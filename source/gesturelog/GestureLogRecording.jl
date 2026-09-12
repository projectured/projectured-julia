"""
    GestureLogRecordingProjectionModule

A transparent decorator that records what the reader chain below it decides.

**Printer** — transparent: it projects the wrapped `inner` and returns its output
unchanged, so the display is exactly the display without the decorator.

**Reader** — it calls the inner reader, records the pair (gesture, operation) in
the [`GestureLog`](GestureLogDocument.jl) when the filter accepts the pair, and returns
the inner result without a change. The decorator never makes an operation of its
own and never consumes a gesture.

Put it at the **root** of the composed projection. The root is the seam where
every operation passes, so a content operation, a window operation and an
operation of a nested application all reach the log. The editor makes the
readability-zoom operation after the pipeline declines the gesture, so that one
operation stays outside the log.

The filter is a plain field of a plain struct, not a reactive field. A
`Function` in a reactive field becomes a thunk and the reader calls it with no
arguments.
"""
module GestureLogRecordingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward,
                              map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, ComputedCell
import ..OperationModule: Operation
import ..GestureLogModule: GestureLog, record_gesture!, default_gesture_log_filter

export GestureLogRecordingProjection, GestureLogRecordingIoMap

"""
    GestureLogRecordingProjection(; inner, log, filter = default_gesture_log_filter)

Decorator over `inner` that records every operation the inner reader makes.
`filter(gesture, operation)` decides what the log keeps; the default drops the
selection operations.
"""
struct GestureLogRecordingProjection <: Projection
    inner::Any
    log::GestureLog
    filter::Any
end

GestureLogRecordingProjection(; inner, log::GestureLog,
                                filter = default_gesture_log_filter) =
    GestureLogRecordingProjection(inner, log, filter)

# Transparent: `output` forwards the inner output through a cell so the IoMap
# keeps its identity while the inner projection re-derives.
@iomap struct GestureLogRecordingIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (transparent) ──────────────────────────────────────────────────

function print_document(p::GestureLogRecordingProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    GestureLogRecordingIoMap(p, input, ComputedCell(() -> inner_iomap.output), inner_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::GestureLogRecordingProjection, recursion, change::Intent,
                     iomap::GestureLogRecordingIoMap)
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    operation = child isa Intent ? child.operation : child
    if operation isa Operation && p.filter(change.gesture, operation)
        record_gesture!(p.log, change.gesture, operation)
    end
    child
end

read_intent(p::GestureLogRecordingProjection, iomap::GestureLogRecordingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping (transparent — the output is the inner output) ───────

map_reference_forward(p::GestureLogRecordingProjection,
                      iomap::GestureLogRecordingIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::GestureLogRecordingProjection,
                       iomap::GestureLogRecordingIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

end # module
