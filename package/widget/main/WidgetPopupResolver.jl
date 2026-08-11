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
bubbles up to `WindowManagingProjection`, which opens the popup window — the same
window route the tooltip already uses.

Transparent on print and for reference mapping; only the reader does work. Mirrors
how `HoverProbeProjection` produces window ops from the content level.
"""
module WidgetPopupResolverProjectionModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward,
                              Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, ComputedCell
import ..ScreenDocumentModule: OpenPopupOperation, OpenWindowOperation
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

# Transparent: `output` forwards the child's output through a cell so the IoMap
# keeps its identity while the child re-derives (AR-STABLE-IOMAP-IDENTITY).
@iomap struct WidgetPopupResolverProjectionIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::WidgetPopupResolverProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    WidgetPopupResolverProjectionIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::WidgetPopupResolverProjection, recursion, change::Intent,
                         iomap::WidgetPopupResolverProjectionIoMap)
    res = read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)
    op = res isa Intent ? res.operation : res
    op isa OpenPopupOperation || return res isa Intent ? res : Intent(change.gesture, op)
    pt = anchor_point(iomap.child_iomap, op.anchor)
    # Anchor unresolved (the trigger's reference has no graphics image): drop the
    # open rather than place the popup at a wrong (0,0).
    pt === nothing && return Intent(change.gesture, nothing)
    x, y = pt
    win = OpenWindowOperation(; id=op.id, x=x + op.dx, y=y + op.dy,
                              width=op.width, height=op.height,
                              style=:floating, auto_dismiss=op.auto_dismiss,
                              content=op.content)
    Intent(change.gesture, win)
end

read_intent(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping (passthrough — transparent on print) ─────────────────

map_reference_forward(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(p::WidgetPopupResolverProjection, iomap::WidgetPopupResolverProjectionIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

end # module
