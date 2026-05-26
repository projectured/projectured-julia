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
import ..FontModule: StyleFont, font_scaled_size
import ..ReferenceModule: Reference
export GraphicsDocument, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
       GraphicsInsertion, GraphicsForeign, GraphicsText, GraphicsRect, GraphicsCanvas, GraphicsViewport, GraphicsImage,
       GraphicsFence, setfn!, hit_element_at,
       IGraphicsInsertion, IGraphicsForeign, IGraphicsText, IGraphicsRect, IGraphicsCanvas, IGraphicsViewport, IGraphicsImage,
       IGraphicsFence

abstract type GraphicsDocument <: Document end

@enum LayoutDirection layout_none layout_horizontal layout_vertical

# ── GraphicsInsertion / GraphicsForeign ──────────────────────────────────

@document struct GraphicsInsertion <: GraphicsDocument
    value::Any
    selection::Reference
end
GraphicsInsertion() = GraphicsInsertion(Cell(nothing), Cell(nothing))

@document struct GraphicsForeign <: GraphicsDocument
    value::Any
    selection::Reference
end
GraphicsForeign(value) = GraphicsForeign(Cell(value), Cell(nothing))

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
                 radius_br=radius, radius_bl=radius)

A reactive filled rectangle for rendering (e.g. cursor lines, highlights).
Each corner has an independent radius in pixels (`0` means a square
corner). The positional `radius` is a shorthand that applies to all four
corners; per-corner keyword arguments override it.
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
    selection::Reference
end

function GraphicsRect(x::Integer, y::Integer, w::Integer, h::Integer,
                      r::Integer=255, g::Integer=255, b::Integer=255, a::Integer=255,
                      radius::Integer=0;
                      radius_tl::Integer=radius, radius_tr::Integer=radius,
                      radius_br::Integer=radius, radius_bl::Integer=radius)
    GraphicsRect(Cell(Int32(x)), Cell(Int32(y)), Cell(Int32(w)), Cell(Int32(h)),
                 Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                 Cell(Int32(radius_tl)), Cell(Int32(radius_tr)),
                 Cell(Int32(radius_br)), Cell(Int32(radius_bl)),
                 Cell(nothing))
end

function Base.show(io::IO, r::GraphicsRect)
    print(io, "GraphicsRect(x=", r.x, ", y=", r.y,
          ", w=", r.w, ", h=", r.h,
          ", rgba=(", r.r, ",", r.g, ",", r.b, ",", r.a, ")",
          ", radius=(tl=", r.radius_tl, ",tr=", r.radius_tr,
          ",br=", r.radius_br, ",bl=", r.radius_bl, "))")
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
        fs = font_scaled_size(elem.font.size)
        x >= ex && y >= ey && y < ey + fs
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
