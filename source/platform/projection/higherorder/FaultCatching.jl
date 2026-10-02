# Fragment of `ProjectionAlgebraModule` — the fault barrier inside the pipeline.
#
# **The point the whole design turns on.** A printer does not throw when
# `print_document` runs. It builds a graph of cells and returns. It throws later,
# inside one of those cells, while a consumer reads the output — one frame later,
# or a hundred. By then the barrier has returned as well, so it is not on the
# stack of the read that fails, and a `try` around the print catches almost
# nothing.
#
# So the barrier prints its part inside a fault scope (`run_in_fault_scope`).
# Each computation made there keeps the barrier, and the computation that throws
# hands its fault to it, whatever read reached the cell. The barrier records the
# fault and goes on the list of the editor. The exception goes on up the stack as
# a `RecordedFaultException`, which no barrier above records again, and the frame
# that read it loses that read.
#
# Between two frames the editor shows the mark of each barrier on its list
# (`show_barrier_mark!`). The barrier writes its output cell, so its parent reads
# the mark, and nothing reads the cells that failed. The mark stays until the
# editor tries the part again (`retry_barrier_print!`), after an operation or
# when a person clicks the mark, and the part prints.
#
# A fault inside `print_document` itself is caught there, and the mark stands at
# once. A computation must not write a cell, so the barrier records into the
# kernel's `FaultStore`, a plain object outside the reactive graph, and the editor
# writes the log and the output cells on its own task.

"""
    FaultCatchingProjection(; inner, substitute = nothing)

Wrap `inner` so a fault in it costs one part rather than the editor.

Put one at every recursion point and at every step of a chain:

    ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(),
                                                    substitute = FaultToSyntax())),
        RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(),
                                                    substitute = FaultToText())),
        FaultCatchingProjection(inner = TextToGraphics(measure = measure),
                                substitute = FaultToGraphics()))

Each call of `print_document` is the barrier of one part: at a recursion point,
of one node. A fault in a cell that the part built goes to the barrier of that
part, whatever stage or reader reached the cell, and the mark stands in place of
that part from the next frame on.

**Give every one of them a `substitute`.** It is not a decoration. With no
substitute the mark is a bare `FaultReport`. The next step does not know that
type, throws, and its own barrier fires, so one cause makes a fault at each step.
A parent printer often reads the output of its child as well — it measures a
width, it counts a length — and a parent handed a `FaultReport` throws in its own
cell, so its mark takes the place of the whole parent. A substitute keeps the
output of the child a real document of the right domain, which the parent can
measure.

Do not lean on the throw downstream either: a step whose type dispatcher ends in
an `Any` entry will not throw on a `FaultReport`. It prints something wrong, and
quietly.

The projection reads the store from the printer context under `:fault_store`,
the policy under `:fault_policy`, and the list of the editor under
`:noted_barriers`, which `Editor` puts there. With no list, a fault in
`print_document` still shows its mark at once, but a fault in a cell of the
output goes on up as an exception, because nothing would show the mark. With no
store, the fault is not collected.

It catches nothing and sets no scope under a policy whose `is_barrier_enabled` is
false, which is what `make_strict_fault_policy()` gives a test editor, so a broken
projection fails its test. A context with no policy is the same as the strict
policy, for the same reason. The barrier still wraps the IoMap of its part then,
so a test sees the IO maps that a running editor has. It never catches an
exception that `is_passthrough_exception` names, such as an interrupt or a
request to quit.

See also `FaultReport`, `FaultLog` and the kernel's `FaultStore`.
"""
struct FaultCatchingProjection <: Projection
    inner::Any
    substitute::Any
end

FaultCatchingProjection(; inner, substitute = nothing) =
    FaultCatchingProjection(inner, substitute)

# What a barrier knows about the print of its part, which changes when a fault
# comes and when the part prints again.
#
# `fault` and `report` are `nothing` while the part prints. `report` is the mark
# as a document, kept rather than made again on demand, because a selection names
# it by identity: a report made for each press would name a different object every
# time, and the selection would be lost on the next frame. `failed_computation` is
# the function of the computation that threw, which a retry runs again, and
# `nothing` for a fault in the print. `computation` computes the output of the
# inner IoMap, and was made in the scope of the barrier. `is_noted` holds from the
# fault until the part prints again, so a part whose cells fail twice goes on the
# list once. `is_retrying` holds while a retry runs. `can_show_mark` is false
# after the substitute failed to draw the mark. `enclosing` is the scope that held
# when the barrier printed, the barrier of the part around this one, or `nothing`:
# a fault that this barrier can not show goes there.
mutable struct _FaultBarrierState
    enclosing::Any
    inner_iomap::Any
    computation::Any
    fault::Any
    report::Any
    failed_computation::Any
    is_noted::Bool
    is_retrying::Bool
    can_show_mark::Bool
