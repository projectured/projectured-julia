"""
    WidgetToGraphicsModule

WidgetDocument → GraphicsCanvas projection. One projection struct per widget
document type, composed via `TypeDispatchingProjection(...)` through the
`WidgetToGraphics()` factory function. Wrap the result in `RecursiveProjection`
at the call site to enable recursive child dispatch.

Each widget projection produces a `GraphicsCanvas` as output. Leaf widgets
emit text and rect elements; container widgets recurse via the `recursion`
argument and nest child canvases. Event routing (e.g. MouseScroll) is
delegated through containers to the appropriate child via hit-testing.

Also contains `WidgetScrollPaneToGraphicsViewport`, a composable projection
that converts a single `WidgetScrollPane` into a `GraphicsViewport`, delegating
the content projection via the recursion argument.
"""
module WidgetToGraphicsModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..ColorModule: StyleColor
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetCheckbox,
                       WidgetButton, WidgetTooltip, WidgetMenu, WidgetMenuItem,
                       WidgetComposite, WidgetShell, WidgetTitlePane, WidgetSplitPane,
                       WidgetTabbedPane, WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
                       Inset, Point2D,
                       ScrollWidgetOperation, SelectTabOperation, SetScrollBarValueOperation
import ..CollectionModule: CellVector, CollectionDocument
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, hit_element_at, layout_none
import ..FontModule: StyleFont
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseScroll, MousePress
import ..OperationModule: ReplaceSelectionOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ProjectionContextModule: child_context
export WidgetLabelToGraphicsCanvas, WidgetTextToGraphicsCanvas,
       WidgetCheckboxToGraphicsCanvas, WidgetButtonToGraphicsCanvas,
       WidgetTooltipToGraphicsCanvas, WidgetMenuToGraphicsCanvas,
       WidgetMenuItemToGraphicsCanvas, WidgetCompositeToGraphicsCanvas,
       WidgetShellToGraphicsCanvas, WidgetTitlePaneToGraphicsCanvas,
       WidgetSplitPaneToGraphicsCanvas, WidgetTabbedPaneToGraphicsCanvas,
       WidgetScrollPaneToGraphicsCanvas, WidgetScrollPaneToGraphicsCanvasIoMap,
       WidgetToolbarToGraphicsCanvas, WidgetScrollBarToGraphicsCanvas,
       WidgetToGraphics,
       WidgetScrollPaneToGraphicsViewport, WidgetScrollPaneToGraphicsViewportIoMap

# ── Projection structs ─────────────────────────────────────────────────────

struct WidgetLabelToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetTextToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetCheckboxToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetButtonToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetTooltipToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetMenuToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
end

struct WidgetMenuItemToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetCompositeToGraphicsCanvas <: Projection end

struct WidgetShellToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
end

struct WidgetTitlePaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
end

struct WidgetSplitPaneToGraphicsCanvas <: Projection end

struct WidgetTabbedPaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
    default_fg::NTuple{4,UInt8}
    selector_fg::NTuple{4,UInt8}
end

struct WidgetScrollPaneToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
end

struct WidgetToolbarToGraphicsCanvas <: Projection
    font::StyleFont
    measure::Function
end

struct WidgetScrollBarToGraphicsCanvas <: Projection
    track_color::NTuple{4,UInt8}
    thumb_color::NTuple{4,UInt8}
end

# ── IoMap for WidgetScrollPane ─────────────────────────────────────────────

struct WidgetScrollPaneToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

# ── Color helpers ──────────────────────────────────────────────────────────

_rgba(c::StyleColor) = (UInt8(round(c.red * 255)), UInt8(round(c.green * 255)), UInt8(round(c.blue * 255)), UInt8(round(c.alpha * 255)))

# ── Box model helpers ──────────────────────────────────────────────────────

"""
Return the (x, y) content-area offset from the widget's outer top-left corner,
i.e. margin + border + padding on each axis.
"""
function _content_offset(w::WidgetDocument)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset
    ox = Int(m.left[]) + Int(brd.left[]) + Int(pad.left[])
    oy = Int(m.top[])  + Int(brd.top[])  + Int(pad.top[])
    (ox, oy)
end

