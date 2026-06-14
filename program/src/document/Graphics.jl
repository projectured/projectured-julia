"""
    GraphicsModule

The graphics domain provides the final output stage before the SDL backend.
Elements are positioned, styled render primitives. The canvas is itself a
Document so the selection mechanism can descend into individual elements,
enabling mouse hit-testing and element-level selection in the reader.

The domain includes:
- **Render primitives**: `GraphicsText` (text rendering), `GraphicsRect` (filled rectangles)
- **Container types**: `GraphicsCanvas` (collection of graphics elements), `GraphicsViewport` (clipping viewport)
- **Hit testing**: `hit_element_at` for mouse hit detection

All fields are reactive Cells for automatic dependency tracking and incremental redraws.
"""
module GraphicsModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..FontModule: StyleFont
import ..ReferenceModule: Reference
export GraphicsDocument, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
       GraphicsInsertion, GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
       GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, setfn!, hit_element_at,
       IGraphicsInsertion, IGraphicsText, IGraphicsRect, IGraphicsLine, IGraphicsCircle,
       IGraphicsCanvas, IGraphicsViewport, IGraphicsImage,
       IGraphicsFence

abstract type GraphicsDocument <: Document end

@enum LayoutDirection layout_none layout_horizontal layout_vertical

# ── GraphicsInsertion ─────────────────────────────────────────────────────

@document struct GraphicsInsertion <: GraphicsDocument
    value::Any
    selection::Reference
end
GraphicsInsertion() = GraphicsInsertion(Cell(nothing), Cell(nothing))

# ── GraphicsText ───────────────────────────────────────────────────────

"""
    GraphicsText(text, x, y, font, r, g, b, a)

A reactive text element for rendering.
Each field is a `Cell`, so changes to any property are tracked
and can trigger incremental redraws.
"""
@document struct GraphicsText <: GraphicsDocument
    text::String
    x::Int32
    y::Int32
    font::StyleFont
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    selection::Reference
end

function GraphicsText(text::AbstractString, x::Integer, y::Integer,
                      font::StyleFont,
                      r::Integer=255, g::Integer=255, b::Integer=255, a::Integer=255)
    GraphicsText(Cell(text), Cell(Int32(x)), Cell(Int32(y)),
                 Cell(font),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(nothing))
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, t::GraphicsText)
    print(io, "GraphicsText(", repr(t.text),
          ", x=", t.x, ", y=", t.y,
          ", font=", repr(t.font),
          ", rgba=(", t.r, ",", t.g, ",", t.b, ",", t.a, "))")
end

"""
    GraphicsRect(x, y, w, h, r, g, b, a, radius=0;
                 radius_tl=radius, radius_tr=radius,
                 radius_br=radius, radius_bl=radius,
                 border_width=0, border_color=nothing)

A reactive filled rectangle for rendering (e.g. cursor lines, highlights).
Each corner has an independent radius in pixels (`0` means a square
corner). The positional `radius` is a shorthand that applies to all four
corners; per-corner keyword arguments override it.

An optional `border_width` (pixels) + `border_color` (an `(r,g,b,a)` tuple,
0–255) paints a rounded outline *inside* the rect, so a single primitive can
express the "rounded fill + 1px outline" idiom without stacking rects.
Each field is a `Cell`.
"""
@document struct GraphicsRect <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    radius_tl::Int32
    radius_tr::Int32
    radius_br::Int32
    radius_bl::Int32
    border_width::Int32
    border_r::UInt8
    border_g::UInt8
    border_b::UInt8
    border_a::UInt8
    selection::Reference
end