end

_FaultBarrierState(enclosing) =
    _FaultBarrierState(enclosing, nothing, nothing, nothing, nothing, nothing, false, false,
                       true)

# The fields are plain and not reactive on purpose: a projection in a reactive
# field becomes a computation, and a reader that then calls it with no arguments
# gets a different thing than it asked for. `GestureLogRecordingProjection` keeps
# its filter the same way. `output` is the one reactive field: it computes the
# output of the part, or holds the mark. `store`, `policy` and `noted` are the
# ones the printer context held, because the reader and the maps get no context.
# `recursion` and `context` are those of the print, because a retry prints again.
@iomap struct FaultCatchingIoMap
    projection::ImmutableCell{Any}
    input::ImmutableCell{Any}
    output::Cell
    store::ImmutableCell{Any}
    policy::ImmutableCell{Any}
    noted::ImmutableCell{Any}
    recursion::ImmutableCell{Any}
    context::ImmutableCell{Any}
    state::ImmutableCell{Any}
end

# Whether the barrier takes `exception` rather than let it go on.
_is_fault_caught(policy::FaultPolicy, exception) =
    policy.is_barrier_enabled && !is_passthrough_exception(exception)

_get_inner_iomap(barrier::FaultCatchingIoMap) = barrier.state.inner_iomap

# The mark of this part as a document, or `nothing` while the part prints.
_get_mark_report(barrier::FaultCatchingIoMap) = barrier.state.report

# While the part prints, the barrier adds nothing to its output, so a reader that
# looks at the IoMap of a child sees the IoMap of the part. A mark is the barrier's
# own output.
function get_content_iomap(barrier::FaultCatchingIoMap)
    inner = _get_inner_iomap(barrier)
    (inner === nothing || _get_mark_report(barrier) !== nothing) && return barrier
    get_content_iomap(inner)
end

# ── Printer ──────────────────────────────────────────────────────────────────

# The output cell is new and nothing reads it yet, so the print writes it with no
# reader to invalidate, as the template engine writes the cell of its IoMap.
function print_document(p::FaultCatchingProjection, recursion, input, ctx)
    barrier = FaultCatchingIoMap(p, input, Cell(nothing),
                                 get_property(ctx, :fault_store, nothing),
                                 get_property(ctx, :fault_policy, make_strict_fault_policy()),
                                 get_property(ctx, :noted_barriers, nothing),
                                 recursion, ctx, _FaultBarrierState(find_fault_scope()))
    if barrier.policy.is_barrier_enabled
        printed = try
            _print_in_scope(barrier)
        catch exception
            _is_fault_caught(barrier.policy, exception) || rethrow()
            _take_print_fault!(barrier, exception, catch_backtrace())
            return barrier
        end
        _show_part!(barrier, printed...)
    else
        inner = print_document(p.inner, recursion, input, ctx)
        _show_part!(barrier, inner, Computation(() -> inner.output))
    end
    barrier
end

# The inner IoMap of the part, printed in the scope of the barrier, and the
# computation of its output, made in the same scope.
function _print_in_scope(barrier::FaultCatchingIoMap)
    p = barrier.projection
    run_in_fault_scope(barrier) do
        inner = print_document(p.inner, barrier.recursion, barrier.input, barrier.context)
        (inner, Computation(() -> inner.output))
    end
end

function _show_part!(barrier::FaultCatchingIoMap, inner, computation)
    state = barrier.state
    state.inner_iomap = inner
    state.computation = computation
    state.fault = nothing
    state.report = nothing
    state.failed_computation = nothing
    state.is_noted = false
    getfield(barrier, :output)[] = computation
    nothing
end

# A fault in the print itself: the part has no IoMap, and the mark stands at once.
# A `RecordedFaultException` is a fault that another barrier took while this print
# read its cell; that barrier shows it, and this one shows its own mark until the
# parent prints the part again, with no second record. The mark is drawn here,
# outside every `try`, so a substitute that throws goes on up as the fault of this
# print.
function _take_print_fault!(barrier::FaultCatchingIoMap, exception, traceback)
    state = barrier.state
    state.inner_iomap = nothing
    state.computation = nothing
    state.failed_computation = nothing
    state.fault = if exception isa RecordedFaultException
        make_fault_record(:print; origin = barrier.projection.inner,
                          reference = barrier.context.reference,
                          exception = exception.exception)
    else
        _take_fault(barrier.store, barrier.projection.inner, barrier.context.reference,
                    exception, traceback)
    end
    _show_mark!(barrier)
    _note_barrier!(barrier)
