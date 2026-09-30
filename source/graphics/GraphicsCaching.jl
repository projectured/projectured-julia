# Fragment of `GraphicsModule`.
#
# GraphicsCanvas → GraphicsImage projection. Finite leaf canvases (no nested
# canvases, no infinite `ListNode`-backed element lists) are passed through
# `GraphicsCanvasToGraphicsImage` which will eventually rasterize them to a
# cached image. Non-leaf or infinite canvases are preserved as-is via
# `IdentityProjection` so that recursion can process their children.
#
# The reader performs mouse hit-testing: click coordinates are matched against
# canvas elements and translated into a pixel-offset selection path that
# upstream projection readers interpret as a character position.
# ── Predicates ──────────────────────────────────────────────────────────────

# A canvas with no end: its elements are a list the renderer walks and stops
# in, or one of its element canvases is: a content can draw a list beside other
# elements, and one level down is the level that a pane around it looks at.
function is_infinite_canvas(canvas::GraphicsCanvas)
    elements = canvas.elements
    elements isa ListNode && return true
    elements === nothing && return false
    for element in elements
        element isa GraphicsCanvas && element.elements isa ListNode && return true
    end
    false
end

function is_leaf_canvas(canvas::GraphicsCanvas)
    for elem in canvas.elements
        (elem isa GraphicsCanvas || elem isa GraphicsViewport) && return false
    end
    return true
end

# ── GraphicsCanvasToGraphicsImage ────────────────────────────────────────────

struct GraphicsCanvasToGraphicsImage <: Projection end

function map_reference_forward(::GraphicsCanvasToGraphicsImage, iomap, reference)
    return nothing
end

function map_reference_backward(::GraphicsCanvasToGraphicsImage, iomap, reference)
    return nothing
end

# Color palette for distinguishing cached images
const _checker_colors = [
    StyleColor(255 / 255, 230 / 255, 230 / 255, 40 / 255),  # pale red
    StyleColor(230 / 255, 255 / 255, 230 / 255, 40 / 255),  # pale green
    StyleColor(230 / 255, 230 / 255, 255 / 255, 40 / 255),  # pale blue
    StyleColor(255 / 255, 255 / 255, 210 / 255, 40 / 255),  # pale yellow
    StyleColor(255 / 255, 220 / 255, 255 / 255, 40 / 255),  # pale magenta
    StyleColor(220 / 255, 255 / 255, 255 / 255, 40 / 255),  # pale cyan
]
const _checker_counter = Ref(0)

function _compute_bounds(canvas::GraphicsCanvas)
    min_x, min_y, max_x, max_y = typemax(Int), typemax(Int), 0, 0
    for elem in canvas.elements
        if elem isa GraphicsText
            x, y = Int(elem.x), Int(elem.y)
            width, ascent, descent = compute_text_extent(elem.text, elem.font)
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x + width)
            max_y = max(max_y, y + ascent + descent)
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
    bx, by, bw, bh = _compute_bounds(canvas)
    step = 16
    rects = Cell[]
    for row in 0:div(bh, step)
        for col in 0:div(bw, step)
            if (row + col) % 2 == 0
                push!(rects, Cell(GraphicsRect(
                    Int32(bx + col * step), Int32(by + row * step),
                    Int32(min(step, bw - col * step)), Int32(min(step, bh - row * step));
                    color)))
            end
        end
    end
    rects
end

function print_document(p::GraphicsCanvasToGraphicsImage, recursion, canvas::GraphicsCanvas, ctx)
    bg_rects = _make_checker_background(canvas)
    orig_cv = canvas.elements::CellVector
    orig_elements_cell = getfield(orig_cv, :elements)
    output_cv = CellVector(Cell(Cell[]), Cell(nothing))
    set_cell_computation!(getfield(output_cv, :elements), () -> begin
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

function read_intent(::GraphicsCanvasToGraphicsImage, iomap::SimpleIoMap, evt)
    evt isa MousePress || return nothing
    canvas = iomap.input
    elems  = canvas.elements

    # Always emit a plain click (element + pixel offset). Whole-element promotion
    # (Alt+click) is decided in SyntaxToText off the originating gesture.
    # Check precise-bounds rects first (e.g. cursor highlights)
    for (i, elem) in enumerate(elems)
        elem isa GraphicsRect || continue
        _rect_hit(elem, evt.x, evt.y) || continue
        ox, oy = Int(elem.x), Int(elem.y)
        path = ConcreteReference(ElementReferenceStep(i),
                   ConcreteReference(PointReferenceStep(evt.x - ox, evt.y - oy)))
        return ReplaceSelectionOperation(path)
    end

    # For text elements: pick the segment with the largest x ≤ click_x
    # on the matching vertical band — that is the segment the click landed on.
    best_i  = nothing
    best_x  = -1
    for (i, elem) in enumerate(elems)
        elem isa GraphicsText || continue
        x, y = Int(elem.x), Int(elem.y)
        _, ascent, descent = compute_text_extent(elem.text, elem.font)
        evt.y >= y && evt.y < y + ascent + descent || continue
        x <= evt.x && x > best_x || continue
        best_x = x
        best_i = i
    end
    best_i === nothing && return nothing
    elem = elems[best_i]
    ox, oy = Int(elem.x), Int(elem.y)
    path = ConcreteReference(ElementReferenceStep(best_i),
               ConcreteReference(PointReferenceStep(evt.x - ox, evt.y - oy)))
    return ReplaceSelectionOperation(path)
end

# ── Compound convenience constructor ────────────────────────────────────────

"""
    GraphicsCaching(; render)

A composite projection that processes graphics documents recursively using
type and predicate dispatch. Finite leaf canvases (no nested canvases, no
`ListNode`-backed elements) are routed to `GraphicsCanvasToGraphicsImage`;
non-leaf canvases and viewports recurse via `CopyingProjection`. `render` is
accepted for the rasterizer this file's header describes as future work;
nothing reads it yet.
"""
function GraphicsCaching(; render)
    TypeDispatchingProjection(
        GraphicsCanvas => PredicateDispatchingProjection(
            (c -> !is_infinite_canvas(c) && is_leaf_canvas(c)) => GraphicsCanvasToGraphicsImage(),
            ((_) -> true)                                      => CopyingProjection(),
        ),
        GraphicsViewport => CopyingProjection(),
        CellVector => CopyingProjection(),
        ListNode => CopyingProjection(),
        Any => IdentityProjection(),
    )
end