"""
Return the total (horizontal, vertical) space consumed by all box-model layers.
"""
function _inset_total(w::WidgetDocument)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset
    tx = Int(m.left[]) + Int(m.right[]) + Int(brd.left[]) + Int(brd.right[]) +
         Int(pad.left[]) + Int(pad.right[])
    ty = Int(m.top[])  + Int(m.bottom[]) + Int(brd.top[])  + Int(brd.bottom[]) +
         Int(pad.top[])  + Int(pad.bottom[])
    (tx, ty)
end

"""
Push colored rectangles for every non-transparent box-model layer of `w`.
`bx, by` is the widget's outer top-left (outermost edge of margin).
`cw, ch` is the content size (inside padding).
"""
function _push_box_rects!(elems::Vector, w::WidgetDocument,
                          bx::Int, by::Int, cw::Int, ch::Int)
    m   = w.margin::Inset
    brd = w.border::Inset
    pad = w.padding::Inset

    ml, mt, mr, mb = Int(m.left[]),   Int(m.top[]),   Int(m.right[]),  Int(m.bottom[])
    bl, bt, br, bb = Int(brd.left[]), Int(brd.top[]), Int(brd.right[]), Int(brd.bottom[])
    pl, pt, pr, pb = Int(pad.left[]), Int(pad.top[]), Int(pad.right[]), Int(pad.bottom[])

    pw = cw + pl + pr    # padded-content width  (inside border)
    ph = ch + pt + pb    # padded-content height

    mc = w.margin_color
    if mc isa StyleColor
        r, g, blu, a = _rgba(mc)
        total_w = ml + bl + pw + br + mr
        mt > 0 && push!(elems, GraphicsRect(bx,                      by, total_w, mt,  r, g, blu, a))
        mb > 0 && push!(elems, GraphicsRect(bx, by + mt + bt + ph + bb, total_w, mb,  r, g, blu, a))
        ml > 0 && push!(elems, GraphicsRect(bx,              by + mt,   ml, bt + ph + bb, r, g, blu, a))
        mr > 0 && push!(elems, GraphicsRect(bx + ml + bl + pw + br, by + mt, mr, bt + ph + bb, r, g, blu, a))
    end

    bc = w.border_color
    if bc isa StyleColor
        r, g, blu, a = _rgba(bc)
        bx2, by2 = bx + ml, by + mt
        bt > 0 && push!(elems, GraphicsRect(bx2,              by2,         bl + pw + br, bt,  r, g, blu, a))
        bb > 0 && push!(elems, GraphicsRect(bx2, by2 + bt + ph,            bl + pw + br, bb,  r, g, blu, a))
        bl > 0 && push!(elems, GraphicsRect(bx2,         by2 + bt,         bl, ph,           r, g, blu, a))
        br > 0 && push!(elems, GraphicsRect(bx2 + bl + pw, by2 + bt,       br, ph,           r, g, blu, a))
    end

    pc = w.padding_color
    if pc isa StyleColor
        r, g, blu, a = _rgba(pc)
        push!(elems, GraphicsRect(bx + ml + bl, by + mt + bt, pw, ph, r, g, blu, a))
    end
end

# ── Text helpers ───────────────────────────────────────────────────────────

function _push_text!(elems::Vector, font::StyleFont, text::AbstractString,
                     x::Int, y::Int, fg::NTuple{4,UInt8})
    r, g, b, a = fg
    push!(elems, GraphicsText(text, x, y, font, r, g, b, a))
end

function _text_size(measure::Function, font::StyleFont, text::AbstractString)
    measure(text, font)
end

# ── Canvas construction helper ─────────────────────────────────────────────

function _make_canvas(x::Int, y::Int, elems::Vector)
    GraphicsCanvas(Int32(x), Int32(y), Int32(0), Int32(0),
                   CellVector(Cell[Cell(e) for e in elems]),
                   layout_none, true, Cell(nothing))
end

function _make_canvas(x::Int, y::Int, w::Int, h::Int, elems::Vector)
    GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h),
                   CellVector(Cell[Cell(e) for e in elems]),
                   layout_none, true, Cell(nothing))
end

_empty_canvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                 CellVector(), layout_none, true, Cell(nothing))

# ── Event routing helper ──────────────────────────────────────────────────

function _route_to_children(child_entries::Vector, x::Int, y::Int, make_evt)
    for entry in child_entries
        entry === nothing && continue
        (ox, oy, cim) = entry::Tuple{Int,Int,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = projection_read(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return result
    end
    nothing
end

_route_scroll_to_children(child_entries::Vector, evt::MouseScroll) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))