end

# Record the fault and answer it. The store answers `nothing` when it is full or
# when there is none, and a mark still has to be drawn, so a record is made
# either way. The traceback is handed over raw: the store formats one for a key
# it has not seen, and a repeat needs none.
function _take_fault(store, origin, reference, exception, traceback)
    record = record_fault!(store, :print; origin, reference, exception, traceback)
    record === nothing || return record
    make_fault_record(:print; origin, reference, exception, traceback)
end

# The projection that printed the part: the one the inner IoMap names, which is
# the rule that a dispatcher chose, or the inner projection of the barrier.
function _get_fault_origin(barrier::FaultCatchingIoMap)
    inner = _get_inner_iomap(barrier)
    projection = inner === nothing ? nothing : get_iomap_projection(inner)
    projection === nothing ? barrier.projection.inner : projection
end

# Put the barrier on the list of the editor once, so the next drain shows its mark
# and the retry after an operation reaches it.
function _note_barrier!(barrier::FaultCatchingIoMap)
    state, noted = barrier.state, barrier.noted
    (noted === nothing || state.is_noted) && return nothing
    state.is_noted = true
    push!(noted, barrier)
    nothing
end

# The report is kept only when its mark is drawn, so a part whose mark failed to
# draw still reads as a part that prints, and its faults go to the scope above.
function _show_mark!(barrier::FaultCatchingIoMap)
    state, p = barrier.state, barrier.projection
    state.report === nothing || return nothing
    report = FaultReport(state.fault;
                         retry = ReplaceViewStateOperation(RetryBarrierPrintOperation(barrier)))
    mark = p.substitute === nothing ? report :
           print_document(p.substitute, p.substitute, report, barrier.context).output
    state.report = report
    getfield(barrier, :output)[] = mark
    nothing
end

# A cell that the part built threw while something read it. The barrier records
# the fault and goes on the list, and the editor shows the mark between two
# frames. During a retry the barrier takes the fault with no record. A part that
# shows its mark is read only by its retry, so a read from anywhere else, and a
# fault of a part whose mark can not be drawn, go to the barrier that encloses
# this one. The cells of a part travel by reference through the stages after it,
# so the stack of the read that fails can hold no other barrier. With no list,
# nothing would show the mark, so the barrier lets the fault go on.
function record_computation_fault!(barrier::FaultCatchingIoMap, computation, exception;
                                   traceback)
    state = barrier.state
    state.is_retrying && return true
    barrier.noted === nothing && return false
    (state.report === nothing && state.can_show_mark) ||
        return _record_in_enclosing_scope!(barrier, computation, exception; traceback)
    state.is_noted && return true
    state.fault = _take_fault(barrier.store, _get_fault_origin(barrier),
                              barrier.context.reference, exception, traceback)
    state.failed_computation = computation
    _note_barrier!(barrier)
    true
end

function _record_in_enclosing_scope!(barrier::FaultCatchingIoMap, computation, exception;
                                     traceback)
    enclosing = barrier.state.enclosing
    enclosing === nothing && return false
    record_computation_fault!(enclosing, computation, exception; traceback)
end

# The substitute that draws the mark can throw too. Its fault is recorded, and the
# part keeps its output, so the next read of the bad cell goes to the barrier
# that encloses it, which draws its own mark in a larger place.
function show_barrier_mark!(barrier::FaultCatchingIoMap)
    try
        _show_mark!(barrier)
    catch exception
        _is_fault_caught(barrier.policy, exception) || rethrow()
        state = barrier.state
        state.can_show_mark = false
        state.is_noted = false
        record_fault!(barrier.store, :print; origin = barrier.projection.substitute,
                      exception, traceback = catch_backtrace())
    end
    nothing
end

function retry_barrier_print!(barrier::FaultCatchingIoMap)
    state = barrier.state
    state.report === nothing && return true
    state.is_retrying = true
    try
        printed = _try_part_again(barrier)
        printed === nothing && return false
        _show_part!(barrier, printed...)
        return true
    finally
        state.is_retrying = false
    end
end

# The inner IoMap and the computation of its output when the part works again, or
# `nothing`. A fault in a cell runs the function of that computation again. A
# fault in the print prints the part again, and reads its output, as its parent
# reads it first.
function _try_part_again(barrier::FaultCatchingIoMap)
    state = barrier.state
    try
        if state.inner_iomap === nothing || state.failed_computation === nothing
            inner, computation = _print_in_scope(barrier)
            inner.output
            return (inner, computation)
        end
        state.failed_computation()
        return (state.inner_iomap, state.computation)
    catch exception
        _is_fault_caught(barrier.policy, exception) || rethrow()
        return nothing
    end
