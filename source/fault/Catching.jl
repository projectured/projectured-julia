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
@iomap struct FaultCatchingIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    store::Any
    fault::Any
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
        early === nothing ||
            return (output = _print_fault_mark(p, early, ctx), fault = early)
        try
            (output = inner.output, fault = nothing)
        catch exception
            late = _take_fault(store, p.inner, reference, exception, catch_backtrace())
            (output = _print_fault_mark(p, late, ctx), fault = late)
        end
    end
    FaultCatchingIoMap(p, input,
                       ComputedCell(() -> guarded[].output),
                       inner, store,
                       ComputedCell(() -> guarded[].fault))
end

# Record the fault and answer it. The store answers `nothing` when it is full or
# when there is none, and a mark still has to be drawn, so a record is made
# either way. The traceback is handed over raw: the store formats one for a key
# it has not seen, and a repeat needs none.
function _take_fault(store, origin, reference, exception, traceback)
    record = record_fault!(store, :print, origin, reference, exception, traceback)
    record === nothing || return record
    make_fault_record(:print, origin, reference, exception, traceback)
end

# **This is called from outside the `try` above, deliberately.** A substitute
# that itself throws is not caught a second time. The exception leaves the thunk
# and reaches the editor's frame barrier, which skips the paint and reports on
# the console; the screen keeps the frame before it, the print-failure counter
# grows, and the safe mode is what bounds the repeat. A barrier that can not
# fail is a barrier that can lie.
function _print_fault_mark(p::FaultCatchingProjection, record, ctx)
    report = FaultReport(record)
    p.substitute === nothing && return report
    print_document(p.substitute, p.substitute, report, ctx).output
end

# ── Reader ───────────────────────────────────────────────────────────────────

# A reader that throws is a reader that declined. The gesture is answered with
# no operation, which is what every reader answers for a gesture it does not
# understand, so the layer above still gets its turn.
function read_intent(p::FaultCatchingProjection, recursion, change::Intent,
                     iomap::FaultCatchingIoMap)
    inner_iomap = iomap.inner_iomap
    inner_iomap === nothing && return Intent(change.gesture, nothing)
    try
        read_intent(p.inner, recursion, change, inner_iomap)
    catch exception
        record_fault!(iomap.store, :read, p.inner, nothing, exception, catch_backtrace())
        Intent(change.gesture, nothing)
    end
end

read_intent(p::FaultCatchingProjection, iomap::FaultCatchingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ────────────────────────────────────────────────────────

# `nothing` is the existing answer for "this reference has no image", which is
# exactly true of a node that failed. So a mark is inert: the selection does not
# walk into one and no edit can address one.
function map_reference_forward(p::FaultCatchingProjection,
                               iomap::FaultCatchingIoMap, reference)
    iomap.inner_iomap === nothing && return nothing
    try
        map_reference_forward(p.inner, iomap.inner_iomap, reference)
    catch exception
        record_fault!(iomap.store, :map, p.inner, reference, exception, catch_backtrace())
        nothing
    end
end

function map_reference_backward(p::FaultCatchingProjection,
                                iomap::FaultCatchingIoMap, reference)
    iomap.inner_iomap === nothing && return nothing
    try
        map_reference_backward(p.inner, iomap.inner_iomap, reference)
    catch exception
        record_fault!(iomap.store, :map, p.inner, reference, exception, catch_backtrace())
        nothing
    end
end
