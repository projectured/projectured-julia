# Fragment of `FaultViewModule` — the barrier inside the pipeline.
#
# **The point the whole design turns on.** A printer does not throw when
# `print_document` runs. It builds a graph of thunks and returns. It throws
# later, inside one of those thunks, while the renderer pulls the output — one
# frame later, or a hundred. So a `try` around the call to `print_document`
# catches almost nothing, and the barrier must sit inside the thunk that derives
# the output. Both are here, because a child can fail at either moment.
#
# What the catch answers is a value, not an exception, and that is what makes
# the rest fall out of the reactive engine for nothing:
#
#   • the engine caches the mark, so the thunk does not run again and does not
#     throw again — without this the read repeats every frame and the editor
#     spins at a hundred faults a second;
#   • the engine invalidates the mark exactly as it invalidates any value, so
#     when the input that caused the fault changes the thunk runs again and the
#     real output comes back by itself;
#   • the exception never escapes the cell, so no other read is aborted and the
#     rest of the cached graph is untouched.
#
# A thunk may not write a cell, so the catch writes the kernel's `FaultStore`
# instead: a plain object outside the reactive graph, with no dependents to
# invalidate and a keyed write that a thunk running ten times leaves alone. The
# editor's frame drains it into a log document afterwards, on its own task.

"""
    FaultCatchingProjection(; inner, substitute = nothing)

Wrap `inner` so a fault in it costs one node rather than the editor.

Put one at every recursion point and at every step of a chain:

    ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(),
                                                    substitute = FaultToSyntax())),
        RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(),
                                                    substitute = FaultToText())),
        FaultCatchingProjection(inner = TextToGraphics(measure = measure),
                                substitute = FaultToGraphics()))

**Give every one of them a `substitute`.** It is not a decoration, and the two
reasons are the two ways a fault otherwise spreads.

*Down the chain.* With no substitute the output is a bare `FaultReport`, the
next step does not know that type, throws, and its own barrier fires. Four steps
make four records for one cause. Bounded, survivable, and not the design.

*Out to the siblings, which is worse.* A parent printer often reads its child's
output — it measures a width, it counts a length. A parent handed a
`FaultReport` throws in its **own** thunk, so its barrier fires and one mark
replaces the whole parent subtree. A substitute keeps the child's output a real
document of the right domain, which the parent can measure, so containment stays
at the one node that failed.

Do not lean on the throw downstream either: a step whose type dispatcher ends in
an `Any` entry will not throw on a `FaultReport`. It prints something wrong, and
quietly.

The projection reads the store from the printer context under `:fault_store`,
which `Editor` puts there. Given none, it still runs and still substitutes; the
fault is then simply not collected.

See also `FaultReport`, `FaultLog` and the kernel's `FaultStore`.
"""
struct FaultCatchingProjection <: Projection
    inner::Any
    substitute::Any
end

FaultCatchingProjection(; inner, substitute = nothing) =
    FaultCatchingProjection(inner, substitute)

# The fields are plain and not reactive on purpose: a projection in a reactive
# field becomes a thunk, and a reader that then calls it with no arguments gets
# a different thing than it asked for. `GestureLogRecordingProjection` keeps its
# filter the same way.
# `fault` is part of the record on purpose, and nothing in this package reads
# it. An IoMap is what a projection answers about one node, and "did this node
# fail, and with what" is exactly that kind of question. A decorator above can
# ask without walking the output looking for a mark. `inner_iomap` is `nothing`
# when the child could not even build its own, which is the other thing a
# consumer has to be able to tell apart.
#
# `report` is the mark as a document, and `nothing` while the node draws. It is
# kept rather than made again on demand, because a selection names it by
# identity: a report made for each press would name a different object every
# time, and the selection would be lost on the next frame.
@iomap struct FaultCatchingIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    store::Any
    fault::Any
    report::Any
end

# ── Printer ──────────────────────────────────────────────────────────────────