end

"""
    RetryBarrierPrintOperation(barrier)

Try again the part whose mark a person clicked: the barrier runs the computation
that failed again, or prints its part again, and the part shows its output when
that works. The mark stays when it fails, and no fault is recorded. A reader
answers it inside `ReplaceViewStateOperation`, so a history does not record it.
"""
struct RetryBarrierPrintOperation <: Operation
    barrier::FaultCatchingIoMap
end

evaluate_operation(editor, operation::RetryBarrierPrintOperation) =
    (retry_barrier_print!(operation.barrier); nothing)

# ── Reader ───────────────────────────────────────────────────────────────────

_is_plain_left_click(gesture) =
    gesture isa MouseClick && gesture.button === :left && gesture.modifiers == ModifierKeys()

# An Alt+press names a mark, as it names anything else on the screen: the report
# is not a child of the part that failed, and no field or index reaches it, so
# the path is a drawn-object step from that part. A plain click tries the part
# again. Every other gesture goes to the bindings of the report, which answer the
# rest of a pointer, the window that says the whole fault and the menu, and
# decline the rest, so the layer above gets its turn.
function _read_mark_gesture(barrier::FaultCatchingIoMap, report, gesture)
    is_whole_selection_press(gesture) &&
        return ReplaceSelectionOperation(make_output_reference(barrier.input, report,
                                                               EmptyReference()))
    _is_plain_left_click(gesture) && return report.retry
    read_gesture(report, gesture)
end

# A fault that a barrier recorded already is not recorded again where a reader or
# a map reaches it.
function _record_unrecorded_fault!(barrier::FaultCatchingIoMap, site::Symbol, origin,
                                   reference, exception, traceback)
    exception isa RecordedFaultException && return nothing
    record_fault!(barrier.store, site; origin, reference, exception, traceback)
    nothing
end

# A reader that throws is a reader that declined. The gesture is answered with
# no operation, which is what every reader answers for a gesture it does not
# understand, so the layer above still gets its turn.
function read_intent(p::FaultCatchingProjection, recursion, change::Intent,
                     barrier::FaultCatchingIoMap)
    report = _get_mark_report(barrier)
    report === nothing ||
        return Intent(change.gesture, _read_mark_gesture(barrier, report, change.gesture))
    inner = _get_inner_iomap(barrier)
    inner === nothing && return Intent(change.gesture, nothing)
    try
        read_intent(p.inner, recursion, change, inner)
    catch exception
        _is_fault_caught(barrier.policy, exception) || rethrow()
        _record_unrecorded_fault!(barrier, :read, p.inner, nothing, exception,
                                  catch_backtrace())
        Intent(change.gesture, nothing)
    end
end

read_intent(p::FaultCatchingProjection, barrier::FaultCatchingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), barrier).operation

# ── Reference mapping ────────────────────────────────────────────────────────

# `nothing` is the existing answer for "this reference has no image", which is
# exactly true of a part that failed: no edit can address a part whose value
# nobody could draw. The mark itself is the one thing that can be named, and it
# is named by the drawn-object step below, whose image is the whole output of
# this part.
function map_reference_forward(p::FaultCatchingProjection,
                               barrier::FaultCatchingIoMap, reference)
    _names_fault_mark(barrier, reference) && return EmptyReference()
    _get_mark_report(barrier) === nothing || return nothing
    _map_through_inner(p, barrier, reference, map_reference_forward)
end

function map_reference_backward(p::FaultCatchingProjection,
                                barrier::FaultCatchingIoMap, reference)
    _get_mark_report(barrier) === nothing || return nothing
    _map_through_inner(p, barrier, reference, map_reference_backward)
end

function _map_through_inner(p::FaultCatchingProjection, barrier::FaultCatchingIoMap,
                            reference, map)
    inner = _get_inner_iomap(barrier)
    inner === nothing && return nothing
    try
        map(p.inner, inner, reference)
    catch exception
        _is_fault_caught(barrier.policy, exception) || rethrow()
        _record_unrecorded_fault!(barrier, :map, p.inner, reference, exception,
                                  catch_backtrace())
        nothing
    end
end

# Whether `reference` names the mark of this part: one drawn-object step, whose
# object is the report this IoMap holds.
function _names_fault_mark(barrier::FaultCatchingIoMap, reference)
    report = _get_mark_report(barrier)
    report === nothing && return false
    reference isa ConcreteReference || return false
    step = strip_reference_types(reference).head
    step isa OutputReferenceStep && step.node === report
end