_norm_rgba(::Nothing) = (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
_norm_rgba(c::NTuple{4,<:Integer}) = (UInt8(c[1]), UInt8(c[2]), UInt8(c[3]), UInt8(c[4]))

function GraphicsRect(x::Integer, y::Integer, w::Integer, h::Integer,
                      r::Integer=255, g::Integer=255, b::Integer=255, a::Integer=255,
                      radius::Integer=0;
                      radius_tl::Integer=radius, radius_tr::Integer=radius,
                      radius_br::Integer=radius, radius_bl::Integer=radius,
                      border_width::Integer=0, border_color=nothing)
    br, bg, bb, ba = _norm_rgba(border_color)
    GraphicsRect(Cell(Int32(x)), Cell(Int32(y)), Cell(Int32(w)), Cell(Int32(h)),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(Int32(radius_tl)), Cell(Int32(radius_tr)),
                 Cell(Int32(radius_br)), Cell(Int32(radius_bl)),
                 Cell(Int32(border_width)),
                 Cell(br), Cell(bg), Cell(bb), Cell(ba),
                 Cell(nothing))
end

function Base.show(io::IO, r::GraphicsRect)
    print(io, "GraphicsRect(x=", r.x, ", y=", r.y,
          ", w=", r.w, ", h=", r.h,
          ", rgba=(", r.r, ",", r.g, ",", r.b, ",", r.a, ")",
          ", radius=(tl=", r.radius_tl, ",tr=", r.radius_tr,
          ",br=", r.radius_br, ",bl=", r.radius_bl, ")",
          ", border=(", r.border_width, ",rgba=(", r.border_r, ",", r.border_g,
          ",", r.border_b, ",", r.border_a, ")))")
end

# ── GraphicsLine ───────────────────────────────────────────────────────────

"""
    GraphicsLine(x1, y1, x2, y2, r, g, b, a; width=1)

A reactive straight line from `(x1,y1)` to `(x2,y2)` in color `(r,g,b,a)` with
the given stroke `width`. Axis-aligned lines (separators, rules) render as a
crisp filled span; diagonal lines render anti-aliased.
"""
@document struct GraphicsLine <: GraphicsDocument
    x1::Int32
    y1::Int32
    x2::Int32
    y2::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    width::Int32
    selection::Reference
end

function GraphicsLine(x1::Integer, y1::Integer, x2::Integer, y2::Integer,
                      r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                      width::Integer=1)
    GraphicsLine(Cell(Int32(x1)), Cell(Int32(y1)), Cell(Int32(x2)), Cell(Int32(y2)),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(Int32(width)), Cell(nothing))
end

function Base.show(io::IO, l::GraphicsLine)
    print(io, "GraphicsLine((", l.x1, ",", l.y1, ")→(", l.x2, ",", l.y2, ")",
          ", rgba=(", l.r, ",", l.g, ",", l.b, ",", l.a, "), width=", l.width, ")")
end

# ── GraphicsCircle ─────────────────────────────────────────────────────────

"""
    GraphicsCircle(cx, cy, radius, r, g, b, a; border_width=0, border_color=nothing)

A reactive filled circle centered at `(cx,cy)`. Optional anti-aliased outline
via `border_width` + `border_color` (an `(r,g,b,a)` tuple). Used for avatars,
radio dots, switch knobs and slider thumbs.
"""
@document struct GraphicsCircle <: GraphicsDocument
    cx::Int32
    cy::Int32
    radius::Int32
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    border_width::Int32
    border_r::UInt8
    border_g::UInt8
    border_b::UInt8
    border_a::UInt8
    selection::Reference
end

function GraphicsCircle(cx::Integer, cy::Integer, radius::Integer,
                        r::Integer=0, g::Integer=0, b::Integer=0, a::Integer=255;
                        border_width::Integer=0, border_color=nothing)
    bor, bog, bob, boa = _norm_rgba(border_color)
    GraphicsCircle(Cell(Int32(cx)), Cell(Int32(cy)), Cell(Int32(radius)),
                   Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                   Cell(Int32(border_width)),
                   Cell(bor), Cell(bog), Cell(bob), Cell(boa),
                   Cell(nothing))
end

function Base.show(io::IO, c::GraphicsCircle)
    print(io, "GraphicsCircle(c=(", c.cx, ",", c.cy, "), r=", c.radius,
          ", rgba=(", c.r, ",", c.g, ",", c.b, ",", c.a, "))")
end

# ── Canvas ───────────────────────────────────────────────────────────────

"""
    GraphicsCanvas(elements[, layout[, overlapping_elements]])

A reactive container holding a list of graphics elements to render.
The `elements` field is a `Cell` wrapping a `CollectionDocument`
(`CellVector` or `ListNode`). The `layout` field declares the axis
along which the canvas may extend infinitely, enabling the renderer
to stop painting when elements are past the viewport edge.

When `overlapping_elements` is `false`, elements are guaranteed not to
overlap along the layout axis. This enables the renderer and hit-testing
to stop early once past the viewport or click point.
"""
@document struct GraphicsCanvas <: GraphicsDocument
    x::Int
    y::Int
    w::Int
    h::Int
    elements::CollectionDocument
    layout::LayoutDirection
    overlapping_elements::Bool
    selection::Reference
end

GraphicsCanvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), CellVector(), layout_none, true, Cell(nothing))
GraphicsCanvas(elems::Vector) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), CellVector(Cell[Cell(e) for e in elems]), layout_none, true, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, true, Cell(nothing))
GraphicsCanvas(elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(0), Int32(0), elems, layout, overlapping, Cell(nothing))
GraphicsCanvas(x::Integer, y::Integer, w::Integer, h::Integer, elems::CollectionDocument, layout::LayoutDirection, overlapping::Bool) = GraphicsCanvas(Int32(x), Int32(y), Int32(w), Int32(h), elems, layout, overlapping, Cell(nothing))

