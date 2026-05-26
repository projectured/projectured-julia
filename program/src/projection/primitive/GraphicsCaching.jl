"""
    GraphicsCachingModule

GraphicsCanvas → GraphicsImage projection. Finite leaf canvases (no nested
canvases, no infinite `ListNode`-backed element lists) are passed through
`GraphicsCanvasToGraphicsImage` which will eventually rasterize them to a
cached image. Non-leaf or infinite canvases are preserved as-is via
`PreservingProjection` so that recursion can process their children.

The reader performs mouse hit-testing: click coordinates are matched against
canvas elements and translated into a pixel-offset selection path that
upstream projection readers interpret as a character position.
"""
module GraphicsCachingModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsViewport, hit_element_at
import ..CollectionModule: CellVector, ListNode
import ..ReactiveModule: Cell, setfn!
import ..CopyingProjectionModule: CopyingProjection
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..PredicateDispatchingModule: PredicateDispatchingProjection
import ..PreservingProjectionModule: PreservingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, PointReference
import ..OperationModule: ReplaceSelectionOperation
import ..MouseModule: MousePress
import ..FontModule: font_scaled_size
export GraphicsCanvasToGraphicsImage, GraphicsCaching

# ── Predicates ──────────────────────────────────────────────────────────────

is_infinite_canvas(canvas::GraphicsCanvas) = canvas.elements isa ListNode

function is_leaf_canvas(canvas::GraphicsCanvas)
    for elem in canvas.elements
        (elem isa GraphicsCanvas || elem isa GraphicsViewport) && return false
    end
    return true
end

# ── GraphicsCanvasToGraphicsImage ────────────────────────────────────────────

struct GraphicsCanvasToGraphicsImage <: Projection
    render::Any
end

function map_reference_forward(::GraphicsCanvasToGraphicsImage, iomap, reference)
    return nothing
end

function map_reference_backward(::GraphicsCanvasToGraphicsImage, iomap, reference)
    return nothing
end

# Color palette for distinguishing cached images
const _checker_colors = [
    (UInt8(255), UInt8(230), UInt8(230), UInt8(40)),  # pale red
    (UInt8(230), UInt8(255), UInt8(230), UInt8(40)),  # pale green
    (UInt8(230), UInt8(230), UInt8(255), UInt8(40)),  # pale blue
    (UInt8(255), UInt8(255), UInt8(210), UInt8(40)),  # pale yellow
    (UInt8(255), UInt8(220), UInt8(255), UInt8(40)),  # pale magenta
    (UInt8(220), UInt8(255), UInt8(255), UInt8(40)),  # pale cyan
]
const _checker_counter = Ref(0)

function _compute_bounds(canvas::GraphicsCanvas)
    min_x, min_y, max_x, max_y = typemax(Int), typemax(Int), 0, 0
    for elem in canvas.elements
        if elem isa GraphicsText
            x, y, fs = Int(elem.x), Int(elem.y), font_scaled_size(elem.font.size)
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x + 200)  # approximate width
            max_y = max(max_y, y + fs)
        elseif elem isa GraphicsRect
            x, y, w, h = Int(elem.x), Int(elem.y), Int(elem.w), Int(elem.h)
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x + w)
            max_y = max(max_y, y + h)
        end
    end
    max_x == 0 && return (0, 0, 100, 100)
    (min_x, min_y, max_x - min_x, max_y - min_y)
end

function _make_checker_background(canvas::GraphicsCanvas)
    _checker_counter[] += 1
    color = _checker_colors[mod1(_checker_counter[], length(_checker_colors))]
    r, g, b, a = color
    bx, by, bw, bh = _compute_bounds(canvas)
    step = 16
    rects = Cell[]
    for row in 0:div(bh, step)
        for col in 0:div(bw, step)
            if (row + col) % 2 == 0
                push!(rects, Cell(GraphicsRect(
                    Int32(bx + col * step), Int32(by + row * step),
                    Int32(min(step, bw - col * step)), Int32(min(step, bh - row * step)),
                    r, g, b, a)))
            end
        end
    end
    rects
end

function projection_print(p::GraphicsCanvasToGraphicsImage, canvas::GraphicsCanvas, recursion, reference)
    bg_rects = _make_checker_background(canvas)
    orig_cv = canvas.elements::CellVector
    orig_elements_cell = getfield(orig_cv, :elements)
    output_cv = CellVector(Cell(Cell[]), Cell(nothing))
    setfn!(getfield(output_cv, :elements), () -> begin
        orig_cells = orig_elements_cell[]::Vector{Cell}
        vcat(bg_rects, orig_cells)
    end)
    output = GraphicsCanvas(getfield(canvas, :x), getfield(canvas, :y),
        getfield(canvas, :w), getfield(canvas, :h),
        output_cv,
        canvas.layout, canvas.overlapping_elements, Cell(nothing))
    return SimpleIoMap(p, canvas, output)
end

_rect_hit(r::GraphicsRect, cx::Integer, cy::Integer) =
    cx >= Int(r.x) && cx < Int(r.x) + Int(r.w) &&
    cy >= Int(r.y) && cy < Int(r.y) + Int(r.h)

function projection_read(::GraphicsCanvasToGraphicsImage, iomap::SimpleIoMap, evt)
    evt isa MousePress || return nothing
    canvas = iomap.input
    elems  = canvas.elements

    # Check precise-bounds rects first (e.g. cursor highlights)
    for (i, elem) in enumerate(elems)
        elem isa GraphicsRect || continue
        _rect_hit(elem, evt.x, evt.y) || continue
        ox, oy = Int(elem.x), Int(elem.y)
        return ReplaceSelectionOperation(
            ConcreteReferencePath(ElementReference(i),
                ConcreteReferencePath(PointReference(evt.x - ox, evt.y - oy))))
    end

    # For text elements: pick the segment with the largest x ≤ click_x
    # on the matching vertical band — that is the segment the click landed on.
    best_i  = nothing
    best_x  = -1
    for (i, elem) in enumerate(elems)
        elem isa GraphicsText || continue
        x, y, fs = Int(elem.x), Int(elem.y), font_scaled_size(elem.font.size)
        evt.y >= y && evt.y < y + fs || continue
        x <= evt.x && x > best_x || continue
        best_x = x
        best_i = i
    end
    best_i === nothing && return nothing
    elem = elems[best_i]
    ox, oy = Int(elem.x), Int(elem.y)
    return ReplaceSelectionOperation(
        ConcreteReferencePath(ElementReference(best_i),
            ConcreteReferencePath(PointReference(evt.x - ox, evt.y - oy))))
end

# ── Compound convenience constructor ────────────────────────────────────────

"""
    GraphicsCaching(; render)

A composite projection that processes graphics documents recursively using
type and predicate dispatch. Finite leaf canvases (no nested canvases, no
`ListNode`-backed elements) are routed to `GraphicsCanvasToGraphicsImage`;
non-leaf canvases and viewports recurse via `CopyingProjection`.
"""
function GraphicsCaching(; render)
    TypeDispatchingProjection(
        GraphicsCanvas => PredicateDispatchingProjection(
            (c -> !is_infinite_canvas(c) && is_leaf_canvas(c)) => GraphicsCanvasToGraphicsImage(render),
            ((_) -> true)                                      => CopyingProjection(),
        ),
        GraphicsViewport => CopyingProjection(),
        CellVector => CopyingProjection(),
        ListNode => CopyingProjection(),
        Any => PreservingProjection(),
    )
end

end # module