_route_click_to_children(child_entries::Vector, evt::MousePress) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MousePress(evt.button, x, y, evt.modifiers))

# ── WidgetLabel ─────────────────────────────────────────────────────────────

function projection_print(p::WidgetLabelToGraphicsCanvas, w::WidgetLabel, recursion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    text = string(w.content)
    cw, ch = _text_size(p.measure, p.font, text)
    tx, ty = _inset_total(w)
    elems = Any[]
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    _push_text!(elems, p.font, text, cox, coy, p.default_fg)
    SimpleIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), cw + tx, ch + ty, elems))
end

function map_reference_forward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetLabelToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetLabelToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetText ──────────────────────────────────────────────────────────────

function projection_print(p::WidgetTextToGraphicsCanvas, w::WidgetText, recursion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    text = string(w.content)
    cw, ch = _text_size(p.measure, p.font, text)
    tx, ty = _inset_total(w)
    elems = Any[]
    cfc = w.content_fill_color
    if cfc isa StyleColor
        r, g, b, a = _rgba(cfc)
        push!(elems, GraphicsRect(cox, coy, cw, ch, r, g, b, a))
    end
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    _push_text!(elems, p.font, text, cox, coy, p.default_fg)
    SimpleIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), cw + tx, ch + ty, elems))
end

function map_reference_forward(::WidgetTextToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTextToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetTextToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetCheckbox ──────────────────────────────────────────────────────────

function projection_print(p::WidgetCheckboxToGraphicsCanvas, w::WidgetCheckbox, recursion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    text = w.content === true ? "[x]" : "[ ]"
    cw, ch = _text_size(p.measure, p.font, text)
    tx, ty = _inset_total(w)
    elems = Any[]
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    _push_text!(elems, p.font, text, cox, coy, p.default_fg)
    SimpleIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), cw + tx, ch + ty, elems))
end

function map_reference_forward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetCheckboxToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetCheckboxToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetButton ────────────────────────────────────────────────────────────

function projection_print(p::WidgetButtonToGraphicsCanvas, w::WidgetButton, recursion, ctx)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position::Point2D
    sz  = w.size::Point2D
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    text = string(w.content)
    tw, th = _text_size(p.measure, p.font, text)
    bw = max(Int(sz.x[]), tw + tx)
    bh = max(Int(sz.y[]), th + ty)
    cw = max(0, bw - tx)
    ch = max(0, bh - ty)
    elems = Any[]
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    _push_text!(elems, p.font, text, cox, coy, p.default_fg)
    SimpleIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), bw, bh, elems))
end

function map_reference_forward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetButtonToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetButtonToGraphicsCanvas, iomap::SimpleIoMap, evt)
    return nothing
end

# ── WidgetTooltip ───────────────────────────────────────────────────────────