# ── Viewport ─────────────────────────────────────────────────────────────

"""
    GraphicsViewport(x, y, w, h, content)

A clipping viewport: renders `content` (a `GraphicsCanvas` whose element
coordinates are relative to the viewport origin, with any scroll offset
already applied) and clips the output to the rectangle `(x, y, w, h)`.
"""
@document struct GraphicsViewport <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    content::GraphicsCanvas
    selection::Reference
end

function GraphicsViewport(x::Integer, y::Integer, w::Integer, h::Integer,
                          content::GraphicsCanvas)
    GraphicsViewport(Cell(Int32(x)), Cell(Int32(y)),
                     Cell(Int32(w)), Cell(Int32(h)),
                     Cell(content),
                     Cell(nothing))
end

function Base.show(io::IO, v::GraphicsViewport)
    print(io, "GraphicsViewport(x=", v.x, ", y=", v.y,
          ", w=", v.w, ", h=", v.h, ")")
end

# ── Image (cached rasterized canvas) ─────────────────────────────────────

@document struct GraphicsImage <: GraphicsDocument
    x::Int32
    y::Int32
    w::Int32
    h::Int32
    data::Any
    selection::Reference
end

function GraphicsImage(x::Integer, y::Integer, w::Integer, h::Integer, data)
    GraphicsImage(Cell(Int32(x)), Cell(Int32(y)),
                  Cell(Int32(w)), Cell(Int32(h)),
                  Cell(data),
                  Cell(nothing))
end

function Base.show(io::IO, img::GraphicsImage)
    print(io, "GraphicsImage(x=", img.x, ", y=", img.y,
          ", w=", img.w, ", h=", img.h, ")")
end

# ── Fence ──────────────────────────────────────────────────────────────────

"""
    GraphicsFence()

A barrier element placed inside a `GraphicsCanvas`'s element list.
It guarantees that elements before and after the fence do not overlap
along the canvas's layout axis. The fence is always perpendicular to
the canvas's `layout` direction. It carries no visual representation
and is skipped during rendering and hit-testing.
"""
@document struct GraphicsFence <: GraphicsDocument
    selection::Reference
end

GraphicsFence() = GraphicsFence(Cell(nothing))