function print_document(p::FaultCatchingProjection, recursion, input, ctx)
    store = get_property(ctx, :fault_store, nothing)
    reference = ctx.reference
    inner = nothing
    early = nothing              # a fault raised while the child built its IoMap
    try
        inner = print_document(p.inner, recursion, input, ctx)
    catch exception
        early = _take_fault(store, p.inner, reference, exception, catch_backtrace())
    end
    guarded = ComputedCell() do
        if early !== nothing
            report = FaultReport(early)
            return (output = _print_fault_mark(p, report, ctx), fault = early, report = report)
        end
        try
            (output = inner.output, fault = nothing, report = nothing)
        catch exception
            late = _take_fault(store, p.inner, reference, exception, catch_backtrace())
            report = FaultReport(late)
            (output = _print_fault_mark(p, report, ctx), fault = late, report = report)
        end
    end
    FaultCatchingIoMap(p, input,
                       ComputedCell(() -> guarded[].output),
                       inner, store,
                       ComputedCell(() -> guarded[].fault),
                       ComputedCell(() -> guarded[].report))
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

# **This is called from outside the `try` above, deliberately.** A substitute
# that itself throws is not caught a second time. The exception leaves the thunk
# and reaches the editor's frame barrier, which skips the paint and reports on
# the console; the screen keeps the frame before it, the print-failure counter
# grows, and the safe mode is what bounds the repeat. A barrier that can not
# fail is a barrier that can lie.
function _print_fault_mark(p::FaultCatchingProjection, report::FaultReport, ctx)
    p.substitute === nothing && return report
    print_document(p.substitute, p.substitute, report, ctx).output
end

# ── Reader ───────────────────────────────────────────────────────────────────

# A reader that throws is a reader that declined. The gesture is answered with
# no operation, which is what every reader answers for a gesture it does not
# understand, so the layer above still gets its turn.
function read_intent(p::FaultCatchingProjection, recursion, change::Intent,
                     iomap::FaultCatchingIoMap)
    # A mark is a thing on the screen like any other, so an Alt+press names it.
    # The report is not a child of the node that failed, and no field or index
    # reaches it, so the path is a drawn-object step from that node.
    report = _mark_report(iomap)
    if report !== nothing && is_whole_selection_press(change.gesture)
        return Intent(change.gesture,
                      ReplaceSelectionOperation(make_output_reference(iomap.input, report,
                                                                      EmptyReference())))
    end
    inner_iomap = iomap.inner_iomap
    inner_iomap === nothing && return Intent(change.gesture, nothing)
    try
        read_intent(p.inner, recursion, change, inner_iomap)
    catch exception
        record_fault!(iomap.store, :read; origin = p.inner, exception,
                      traceback = catch_backtrace())
        Intent(change.gesture, nothing)
    end
end

read_intent(p::FaultCatchingProjection, iomap::FaultCatchingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ────────────────────────────────────────────────────────

# `nothing` is the existing answer for "this reference has no image", which is
# exactly true of a node that failed: no edit can address a node whose value
# nobody could draw. The mark itself is the one thing that can be named, and it
# is named by the drawn-object step below, whose image is the whole output of
# this node.
function map_reference_forward(p::FaultCatchingProjection,
                               iomap::FaultCatchingIoMap, reference)
    _names_fault_mark(iomap, reference) && return EmptyReference()
    iomap.inner_iomap === nothing && return nothing
    try
        map_reference_forward(p.inner, iomap.inner_iomap, reference)
    catch exception
        record_fault!(iomap.store, :map; origin = p.inner, reference, exception,
                      traceback = catch_backtrace())
        nothing
    end
end

# The mark of this node as a document, or `nothing` while the node draws. The
# field holds a cell, as every field of an io map does.
function _mark_report(iomap::FaultCatchingIoMap)
    report = getfield(iomap, :report)
    report isa Cell ? report[] : report
end

# Whether `reference` names the mark of this node: one drawn-object step, whose
# object is the report this io map holds.
function _names_fault_mark(iomap::FaultCatchingIoMap, reference)
    report = _mark_report(iomap)
    report === nothing && return false
    reference isa ConcreteReference || return false
    step = strip_reference_types(reference).head
    step isa OutputReferenceStep && step.node === report
end

function map_reference_backward(p::FaultCatchingProjection,
                                iomap::FaultCatchingIoMap, reference)
    iomap.inner_iomap === nothing && return nothing
    try
        map_reference_backward(p.inner, iomap.inner_iomap, reference)
    catch exception
        record_fault!(iomap.store, :map; origin = p.inner, reference, exception,
                      traceback = catch_backtrace())
        nothing
    end
end
