"""
    WidgetHoverTrackingProjectionModule

A higher-order projection that wraps a widget pipeline and keeps the
**`hovered` flag of exactly one widget** true as the pointer moves — the piece
container hit-test routing cannot do on its own.

The problem: a container routes a `MouseMove` only to the child under the
pointer (`_route_to_children`), so a widget learns when the pointer *enters* it
but never when it *leaves* (the leaving move goes to whatever is under the
pointer now, or to nothing). Individual widget readers therefore report
"pointer is on me" (`SetWidgetHoverOperation(w, true)`) but cannot clear the
*previously* hovered widget.

This tracker closes the gap centrally, the same shape as `HoverProbeProjection`:

**Printer** — transparent: projects the wrapped document through `inner` and
returns its output unchanged. It remembers the inner iomap so the reader can
reuse it.

**Reader** — on a `MouseMove`, forward the move to `inner`; whatever widget is
under the pointer answers with `SetWidgetHoverOperation(w, true)` (or nothing
over dead space). Compare that widget to the previously-hovered one held in
`last`:

- same widget → nothing (no state change);
- a different widget (or dead space) → a `CompoundOperation` that clears
  `hovered`/`pressed` on the old widget and sets `hovered` on the new one.

Every non-`MouseMove` event passes straight through to `inner`, so clicks,
presses, keys and scroll behave exactly as before.
"""
module WidgetHoverTrackingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward,
                              Projection, Change, as_change
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseMove
import ..WidgetModule: SetWidgetHoverOperation, SetWidgetPressedOperation
import ..OperationModule: CompoundOperation

export WidgetHoverTrackingProjection, WidgetHoverTrackingProjectionIoMap

struct WidgetHoverTrackingProjection <: Projection
    inner::Projection
    # transient state (a Ref so the immutable projection can update it):
    last::Base.RefValue{Any}    # the currently-hovered widget, or nothing
end

"""
    WidgetHoverTrackingProjection(; inner)

Wrap `inner` (the widget pipeline whose hover state should be tracked).
"""
WidgetHoverTrackingProjection(; inner::Projection) =
    WidgetHoverTrackingProjection(inner, Ref{Any}(nothing))

struct WidgetHoverTrackingProjectionIoMap <: IoMap
    projection::WidgetHoverTrackingProjection
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function projection_print(p::WidgetHoverTrackingProjection, recursion, input, ctx)
    child_iomap = projection_print(p.inner, recursion, input, ctx)
    WidgetHoverTrackingProjectionIoMap(p, input, child_iomap.output, child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function projection_read(p::WidgetHoverTrackingProjection, recursion, change::Change,
                         iomap::WidgetHoverTrackingProjectionIoMap)
    event = change.gesture
    if event isa MouseMove
        inner = projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
        inner_op = inner isa Change ? inner.operation : inner
        new_widget = (inner_op isa SetWidgetHoverOperation && inner_op.value) ? inner_op.widget : nothing
        return Change(change.gesture, _track_hover(p, new_widget))
    end
    return projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
end

# 3-arg compatibility shim (tests / hit-test recursion).
projection_read(p::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# Diff the newly-hovered widget against the last one and emit the minimal state
# change: clear the old widget's hover/press, set the new one's hover.
function _track_hover(p::WidgetHoverTrackingProjection, new_widget)
    old = p.last[]
    new_widget === old && return nothing
    ops = Any[]
    if old !== nothing
        push!(ops, SetWidgetHoverOperation(old, false))
        push!(ops, SetWidgetPressedOperation(old, false))
    end
    new_widget === nothing || push!(ops, SetWidgetHoverOperation(new_widget, true))
    p.last[] = new_widget
    isempty(ops) ? nothing : length(ops) == 1 ? ops[1] : CompoundOperation(ops)
end

# ── Reference mapping (passthrough — the tracker is transparent on print) ──

map_reference_forward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::WidgetHoverTrackingProjection, iomap::WidgetHoverTrackingProjectionIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

end # module