# ── Hit testing ─────────────────────────────────────────────────────────────

function _rect_hit(elem::GraphicsRect, cx::Int, cy::Int)
    x, y, w, h = Int(elem.x), Int(elem.y), Int(elem.w), Int(elem.h)
    cx >= x && cx < x + w && cy >= y && cy < y + h
end

"""
    hit_element_at(canvas::GraphicsCanvas, x::Int, y::Int) -> Int or nothing

Returns the 1-based index of the first element in `canvas` whose bounding area
contains `(x, y)`, or `nothing` if no element matches.
Supports `GraphicsViewport` (rectangle bounds), `GraphicsRect` (rectangle
bounds), and `GraphicsText` (vertical font-size band).
Skips `GraphicsFence` elements. For `ListNode`-backed canvases with a layout
direction, stops early when the element position exceeds the click coordinate
along the layout axis.
"""
function hit_element_at(canvas::GraphicsCanvas, x::Int, y::Int)
    layout = canvas.layout
    elements = canvas.elements
    early_stop = !canvas.overlapping_elements && layout != layout_none
    if elements isa ListNode
        # Check prev-direction elements (negative offsets)
        prev_node = elements.prev
        pi = 0
        while prev_node !== nothing
            pi -= 1
            elem = prev_node.value
            if elem isa GraphicsFence
                prev_node = prev_node.prev
                continue
            end
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey < y && break
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex < x && break
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return pi
            prev_node = prev_node.prev
        end
        # Check forward-direction elements
        i = 0
        node = elements
        while node !== nothing
            i += 1
            elem = node.value
            if elem isa GraphicsFence
                node = node.next
                continue
            end
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey > y && return nothing
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex > x && return nothing
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return i - 1
            node = node.next
        end
    else
        for (i, elem) in enumerate(elements)
            elem isa GraphicsFence && continue
            if early_stop
                if layout == layout_vertical
                    ey = _elem_y(elem)
                    ey !== nothing && ey > y && return nothing
                elseif layout == layout_horizontal
                    ex = _elem_x(elem)
                    ex !== nothing && ex > x && return nothing
                end
            end
            hit = _hit_test_element(elem, x, y)
            hit && return i - 1
        end
    end
    nothing
end

function _hit_test_element(elem, x::Int, y::Int)
    if elem isa GraphicsViewport
        vx, vy = Int(elem.x), Int(elem.y)
        vw, vh = Int(elem.w), Int(elem.h)
        x >= vx && x < vx + vw && y >= vy && y < vy + vh
    elseif elem isa GraphicsRect
        _rect_hit(elem, x, y)
    elseif elem isa GraphicsText
        ex, ey = Int(elem.x), Int(elem.y)
        fs = elem.font.size
        x >= ex && y >= ey && y < ey + fs
    elseif elem isa GraphicsCircle
        dx, dy = x - Int(elem.cx), y - Int(elem.cy)
        rad = Int(elem.radius)
        dx * dx + dy * dy <= rad * rad
    elseif elem isa GraphicsLine
        lx = min(Int(elem.x1), Int(elem.x2)); ly = min(Int(elem.y1), Int(elem.y2))
        lw = abs(Int(elem.x2) - Int(elem.x1)); lh = abs(Int(elem.y2) - Int(elem.y1))
        hw = max(1, Int(elem.width))
        x >= lx - hw && x <= lx + lw + hw && y >= ly - hw && y <= ly + lh + hw
    elseif elem isa GraphicsCanvas
        # Delegate hit test into the nested canvas (coordinates relative to canvas origin)
        cx, cy = Int(elem.x), Int(elem.y)
        hit_element_at(elem, x - cx, y - cy) !== nothing
    else
        false
    end
end

_elem_x(elem) = hasproperty(elem, :x) ? Int(elem.x) : nothing
_elem_y(elem) = hasproperty(elem, :y) ? Int(elem.y) : nothing

end # module