function projection_print(p::WidgetTooltipToGraphicsCanvas, w::WidgetTooltip, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    sz  = w.size::Point2D
    cox, coy = _content_offset(w)
    vw, vh = Int(sz.x[]), Int(sz.y[])
    tx, ty = _inset_total(w)
    cw, ch = max(0, vw - tx), max(0, vh - ty)
    elems = Any[]
    push!(elems, GraphicsRect(0, 0, vw, vh, 0x40, 0x40, 0x40, 0xe0))
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    child_iomaps = Any[]
    content = w.content
    if content isa AbstractString
        _push_text!(elems, p.font, content, cox, coy, p.default_fg)
    elseif content isa WidgetDocument
        cim = projection_print(recursion, content, recursion, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTooltipToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetTooltipToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetMenuItem ──────────────────────────────────────────────────────────

function projection_print(p::WidgetMenuItemToGraphicsCanvas, w::WidgetMenuItem, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    content = w.content
    child_iomaps = Any[]
    elems = Any[]
    if content isa WidgetDocument
        cim = projection_print(recursion, content, recursion, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    else
        text = string(content)
        cw, ch = _text_size(p.measure, p.font, text)
        _push_box_rects!(elems, w, 0, 0, cw, ch)
        _push_text!(elems, p.font, text, cox, coy, p.default_fg)
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetMenuItemToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetMenuItemToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetMenuItemToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetMenu ──────────────────────────────────────────────────────────────

function projection_print(p::WidgetMenuToGraphicsCanvas, w::WidgetMenu, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    y_cursor = coy
    _, item_h = p.measure("M", p.font)
    for item in w.elements
        item isa WidgetDocument || continue
        cim = projection_print(recursion, item, recursion, ctx)
        push!(child_iomaps, (cox, y_cursor, cim))
        push!(elems, _make_canvas(cox, y_cursor, Any[cim.output]))
        y_cursor += item_h
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetMenuToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetMenuToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetMenuToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetComposite ─────────────────────────────────────────────────────────

function projection_print(p::WidgetCompositeToGraphicsCanvas, w::WidgetComposite, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    pos = w.position::Point2D
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    for child in w.elements
        child isa WidgetDocument || continue
        cim = projection_print(recursion, child, recursion, ctx)
        push!(child_iomaps, (cox, coy, cim))
        push!(elems, _make_canvas(cox, coy, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(Int(pos.x[]), Int(pos.y[]), elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetCompositeToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetCompositeToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetCompositeToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetShell ─────────────────────────────────────────────────────────────

function projection_print(p::WidgetShellToGraphicsCanvas, w::WidgetShell, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    cfc = w.content_fill_color
    sz  = w.size
    if cfc isa StyleColor && sz isa Point2D
        r, g, b, a = _rgba(cfc)
        push!(elems, GraphicsRect(cox, coy, Int(sz.x[]), Int(sz.y[]), r, g, b, a))
    end
    content_y = coy
    mb = w.menu_bar
    if mb isa WidgetDocument
        cim = projection_print(recursion, mb, recursion, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, menu_h = p.measure("M", p.font)
        content_y += menu_h
    end
    tb = w.toolbar
    if tb isa WidgetDocument
        cim = projection_print(recursion, tb, recursion, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
        _, toolbar_h = p.measure("M", p.font)
        content_y += toolbar_h + 4
    end
    content = w.content
    if content isa WidgetDocument
        cim = projection_print(recursion, content, recursion, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    end
    tt = w.tooltip
    if tt isa WidgetDocument
        cim = projection_print(recursion, tt, recursion, ctx)
        push!(child_iomaps, (0, 0, cim))
        push!(elems, _make_canvas(0, 0, Any[cim.output]))
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetShellToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetShellToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetShellToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    evt isa MouseScroll && return _route_scroll_to_children(child_iomaps, evt)
    evt isa MousePress  && return _route_click_to_children(child_iomaps, evt)
    nothing
end

# ── WidgetTitlePane ─────────────────────────────────────────────────────────

function projection_print(p::WidgetTitlePaneToGraphicsCanvas, w::WidgetTitlePane, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    elems = Any[]
    child_iomaps = Any[]
    title_text = string(w.title)
    tw, th = _text_size(p.measure, p.font, title_text)
    tfc = w.title_fill_color
    if tfc isa StyleColor
        r, g, b, a = _rgba(tfc)
        push!(elems, GraphicsRect(cox, coy, tw, th, r, g, b, a))
    end
    _push_text!(elems, p.font, title_text, cox, coy, p.default_fg)
    content_y = coy + th
    content = w.content
    if content isa WidgetDocument
        cim = projection_print(recursion, content, recursion, ctx)
        push!(child_iomaps, (cox, content_y, cim))
        push!(elems, _make_canvas(cox, content_y, Any[cim.output]))
    elseif content isa AbstractString
        _push_text!(elems, p.font, content, cox, content_y, p.default_fg)
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTitlePaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetTitlePaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    child_iomaps = iomap.child_iomaps[]::Vector
    _route_scroll_to_children(child_iomaps, evt)
end

# ── WidgetSplitPane ─────────────────────────────────────────────────────────

function projection_print(p::WidgetSplitPaneToGraphicsCanvas, w::WidgetSplitPane, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    orientation = w.orientation::Symbol
    sizes = w.sizes
    child_iomaps = Any[]
    elems = Any[]
    cursor = 0
    splitter_thickness = 3
    splitter_r, splitter_g, splitter_b, splitter_a = 0x88, 0x88, 0x88, 0xff
    splitter_cross = 100000
    n = length(w.elements)
    for (i, child) in enumerate(w.elements)
        child isa WidgetDocument || continue
        cim = projection_print(recursion, child, recursion, ctx)
        if orientation === :horizontal
            push!(child_iomaps, (cox + cursor, coy, cim))
            push!(elems, _make_canvas(cox + cursor, coy, Any[cim.output]))
        else
            push!(child_iomaps, (cox, coy + cursor, cim))
            push!(elems, _make_canvas(cox, coy + cursor, Any[cim.output]))
        end
        slot = (!isempty(sizes) && i <= length(sizes)) ? Int(sizes[i]) : 200
        cursor += slot
        if i < n
            if orientation === :horizontal
                push!(elems, GraphicsRect(cox + cursor - splitter_thickness, coy,
                                          splitter_thickness, splitter_cross,
                                          splitter_r, splitter_g, splitter_b, splitter_a))
            else
                push!(elems, GraphicsRect(cox, coy + cursor - splitter_thickness,
                                          splitter_cross, splitter_thickness,
                                          splitter_r, splitter_g, splitter_b, splitter_a))
            end
        end
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetSplitPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetSplitPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetSplitPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    evt isa MouseScroll && return _route_scroll_to_children(child_iomaps, evt)
    evt isa MousePress  && return _route_click_to_children(child_iomaps, evt)
    nothing
end

# ── WidgetTabbedPane ────────────────────────────────────────────────────────

function projection_print(p::WidgetTabbedPaneToGraphicsCanvas, w::WidgetTabbedPane, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    pairs = w.selector_element_pairs
    child_iomaps = Any[]
    if isempty(pairs)
        return ChildrenIoMap(p, w, _empty_canvas(), Cell(child_iomaps))
    end

    sel_pad = 4
    tabs = Any[]
    for pair in pairs
        label = string(pair[1])
        tw, th = _text_size(p.measure, p.font, label)
        push!(tabs, (label, tw, th))
    end
    tab_h = maximum(t[3] for t in tabs)
    sel_h = tab_h + 2 * sel_pad

    tab_xs = Int[]
    tab_rws = Int[]
    x = cox
    for (_, tw, _) in tabs
        push!(tab_xs, x)
        push!(tab_rws, tw + 2 * sel_pad)
        x += tw + 2 * sel_pad
    end

    sel_cell = getfield(w, :selection)

    _active_idx(sel) = begin
        sel isa ConcreteReferencePath || return 1
        h = sel.head
        h isa RangeReference || return 1
        i = h.start + 1
        1 <= i <= length(tabs) ? i : 1
    end

    selector_cv = CellVector(() -> begin
        active = _active_idx(sel_cell[])
        result = Any[]
        tab_radius = 6
        for i in eachindex(tabs)
            label, _, _ = tabs[i]
            tx, rw = tab_xs[i], tab_rws[i]
            fr, fg, fb, fa = i == active ? (0x33, 0x66, 0xaa, 0xff) : (0x22, 0x22, 0x2a, 0xff)
            br, bg, bb, ba = i == active ? (0xff, 0xff, 0xff, 0xff) : (0x55, 0x55, 0x55, 0xff)
            push!(result, GraphicsRect(tx, coy, rw, sel_h, br, bg, bb, ba;
                                       radius_tl=tab_radius, radius_tr=tab_radius))
            push!(result, GraphicsRect(tx + 1, coy + 1, rw - 2, sel_h - 2, fr, fg, fb, fa;
                                       radius_tl=tab_radius - 1, radius_tr=tab_radius - 1))
            _push_text!(result, p.font, label, tx + sel_pad, coy + sel_pad, p.selector_fg)
        end
        result
    end)

    all_cims = Any[]
    for pair in pairs
        content = pair[2]
        if content !== nothing
            cim = projection_print(recursion, content, recursion, ctx)
            push!(child_iomaps, (cox, coy + sel_h, cim))
            push!(all_cims, cim)
        else
            push!(all_cims, nothing)
        end
    end

    content_cv = CellVector(() -> begin
        active = _active_idx(sel_cell[])
        idx = active == 0 ? 1 : active
        cim = all_cims[idx]
        cim === nothing ? Any[] : Any[_make_canvas(cox, coy + sel_h, Any[cim.output])]
    end)

    canvas = _make_canvas(0, 0, Any[
        GraphicsCanvas(selector_cv, layout_none, true),
        GraphicsCanvas(content_cv,  layout_none, true),
    ])
    ChildrenIoMap(p, w, canvas, Cell(child_iomaps))
end

function map_reference_forward(::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetTabbedPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(p::WidgetTabbedPaneToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    child_iomaps = iomap.child_iomaps[]::Vector
    if evt isa MousePress
        w = iomap.input
        w isa WidgetTabbedPane || return _route_click_to_children(_active_tab_children(iomap, child_iomaps), evt)
        cox, coy = _content_offset(w)
        pairs = w.selector_element_pairs
        if !isempty(pairs)
            sel_pad = 4
            sizes = Tuple{Int,Int}[]
            tab_h = 0
            for pair in pairs
                tw, th = _text_size(p.measure, p.font, string(pair[1]))
                push!(sizes, (tw, th))
                tab_h = max(tab_h, th)
            end
            sel_h = tab_h + 2 * sel_pad
            tab_x = cox
            for (i, (tw, _)) in enumerate(sizes)
                rw = tw + 2 * sel_pad
                if evt.x >= tab_x && evt.x < tab_x + rw && evt.y >= coy && evt.y < coy + sel_h
                    return SelectTabOperation(w, i)
                end
                tab_x += rw
            end
        end
        return _route_click_to_children(_active_tab_children(iomap, child_iomaps), evt)
    end
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(_active_tab_children(iomap, child_iomaps), evt)
end

function _active_tab_children(iomap::ChildrenIoMap, child_iomaps::Vector)
    w = iomap.input
    w isa WidgetTabbedPane || return child_iomaps
    sel = getfield(w, :selection)[]
    sel isa ConcreteReferencePath || return isempty(child_iomaps) ? child_iomaps : child_iomaps[1:1]
    h = sel.head
    h isa RangeReference || return isempty(child_iomaps) ? child_iomaps : child_iomaps[1:1]
    idx = h.start + 1
    1 <= idx <= length(child_iomaps) || return child_iomaps[1:1]
    child_iomaps[idx:idx]
end

# ── WidgetScrollPane ────────────────────────────────────────────────────────

function projection_print(p::WidgetScrollPaneToGraphicsCanvas, w::WidgetScrollPane, recursion, ctx)
    w.visible == false && return WidgetScrollPaneToGraphicsCanvasIoMap(p, w, _empty_canvas(), nothing)
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? Int(pos.x[]) : 0
    py = pos isa Point2D ? Int(pos.y[]) : 0
    vw = sz isa Point2D ? Int(sz.x[]) : 400
    vh = sz isa Point2D ? Int(sz.y[]) : 300
    cox, coy = _content_offset(w)
    scroll_cell = getfield(w, :scroll_position)
    inner_x = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.x[])) end)
    inner_y = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.y[])) end)
    elems = Any[]
    cfc = w.content_fill_color
    if cfc isa StyleColor
        r, g, b, a = _rgba(cfc)
        push!(elems, GraphicsRect(cox, coy, vw, vh, r, g, b, a))
    end
    content_iomap = nothing
    content = w.content
    if content isa Document
        content_iomap = projection_print(recursion, content, recursion, ctx)
        inner_canvas = content_iomap.output::GraphicsCanvas
        inner_elems_cv = inner_canvas.elements
        push!(elems, GraphicsViewport(cox, coy, vw, vh,
                                      GraphicsCanvas(inner_x, inner_y, Int32(0), Int32(0),
                                                     inner_elems_cv isa CellVector ? inner_elems_cv : CellVector(Cell[Cell(inner_canvas)]),
                                                     layout_none, true, Cell(nothing))))
    end
    WidgetScrollPaneToGraphicsCanvasIoMap(p, w, _make_canvas(px, py, elems), content_iomap)
end

function map_reference_forward(::WidgetScrollPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollPaneToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(p::WidgetScrollPaneToGraphicsCanvas, iomap::WidgetScrollPaneToGraphicsCanvasIoMap, evt)
    evt isa MouseScroll || return nothing
    canvas = iomap.output
    # evt coords are already relative to canvas origin (parent routing subtracted position)
    hit_element_at(canvas, evt.x, evt.y) === nothing && return nothing
    _, scroll_step = p.measure("M", p.font)
    if evt.dx != 0 && evt.dy == 0
        return ScrollWidgetOperation(iomap.input, Point2D(-evt.dx * scroll_step, 0))
    else
        return ScrollWidgetOperation(iomap.input, Point2D(0, -evt.dy * scroll_step))
    end
end

# ── WidgetToolbar ───────────────────────────────────────────────────────────

function projection_print(p::WidgetToolbarToGraphicsCanvas, w::WidgetToolbar, recursion, ctx)
    w.visible == false && return ChildrenIoMap(p, w, _empty_canvas(), Cell(Any[]))
    cox, coy = _content_offset(w)
    child_iomaps = Any[]
    elems = Any[]
    x_cursor = cox
    item_gap = 4
    for item in w.elements
        item isa WidgetDocument || continue
        cim = projection_print(recursion, item, recursion, ctx)
        push!(child_iomaps, (x_cursor, coy, cim))
        push!(elems, _make_canvas(x_cursor, coy, Any[cim.output]))
        content = hasproperty(item, :content) ? item.content : nothing
        iw, _ = content !== nothing ? _text_size(p.measure, p.font, string(content)) :
                                      p.measure("    ", p.font)
        x_cursor += iw + item_gap
    end
    ChildrenIoMap(p, w, _make_canvas(0, 0, elems), Cell(child_iomaps))
end

function map_reference_forward(::WidgetToolbarToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetToolbarToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetToolbarToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    evt isa MouseScroll || return nothing
    _route_scroll_to_children(iomap.child_iomaps[]::Vector, evt)
end

# ── WidgetScrollBar ─────────────────────────────────────────────────────────

function projection_print(p::WidgetScrollBarToGraphicsCanvas, w::WidgetScrollBar, _, _)
    w.visible == false && return SimpleIoMap(p, w, _empty_canvas())
    pos = w.position
    sz  = w.size
    px = pos isa Point2D ? Int(pos.x[]) : 0
    py = pos isa Point2D ? Int(pos.y[]) : 0
    bw = sz  isa Point2D ? Int(sz.x[])  : 200
    bh = sz  isa Point2D ? Int(sz.y[])  : 16
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    elems = Any[]
    _push_box_rects!(elems, w, 0, 0, cw, ch)
    tr, tg, tb, ta = p.track_color
    push!(elems, GraphicsRect(cox, coy, cw, ch, tr, tg, tb, ta))
    value    = clamp(Float64(w.value),     0.0, 1.0)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    hr, hg, hb, ha = p.thumb_color
    if w.orientation === :horizontal
        tw = max(8, Int(round(thumb_sz * cw)))
        tx_pos = cox + Int(round(value * (cw - tw)))
        push!(elems, GraphicsRect(tx_pos, coy, tw, ch, hr, hg, hb, ha))
    else
        th = max(8, Int(round(thumb_sz * ch)))
        ty_pos = coy + Int(round(value * (ch - th)))
        push!(elems, GraphicsRect(cox, ty_pos, cw, th, hr, hg, hb, ha))
    end
    SimpleIoMap(p, w, _make_canvas(px, py, elems))
end

function map_reference_forward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollBarToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::WidgetScrollBarToGraphicsCanvas, iomap::SimpleIoMap, evt)
    evt isa MousePress || return nothing
    w = iomap.input
    w isa WidgetScrollBar || return nothing
    sz  = w.size
    bw = sz isa Point2D ? Int(sz.x[]) : 200
    bh = sz isa Point2D ? Int(sz.y[]) : 16
    cox, coy = _content_offset(w)
    tx, ty = _inset_total(w)
    cw = max(1, bw - tx)
    ch = max(1, bh - ty)
    thumb_sz = clamp(Float64(w.thumb_size), 0.05, 1.0)
    if w.orientation === :horizontal
        tw = max(8, Int(round(thumb_sz * cw)))
        new_value = clamp(Float64(evt.x - cox - div(tw, 2)) / max(1, cw - tw), 0.0, 1.0)
    else
        th = max(8, Int(round(thumb_sz * ch)))
        new_value = clamp(Float64(evt.y - coy - div(th, 2)) / max(1, ch - th), 0.0, 1.0)
    end
    SetScrollBarValueOperation(w, new_value)
end

# ── Factory ────────────────────────────────────────────────────────────────

"""
    WidgetToGraphics(font; measure, default_fg)

Build a recursive type-dispatching projection that maps any `WidgetDocument`
subtree to a `GraphicsCanvas`. `measure(text, font) -> (width, height)` is
used for all text sizing.
"""
function WidgetToGraphics(font::StyleFont; measure::Function,
                          default_fg::NTuple{4,UInt8}=(0xff, 0xff, 0xff, 0xff))
    fg4 = default_fg
    TypeDispatchingProjection(
        WidgetLabel      => WidgetLabelToGraphicsCanvas(font, measure, fg4),
        WidgetText       => WidgetTextToGraphicsCanvas(font, measure, fg4),
        WidgetCheckbox   => WidgetCheckboxToGraphicsCanvas(font, measure, fg4),
        WidgetButton     => WidgetButtonToGraphicsCanvas(font, measure, fg4),
        WidgetTooltip    => WidgetTooltipToGraphicsCanvas(font, measure, fg4),
        WidgetMenu       => WidgetMenuToGraphicsCanvas(font, measure),
        WidgetMenuItem   => WidgetMenuItemToGraphicsCanvas(font, measure, fg4),
        WidgetComposite  => WidgetCompositeToGraphicsCanvas(),
        WidgetShell      => WidgetShellToGraphicsCanvas(font, measure),
        WidgetTitlePane  => WidgetTitlePaneToGraphicsCanvas(font, measure, fg4),
        WidgetSplitPane  => WidgetSplitPaneToGraphicsCanvas(),
        WidgetTabbedPane => WidgetTabbedPaneToGraphicsCanvas(font, measure, fg4, (0xff, 0xcc, 0x00, 0xff)),
        WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(font, measure),
        WidgetToolbar    => WidgetToolbarToGraphicsCanvas(font, measure),
        WidgetScrollBar  => WidgetScrollBarToGraphicsCanvas((0x33, 0x33, 0x33, 0xff),
                                                            (0x88, 0x88, 0x88, 0xff)),
    )
end

# ── WidgetScrollPaneToGraphicsViewport ─────────────────────────────────────

struct WidgetScrollPaneToGraphicsViewportIoMap <: IoMap
    projection::Any
    input::WidgetScrollPane
    output::GraphicsCanvas
    content_iomap::Any
end

"""
    WidgetScrollPaneToGraphicsViewport(font, measure)

Projects a `WidgetScrollPane` to a `GraphicsViewport`. The content inside
the scroll pane is projected via the recursion argument. `measure` is
used to determine the scroll delta for mouse scroll events.
"""
struct WidgetScrollPaneToGraphicsViewport <: Projection
    font::StyleFont
    measure::Function
end

function projection_print(p::WidgetScrollPaneToGraphicsViewport, w::WidgetScrollPane, recursion, ctx)
    content_iomap = projection_print(recursion, w.content, recursion, ctx)
    content_output = content_iomap.output::GraphicsCanvas

    pos = w.position
    sz  = w.size
    bx = pos isa Point2D ? Int(pos.x[]) : 0
    by = pos isa Point2D ? Int(pos.y[]) : 0
    vw = sz isa Point2D ? Int(sz.x[]) : 400
    vh = sz isa Point2D ? Int(sz.y[]) : 300
    scroll_cell = getfield(w, :scroll_position)
    inner_x = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.x[])) end)
    inner_y = Cell(() -> begin sp = scroll_cell[]::Point2D; Int32(-Int(sp.y[])) end)

    inner_canvas = GraphicsCanvas(inner_x, inner_y, Cell(Int32(0)), Cell(Int32(0)),
                                  content_output.elements,
                                  content_output.layout,
                                  content_output.overlapping_elements,
                                  Cell(nothing))
    viewport = GraphicsViewport(bx, by, vw, vh, inner_canvas)
    output = GraphicsCanvas([viewport])

    WidgetScrollPaneToGraphicsViewportIoMap(p, w, output, content_iomap)
end

function projection_read(p::WidgetScrollPaneToGraphicsViewport, iomap::WidgetScrollPaneToGraphicsViewportIoMap, evt)
    if evt isa MouseScroll
        mx, my = evt.x, evt.y
        hit_element_at(iomap.output, mx, my) === nothing && return nothing
        _, scroll_step = p.measure("M", p.font)
        if evt.dx != 0 && evt.dy == 0
            return ScrollWidgetOperation(iomap.input, Point2D(-evt.dx * scroll_step, 0))
        else
            return ScrollWidgetOperation(iomap.input, Point2D(0, -evt.dy * scroll_step))
        end
    end
    content_iomap = iomap.content_iomap
    content_iomap === nothing && return nothing
    op = projection_read(content_iomap.projection, content_iomap, evt)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("content"), op.path))
    end
    return op
end

function map_reference_forward(::WidgetScrollPaneToGraphicsViewport, iomap, reference)
    return nothing
end

function map_reference_backward(::WidgetScrollPaneToGraphicsViewport, iomap, reference)
    return nothing
end

end # module
