# Fragment of `FaultViewModule` — the last guarantee.
#
# When the printer has failed on every frame for long enough that no repair
# helped, the editor puts its projection aside and this one takes its place. It
# ignores the document and draws the fault list, so a person reads what went
# wrong instead of looking at a window that stopped moving.
#
# It is also what bounds a substitute that can not itself be printed. That case
# re-raises on every frame by design, so the print-failure count climbs, and
# this is what the count is counting towards.

"""
    FaultSafeModeProjection(; log, content = …)

Shows `log` whatever it is given.

It ignores its input rather than projecting it, because its input is the
document whose projection just failed. The reader declines every gesture and the
mappers answer no image, so nothing in the safe mode can edit anything.

The editor reaches it through `make_safe_mode_projection`, not by name.
"""
struct FaultSafeModeProjection <: Projection
    log::FaultLog
    content::Any
end

FaultSafeModeProjection(; log::FaultLog,
                          content = make_fault_log_content_projection()) =
    FaultSafeModeProjection(log, content)

@iomap struct FaultSafeModeIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

function print_document(p::FaultSafeModeProjection, recursion, input, ctx)
    inner = print_document(p.content, nothing, p.log, ctx)
    FaultSafeModeIoMap(p, input, Cell(@computation inner.output), inner)
end

read_intent(::FaultSafeModeProjection, recursion, change::Intent,
            ::FaultSafeModeIoMap) = Intent(change.gesture, nothing)

read_intent(::FaultSafeModeProjection, ::FaultSafeModeIoMap, payload) = nothing

map_reference_forward(::FaultSafeModeProjection, ::FaultSafeModeIoMap, reference) = nothing
map_reference_backward(::FaultSafeModeProjection, ::FaultSafeModeIoMap, reference) = nothing

"""
    make_safe_mode_projection(store) -> FaultSafeModeProjection

The kernel's safe-mode seam, answered.

The log starts with every record the store already holds, and the store keeps
feeding it, so a fault raised while the safe mode runs appears in it too.
"""
function FaultModule.make_safe_mode_projection(store::FaultStore)
    log = FaultLog()
    for record in get_fault_records(store)
        append_fault!(log, record)
    end
    attach_fault_target!(store, log)
    FaultSafeModeProjection(log = log)
end
