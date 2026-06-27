"""
    WidgetPopupResolverProjectionModule

A content-level seam that turns an anchor-relative [`OpenPopupOperation`] into an
absolute [`OpenWindowOperation`]. It wraps the window's content projection, so it
sits at the root of that content and holds the content iomap — the level that can
resolve a widget reference to graphics coordinates (the deep trigger reader
cannot; it only knows local coordinates).

When a trigger (e.g. a `WidgetSelect`) emits an `OpenPopupOperation` carrying an
`anchor` reference + an offset, this seam resolves the anchor to the widget's
absolute position via [`anchor_point`] (which rides `map_reference_forward`),
adds the offset, and emits an `OpenWindowOperation` at that position. That op then
bubbles up to `WindowManagerProjection`, which opens the popup window — the same
window route the tooltip already uses.

Transparent on print and for reference mapping; only the reader does work. Mirrors
how `HoverProbeProjection` produces window ops from the content level.
"""
module WidgetPopupResolverProjectionModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward,
                              Projection, Change, as_change
import ..IoMapApiModule: IoMap
import ..OperationModule: OpenPopupOperation, OpenWindowOperation
import ..WidgetToGraphicsModule: anchor_point

export WidgetPopupResolverProjection, WidgetPopupResolverProjectionIoMap

struct WidgetPopupResolverProjection <: Projection
    inner::Projection
end

"""
    WidgetPopupResolverProjection(; inner)

Wrap `inner` (the window's content projection). Place this at the content root so
it can resolve anchors against the whole content.
"""
WidgetPopupResolverProjection(; inner::Projection) = WidgetPopupResolverProjection(inner)

struct WidgetPopupResolverProjectionIoMap <: IoMap
    projection::WidgetPopupResolverProjection
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function projection_print(p::WidgetPopupResolverProjection, recursion, input, ctx)
    child_iomap = projection_print(p.inner, recursion, input, ctx)
    WidgetPopupResolverProjectionIoMap(p, input, child_iomap.output, child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function projection_read(p::WidgetPopupResolverProjection, recursion, change::Change,
                         iomap::WidgetPopupResolverProjectionIoMap)
    res = projection_read(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    op = res isa Change ? res.operation : res
    op isa OpenPopupOperation || return res isa Change ? res : Change(change.gesture, op)
    pt = anchor_point(iomap.child_iomap, op.anchor)
    # Anchor unresolved (the trigger's reference has no graphics image): drop the
    # open rather than place the popup at a wrong (0,0).
    pt === nothing && return Change(change.gesture, nothing)
    x, y = pt
    win = OpenWindowOperation(; id=op.id, x=x + op.dx, y=y + op.dy,
                              width=op.width, height=op.height,
                              style=:floating, auto_dismiss=op.auto_dismiss,
                              content=op.content)
    Change(change.gesture, win)
end

projection_read(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# ── Reference mapping (passthrough — transparent on print) ─────────────────

map_reference_forward(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

end # module
