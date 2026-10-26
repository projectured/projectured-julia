# Fragment of `GraphModule`.
#
# GraphLayout → Graphics projection. Draws each `VertexLayout` as a node box (a
# rounded `GraphicsRect` outline at `(x, y, w, h)`) with the vertex's projected
# content canvas placed inside, and each `EdgeLayout` as a `GraphicsPolyline`
# connector along its `route` (an end arrowhead when the edge is directed), with the
# edge's optional `label` recursed to a canvas and centred on the route midpoint.
# Edges are drawn first, nodes on top.
#
# The drawing paints a box larger than the box that the engine places: the padding
# and, for the highlighted vertex, the ring. So the drawing, not the engine, cuts
# each edge at the rim of what it paints. An edge runs from the centre of its
# source box, through the bends of its route, to the centre of its target box,
# and is cut where it leaves the one and where it enters the other. One rule
# serves a route that ends on the border of a box, a route that ends at its
# centre, and a dragged box.
#
# Selection: a path `vertex_layouts[i].vertex.content.…` routes into the i-th
# node's content sub-pipeline (tutorial School A — peel the steps this projection
# owns and delegate the tail through the stored child IO maps). The
# `GraphToGraphLayout` stage above maps `vertices[i].content.…` ↔
# `vertex_layouts[i].vertex.content.…`, so a selection into vertex content
# round-trips through the whole graph pipeline. An edge is a decoration, but its
# label is a part, as the content of a vertex is: a path
# `edge_layouts[j].edge.label.…` routes into the label, and a key and a click reach
# it the same way.
#
# The highlight (`GraphLayout.highlight_vertex` / `highlight_edge`) is a ring
# just outside the node's box, and a re-stroke over the edge's own line. Both
# are *extra* elements keyed on the highlight cells alone — never a change to a
# node's content or geometry, so a highlight move never re-runs the layout. The
# light of the vertex under the pointer is drawn the same way, from the mouse
# target of the layout: a ring of the light around the vertex and the vertices
# it joins, and a line of the light over its edges.

# The point halfway along a polyline route by arc length — where an edge label
# sits. Falls back to the single point / origin for degenerate routes.
function _route_midpoint(route)
    n = length(route)
    n == 0 && return (0, 0)
    n == 1 && return (round(Int, route[1][1]), round(Int, route[1][2]))
    seglen(i) = hypot(route[i+1][1] - route[i][1], route[i+1][2] - route[i][2])
    half = sum(seglen(i) for i in 1:n-1) / 2
    acc = 0.0
    for i in 1:n-1
        s = seglen(i)
        if acc + s >= half
            t = s == 0 ? 0.0 : (half - acc) / s
            return (round(Int, route[i][1] + t * (route[i+1][1] - route[i][1])),
                    round(Int, route[i][2] + t * (route[i+1][2] - route[i][2])))
        end
        acc += s
    end
    (round(Int, route[n][1]), round(Int, route[n][2]))
end

_get_box_centre(box) = (box[1] + box[3] / 2, box[2] + box[4] / 2)

# The rectangle that the drawing paints for the box of the content of a vertex:
# the box with its padding, and with the ring when the vertex has the highlight
# or the light.
function _get_drawn_rim(box, style, highlighted::Bool)
    x, y, w, h = box
    g = style.node_padding + (highlighted ? style.highlight_gap + style.highlight_width : 0)
    (x - g, y - g, w + 2g, h + 2g)
end

# Whether the point `(x, y)` is inside the rectangle `rim`. A point on the rim is
# outside.
_is_inside_rim(rim, x, y) = rim[1] < x < rim[1] + rim[3] && rim[2] < y < rim[2] + rim[4]

# The fraction of the way from `p` to `q` where a segment that starts inside `rim`
# leaves it.
function _compute_rim_exit(rim, p, q)
    t = 1.0
    dx = q[1] - p[1]
    dy = q[2] - p[2]
    dx > 0 && (t = min(t, (rim[1] + rim[3] - p[1]) / dx))
    dx < 0 && (t = min(t, (rim[1] - p[1]) / dx))
    dy > 0 && (t = min(t, (rim[2] + rim[4] - p[2]) / dy))
    dy < 0 && (t = min(t, (rim[2] - p[2]) / dy))
    clamp(t, 0.0, 1.0)
end

_get_point_between(p, q, t) = (p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2]))

# The part of the polyline `points` that is outside both rims: it starts where the
# polyline leaves `source_rim` and ends where it enters `target_rim`. `nothing`
# when no part is outside both, because the two boxes overlap.
function _clip_route(points, source_rim, target_rim)
    n = length(points)
    n < 2 && return nothing
    first = findfirst(k -> !_is_inside_rim(source_rim, points[k + 1]...), 1:(n - 1))
    last = findlast(k -> !_is_inside_rim(target_rim, points[k]...), 1:(n - 1))
    (first === nothing || last === nothing || first > last) && return nothing
    p, q = points[first], points[first + 1]
    start = _is_inside_rim(source_rim, p...) ? _compute_rim_exit(source_rim, p, q) : 0.0
    r, s = points[last], points[last + 1]
    finish = _is_inside_rim(target_rim, s...) ? 1.0 - _compute_rim_exit(target_rim, s, r) : 1.0
    first == last && start >= finish && return nothing
    clipped = Tuple{Float64,Float64}[_get_point_between(p, q, start)]
    append!(clipped, points[(first + 1):last])
    push!(clipped, _get_point_between(r, s, finish))
    Tuple{Int,Int}[(round(Int, point[1]), round(Int, point[2])) for point in clipped]
end

# The route of an edge as the drawing draws it: from the centre of `source_box`,
# through the bends of `route`, to the centre of `target_box`, cut at the two rims.
# The drawing map `drawing_map` moves each bend. A `straight` edge has no bends, as
# the edge of a dragged vertex.
function _make_drawn_route(route, source_box, target_box, source_rim, target_rim, drawing_map;
                           straight::Bool)
    points = Tuple{Float64,Float64}[_get_box_centre(source_box)]
    if !straight
        for k in 2:(length(route) - 1)
            push!(points, _apply_zoom_map(drawing_map, route[k]))
        end
    end
    push!(points, _get_box_centre(target_box))
    _clip_route(points, source_rim, target_rim)
end

# ── The zoom of the layout ───────────────────────────────────────────────────
#
# The zoom moves the centre of each box and each bend of a route by one map,
# `scale .* point .+ shift`, and a box keeps its size and its content. The scale
# and the shift are view state, `GraphLayout.zoom`, and each notch of the wheel
# writes both, so that the top-left corner of the drawing stays where it is. A
# drop does not change them, so a dropped vertex stays where the person put it.

# The steps of the zoom for each notch of the wheel, and its limits.
const _LAYOUT_ZOOM_STEP = 1.15
const _LAYOUT_ZOOM_LIMITS = (0.25, 4.0)

_apply_zoom_map(zoom_map, point) =
    (zoom_map.scale * point[1] + zoom_map.shift[1], zoom_map.scale * point[2] + zoom_map.shift[2])

# The corner where the zoom map `zoom_map` draws the box of `vertex_layout`, as a
# corner that is not rounded.
_get_zoomed_corner(zoom_map, vertex_layout::VertexLayout) =
    _apply_zoom_map(zoom_map, _get_box_centre((Int(vertex_layout.x), Int(vertex_layout.y),
                                               Int(vertex_layout.w), Int(vertex_layout.h)))) .-
    (Int(vertex_layout.w) / 2, Int(vertex_layout.h) / 2)

# The corner in the layout of the box of `vertex_layout`, when the zoom map
# `zoom_map` draws it at `corner`: the inverse of the map.
function _get_layout_corner(zoom_map, vertex_layout::VertexLayout, corner)
    half = (Int(vertex_layout.w) / 2, Int(vertex_layout.h) / 2)
    round.(Int, (corner .+ half .- zoom_map.shift) ./ zoom_map.scale .- half)
end

# The top-left corner of the boxes that the zoom map `zoom_map` draws, or
# `nothing` for a layout with no box.
function _find_zoomed_top_left(layout::GraphLayout, zoom_map)
    corners = [_get_zoomed_corner(zoom_map, vertex_layout)
               for vertex_layout in layout.vertex_layouts if vertex_layout isa VertexLayout]
    isempty(corners) ? nothing : (minimum(first, corners), minimum(last, corners))
end

# The map of the zoom `zoom` of `layout`, as the drawing draws it. A box that the
# zoom would draw left of or above the drawing, after an engine placed a vertex
# there, moves the whole drawing, so no box is cut.
function _compute_zoom_map(layout::GraphLayout, zoom = layout.zoom)
    stored = zoom === nothing ? (scale = 1.0, shift = (0.0, 0.0)) :
             (scale = Float64(zoom.scale), shift = Float64.(zoom.shift))
    top_left = _find_zoomed_top_left(layout, stored)
    top_left === nothing && return stored
    (scale = stored.scale, shift = stored.shift .- min.(0.0, top_left))
end

_write_layout_zoom(layout::GraphLayout, zoom) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(layout, "zoom", zoom))

# The scale and the shift of a zoom of `layout` by `notches` of the wheel, or
# `nothing` at a limit. A turn away from the person zooms in. The new shift keeps
# the top-left corner of the drawing where it is.
function _compute_next_zoom(layout::GraphLayout, notches::Integer)
    zoom_map = _compute_zoom_map(layout)
    scale = clamp(zoom_map.scale * _LAYOUT_ZOOM_STEP^notches, _LAYOUT_ZOOM_LIMITS...)
    scale == zoom_map.scale && return nothing
    old_top_left = _find_zoomed_top_left(layout, zoom_map)
    old_top_left === nothing && return (scale = scale, shift = (0.0, 0.0))
    (scale = scale,
     shift = old_top_left .- _find_zoomed_top_left(layout, (scale = scale, shift = (0.0, 0.0))))
end

# The margin that the drawing keeps on the left and on the top: the padding of a
# box and the ring of a highlight, which the drawing paints outside the box that
# the engine places. So a box at the corner (0, 0) of the layout is painted
# inside the canvas, and a host that clips the canvas cuts no frame.
_get_drawing_margin(style) = style.node_padding + style.highlight_gap + style.highlight_width

# The map from the layout to the drawing: the zoom, moved right and down by the
# margin, with the margin itself.
function _compute_drawing_map(layout::GraphLayout, style)
    zoom_map = _compute_zoom_map(layout)
    margin = _get_drawing_margin(style)
    (scale = zoom_map.scale, shift = zoom_map.shift .+ margin, margin = margin)
end

# The box of the content of each vertex in the drawing, by its index in
# `vertex_layouts`: where the drawing map `drawing_map` draws it, and the dragged
# vertex where the pointer took it. An entry that is no `VertexLayout` has
# `nothing`.
function _compute_drawn_boxes(layout::GraphLayout, drawing_map, drag)
    boxes = Union{Nothing,NTuple{4,Int}}[]
    for (i, vertex_layout) in enumerate(layout.vertex_layouts)
        if !(vertex_layout isa VertexLayout)
            push!(boxes, nothing)
            continue
        end
        corner = round.(Int, _get_zoomed_corner(drawing_map, vertex_layout))
        x, y = drag !== nothing && i == drag.index ?
               _get_dragged_corner(corner, drag.offset, drawing_map.margin) : corner
        push!(boxes, (x, y, Int(vertex_layout.w), Int(vertex_layout.h)))
    end
    boxes
end

# The samples of each span of a curved edge, for the backend and for the label:
# one for about each `_CURVE_SAMPLE_LENGTH` pixels of the span, inside the limits.
const _CURVE_SAMPLE_LENGTH = 6
const _CURVE_SEGMENT_LIMITS = (12, 64)

# The samples of each span of the chain of Bézier curves `curve`, from the length
# of its control polygon, which is at least the length of the curve.
function _get_curve_segments(curve)
    length_of_polygon = sum(hypot((curve[k + 1] .- curve[k])...) for k in 1:(length(curve) - 1))
    spans = (length(curve) - 1) ÷ 3
    clamp(ceil(Int, length_of_polygon / spans / _CURVE_SAMPLE_LENGTH), _CURVE_SEGMENT_LIMITS...)
end

function _get_unit_vector(v)
    distance = hypot(v[1], v[2])
    distance == 0 ? (0.0, 0.0) : (v[1] / distance, v[2] / distance)
end

# The outward direction of the side of `rim` that the point `p` is on.
function _get_rim_normal(rim, p)
    x, y, w, h = rim
    distances = (abs(p[1] - x), abs(p[1] - (x + w)), abs(p[2] - y), abs(p[2] - (y + h)))
    ((-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0))[argmin(distances)]
end

# The points of a chain of cubic Bézier curves through `points`, for a
# `GraphicsSpline` of kind `:bezier`: each point, with two control points between
# each two. The curve leaves the first point in the direction `start` and reaches
# the last point in the direction `finish`, both unit vectors. At a bend it keeps
# the direction from the point before to the point after, as a Catmull-Rom spline
# does, and its control point is a third of its span from it. The control point
# of an end is half of its span along the direction of that end, so an edge that
# leaves the top of a wide box toward a box far to the side makes no loop.
function _compute_curve_points(points, start, finish)
    n = length(points)
    directions = Tuple{Float64,Float64}[start]
    for k in 2:(n - 1)
        push!(directions, _get_unit_vector(points[k + 1] .- points[k - 1]))
    end
    push!(directions, finish)
    along(v, direction) = abs(v[1] * direction[1] + v[2] * direction[2])
    curve = Tuple{Int,Int}[points[1]]
    for k in 1:(n - 1)
        p, q = points[k], points[k + 1]
        span = hypot(q[1] - p[1], q[2] - p[2])
        leave = k == 1 ? along(q .- p, start) / 2 : span / 3
        arrive = k + 1 == n ? along(q .- p, finish) / 2 : span / 3
        push!(curve, round.(Int, p .+ leave .* directions[k]),
                     round.(Int, q .- arrive .* directions[k + 1]), q)
    end
    curve
end

# The edges as the drawing draws them, by their index in `edge_layouts`: for each
# edge the points of its element, and the polyline that a backend strokes for
# them, or `nothing` for an edge that the drawing does not draw. A straight edge
# has the same points in both. A curved edge has the points of a chain of Bézier
# curves, which leaves each box at a right angle to the side that it crosses.
# An edge ends at the ring of a vertex in `joined`, which the drawing lights.
function _compute_drawn_edges(layout::GraphLayout, boxes, drawing_map, drag, joined, style,
                              edge_shape::Symbol)
    highlight_vertex = layout.highlight_vertex
    index_of = Dict{UInt,Int}(objectid(getfield(vertex_layout, :vertex)[]) => i
                              for (i, vertex_layout) in enumerate(layout.vertex_layouts)
                              if vertex_layout isa VertexLayout)
    rim(i) = _get_drawn_rim(boxes[i], style,
                            (highlight_vertex !== nothing &&
                             getfield(layout.vertex_layouts[i], :vertex)[] === highlight_vertex) ||
                            getfield(layout.vertex_layouts[i], :vertex)[] in joined)
    edges = Any[]
    for edge_layout in layout.edge_layouts
        edge = edge_layout isa EdgeLayout ? getfield(edge_layout, :edge)[] : nothing
        source = edge isa GraphEdge ? get(index_of, objectid(edge.source), 0) : 0
        target = edge isa GraphEdge ? get(index_of, objectid(edge.target), 0) : 0
        boxed = source != 0 && target != 0
        # An edge whose ends have no box is drawn along its route as it is.
        route = !(edge_layout isa EdgeLayout) ? nothing :
                !boxed ? Tuple{Int,Int}[(Int(point[1]), Int(point[2])) for point in edge_layout.route] :
                _make_drawn_route(edge_layout.route, boxes[source], boxes[target],
                                  rim(source), rim(target), drawing_map;
                                  straight = drag !== nothing && drag.index in (source, target))
        if route === nothing || length(route) < 2
            push!(edges, nothing)
        elseif edge_shape === :straight
            push!(edges, (points = route, path = route, segments = 0))
        else
            start = boxed ? _get_rim_normal(rim(source), route[1]) :
                            _get_unit_vector(route[2] .- route[1])
            finish = boxed ? .-(_get_rim_normal(rim(target), route[end])) :
                             _get_unit_vector(route[end] .- route[end - 1])
            curve = _compute_curve_points(route, start, finish)
            segments = _get_curve_segments(curve)
            push!(edges, (points = curve, path = tessellate_spline(curve, :bezier, segments),
                          segments = segments))
        end
    end
    edges
end

# The element that draws the edge `drawn_edge`: a polyline, or a curve.
_make_edge_element(edge_shape::Symbol, drawn_edge; color, width, end_arrow, arrow_size) =
    edge_shape === :straight ?
        GraphicsPolyline(drawn_edge.points; color, width, end_arrow, arrow_size) :
        GraphicsSpline(drawn_edge.points; kind = :bezier, color, width, end_arrow, arrow_size,
                       segments = drawn_edge.segments)

const _EDGE_SHAPES = (:straight, :curved)

# The shape of the edges: the one that the menu of the graph chose, else the
# keyword of the drawing.
_get_edge_shape(p, layout::GraphLayout) = something(layout.edge_shape, p.edge_shape)

"""
    GraphLayoutToGraphicsCanvas(; theme = nothing, edge_shape = :straight)

The drawing of a `GraphLayout`. `theme` is a [`GraphTheme`](@ref), scaled or not,
or `nothing` for the default values; `style` holds every value of the theme as one
`NamedTuple`, read once at each print with `unwrap_cell`.

`edge_shape` is `:straight`, a line along the route of each edge, or `:curved`, a
smooth curve through the route, which leaves each box at a right angle to the side
that it crosses.
"""
struct GraphLayoutToGraphicsCanvas <: Projection
    style::Any
    edge_shape::Symbol
end

function GraphLayoutToGraphicsCanvas(; theme = nothing, edge_shape::Symbol = :straight)
    edge_shape in _EDGE_SHAPES || throw(ArgumentError(
        "GraphLayoutToGraphicsCanvas: the edge_shape is :straight or :curved, " *
        "got $(repr(edge_shape))."))
    GraphLayoutToGraphicsCanvas(make_theme_values_field(GraphTheme, theme), edge_shape)
end

@iomap struct GraphLayoutToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell      # vector of (x, y, content_iomap) per vertex layout
    node_elements::Cell     # index into `output.elements` of each vertex's box
    drawn_boxes::Cell       # (x, y, w, h) of the content of each vertex, as drawn
    label_iomaps::Cell      # the IO map of the label of each edge, or nothing
    label_boxes::Cell       # (x, y, w, h) of the label of each edge, as drawn, or nothing
end

function print_document(p::GraphLayoutToGraphicsCanvas, recursion, layout::GraphLayout, ctx)
    style = unwrap_cell(p.style)
    # Recurse each vertex's content into a canvas, tracking its placed origin.
    child_iomaps = Cell(@computation begin
        n = length(layout.vertex_layouts)
        entries = Any[]
        for i in 1:n
            vl = layout.vertex_layouts[i]
            if vl isa VertexLayout
                v = getfield(vl, :vertex)[]
                content = v isa GraphVertex ? getfield(v, :content)[] : nothing
                if content !== nothing
                    cim = print_child(recursion, content, _make_graph_part_context(ctx, layout, (@reference_step vertex_layouts), (@reference_step [i]), (@reference_step vertex), (@reference_step content)))
                    push!(entries, (Int(vl.x), Int(vl.y), cim))
                else
                    push!(entries, (Int(vl.x), Int(vl.y), nothing))
                end
            else
                push!(entries, (0, 0, nothing))
            end
        end
        entries
    end)

    # Recurse each edge's optional label into a canvas, which a path, a key and a
    # click reach as they reach the content of a vertex.
    edge_label_iomaps = Cell(@computation begin
        m = length(layout.edge_layouts)
        out = Any[]
        for i in 1:m
            el = layout.edge_layouts[i]
            e = el isa EdgeLayout ? getfield(el, :edge)[] : nothing
            label = e isa GraphEdge ? getfield(e, :label)[] : nothing
            if label !== nothing
                push!(out, print_child(recursion, label, _make_graph_part_context(ctx, layout, (@reference_step edge_layouts), (@reference_step [i]), (@reference_step edge), (@reference_step label))))
            else
                push!(out, nothing)
            end
        end
        out
    end)

    # The drag that has started, or nothing. A press that has not become a drag
    # keeps this cell at `nothing`, so it draws nothing again.
    started_drag = Cell(@computation _find_started_drag(layout))

    # The index of the vertex under the pointer, or 0. A cell of its own, so a move
    # inside one vertex draws nothing again.
    lit = Cell(@computation _find_lit_vertex(layout))

    # The map from the layout to the drawing: the zoom and the margin.
    drawing_map = Cell(@computation _compute_drawing_map(layout, style))

    # The box of the content of each vertex, where the drawing draws it.
    drawn_boxes = Cell(@computation _compute_drawn_boxes(layout, drawing_map[], started_drag[]))

    # Each edge, where the drawing draws it.
    drawn_edges = Cell(@computation begin
        lit_vertex = lit[] == 0 ? nothing : getfield(layout.vertex_layouts[lit[]], :vertex)[]
        _compute_drawn_edges(layout, drawn_boxes[], drawing_map[], started_drag[],
                             _collect_joined_vertices(layout, lit_vertex), style,
                             _get_edge_shape(p, layout))
    end)

    # The box of the label of each edge, at the middle of its line.
    drawn_labels = Cell(@computation _compute_label_boxes(drawn_edges[], edge_label_iomaps[]))

    # The drawing, and where each vertex's box ended up in it. The two are built
    # together because the second is a fact about the first: element order
    # depends on how many edges and edge labels came before the nodes, and a
    # second pass that recomputed it would be the same code twice.
    drawn = Cell(@computation begin
        result = Any[]
        # Read the highlights once per repaint. They are compared by identity
        # against the vertex/edge each layout holds.
        highlight_vertex = layout.highlight_vertex
        highlight_edge = layout.highlight_edge
        # The vertex under the pointer and the vertices that an edge joins to it,
        # through a line or not.
        lit_vertex = lit[] == 0 ? nothing : getfield(layout.vertex_layouts[lit[]], :vertex)[]
        joined = _collect_joined_vertices(layout, lit_vertex)
        # The drag of a vertex moves that vertex and the edges at it, and the
        # layout stays as it is until the drop.
        drag = started_drag[]
        boxes = drawn_boxes[]
        # Where each vertex's node box lands in `result` — the reference target
        # for "beside node i", which is what an annotation anchors to.
        node_at = Union{Int,Nothing}[nothing for _ in 1:length(layout.vertex_layouts)]
        # Edges first (behind the nodes), each with its optional label centred on
        # the route midpoint.
        labels = edge_label_iomaps[]
        label_boxes = drawn_labels[]
        edges = drawn_edges[]
        edge_shape = _get_edge_shape(p, layout)
        for i in 1:length(layout.edge_layouts)
            drawn_edge = edges[i]
            drawn_edge === nothing && continue
            e = getfield(layout.edge_layouts[i], :edge)[]
            # An edge that is not visible joins its vertices and draws nothing.
            e isa GraphEdge && !e.visible && continue
            directed = e isa GraphEdge ? e.directed : false
            push!(result, _make_edge_element(edge_shape, drawn_edge; color = style.edge,
                width = style.edge_width, end_arrow = directed, arrow_size = style.arrow_size))
            # An edge of the vertex under the pointer is lit over its own line.
            if lit_vertex !== nothing && e isa GraphEdge && (e.source === lit_vertex || e.target === lit_vertex)
                push!(result, _make_edge_element(edge_shape, drawn_edge;
                    color = style.light_edge, width = style.highlight_width,
                    end_arrow = directed, arrow_size = style.arrow_size))
            end
            # The highlighted edge is re-stroked over its own line, keeping the
            # arrowhead it already drew.
            if highlight_edge !== nothing && e === highlight_edge
                push!(result, _make_edge_element(edge_shape, drawn_edge;
                    color = style.highlight, width = style.highlight_width,
                    end_arrow = directed, arrow_size = style.arrow_size))
            end
            label_box = i <= length(label_boxes) ? label_boxes[i] : nothing
            if label_box !== nothing
                push!(result, GraphicsCanvas(CellVector(Cell[Cell(labels[i].output)]);
                                             x = label_box[1], y = label_box[2]))
            end
        end
        # Node boxes + content on top, and the dragged one over every other.
        entries = child_iomaps[]
        vertex_count = length(layout.vertex_layouts)
        order = drag === nothing ? (1:vertex_count) :
                vcat([j for j in 1:vertex_count if j != drag.index], [drag.index])
        for i in order
            vl = layout.vertex_layouts[i]
            vl isa VertexLayout || continue
            x, y, w, h = boxes[i]
            pad = style.node_padding
            bx, by = x - pad, y - pad
            bw, bh = w + 2*pad, h + 2*pad
            # The ring goes behind the box, inflated by the gap, so the box's
            # own opaque fill leaves only the ring's edge showing.
            v = getfield(vl, :vertex)[]
            if highlight_vertex !== nothing && v === highlight_vertex
                g = style.highlight_gap + style.highlight_width
                push!(result, GraphicsRect(bx - g, by - g, bw + 2*g, bh + 2*g;
                    color = style.highlight, radius = style.node_radius + g))
            elseif v in joined
                g = style.highlight_gap + style.highlight_width
                push!(result, GraphicsRect(bx - g, by - g, bw + 2*g, bh + 2*g;
                    color = style.light, radius = style.node_radius + g))
            end
            push!(result, GraphicsRect(bx, by, bw, bh;
                color = style.node_fill, radius = style.node_radius,
                border_width = style.node_border_width, border_color = style.node_border))
            node_at[i] = length(result)
            entry = i <= length(entries) ? entries[i] : nothing
            if entry !== nothing && entry[3] !== nothing
                cim = entry[3]
                push!(result, GraphicsCanvas(CellVector(Cell[Cell(cim.output)]); x, y))
            end
        end
        (result, node_at)
    end)

    elements = CellVector(@computation drawn[][1])
    node_elements = Cell(@computation drawn[][2])

    # How much room the graph needs, read off the layout that placed it.
    #
    # Without this the canvas declares 0×0, and every container that asks a
    # child how much room it wants is told "none": an `AnchoredLayout` around a
    # graph then reports zero height, the vertical layout above it reserves
    # nothing, and the graph draws straight over whatever follows it. That is
    # the same wrong answer for four nodes as for four hundred, which is why
    # callers ended up ESTIMATING a height from the node count — a guess that
    # cannot tell a tall thin chain from a wide flat mesh.
    #
    # A cell rather than a number, because the layout is reactive and often
    # arrives late: a topology exists only once a run has built the network, so
    # the graph is empty when first drawn and gets its nodes afterwards. The
    # extent has to recompute when it does, or its container reserves room for
    # the empty version for the rest of the session.
    #
    # Read from the layout rather than by walking the drawn elements: the
    # placement is what decides the size, and measuring elements would need a
    # text-measuring function this stage has no business holding.
    extent = Cell(Computation(function ()
        right = bottom = 0
        # The node BOX is the vertex inflated by its padding on every side, and a
        # highlight ring sits outside that — both are painted, so both count.
        # A dragged box is painted where the pointer took it.
        margin = style.node_padding + style.highlight_gap + style.highlight_width
        for box in drawn_boxes[]
            box === nothing && continue
            right  = max(right,  box[1] + box[3] + margin)
            bottom = max(bottom, box[2] + box[4] + margin)
        end
        # A route may bow outside every box it connects, and an edge label sits
        # on the route, so the line of each edge counts too.
        for drawn_edge in drawn_edges[]
            drawn_edge === nothing && continue
            for point in drawn_edge.path
                right  = max(right,  ceil(Int, point[1]))
                bottom = max(bottom, ceil(Int, point[2]))
            end
        end
        (right, bottom)
    end))

    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(extent[][1])),
                            Cell(@computation Int32(extent[][2])),
                            elements, layout_none, true, Cell(nothing))
    GraphLayoutToGraphicsCanvasIoMap(p, layout, canvas, child_iomaps, node_elements, drawn_boxes,
                                     edge_label_iomaps, drawn_labels)
end

# A GraphicsCanvas is not a selectable container, so we never forward a selection
# onto it here; the in-node cursor is forward-projected by the content's own
# sub-pipeline (the node-box selection band is drawn in place if added later).
function map_reference_forward(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, reference)
    @reference_case reference begin
        # A whole vertex is its node box in the drawing. Nothing selects a
        # vertex — the cursor lives in its content — but something has to be
        # able to *point at* one: an annotation anchored beside a node asks the
        # projection where that node was drawn, and this is the answer.
        ::GraphLayout.vertex_layouts[i].vertex => begin
            indices = iomap.node_elements
            (i < 1 || i > length(indices)) && return nothing
            k = indices[i]
            k === nothing ? nothing : (@reference iomap.output elements[k])
        end
        ::GraphLayout.vertex_layouts[i].vertex.content.rest... => begin
            entries = iomap.child_iomaps
            (i < 1 || i > length(entries)) && return nothing
            entry = entries[i]
            (entry === nothing || entry[3] === nothing) && return nothing
            cim = entry[3]
            inner = map_reference_forward(cim.projection, cim, rest)
            inner === nothing && return nothing
            outer = find_node_reference(iomap.output, unwrap_cell(cim.output); depth = 4)
            outer === nothing ? nothing : concat_references(outer, inner)
        end
        ::GraphLayout.edge_layouts[i].edge.label.rest... => begin
            labels = iomap.label_iomaps
            (i < 1 || i > length(labels) || labels[i] === nothing) && return nothing
            lim = labels[i]
            inner = map_reference_forward(lim.projection, lim, rest)
            inner === nothing && return nothing
            outer = find_node_reference(iomap.output, unwrap_cell(lim.output); depth = 4)
            outer === nothing ? nothing : concat_references(outer, inner)
        end
        __ => nothing
    end
end

# A point maps to the vertex whose box holds it, with the hit test of a click, and
# on into the content of the vertex with the point in the frame of its canvas. A
# point in the box but on no part of the content is the vertex itself.
function map_reference_backward(::GraphLayoutToGraphicsCanvas,
                                iomap::GraphLayoutToGraphicsCanvasIoMap, reference)
    point = find_reference_point(reference)
    point === nothing && return nothing
    hit = _find_vertex_at(iomap, point.x, point.y)
    hit === nothing && return _map_label_point_backward(iomap, point)
    (i, cim, x, y) = hit
    inner = cim === nothing ? nothing :
            map_reference_backward(cim.projection, cim, PointReferenceStep(x, y))
    inner === nothing &&
        return @reference iomap.input vertex_layouts[i].vertex
    @reference iomap.input vertex_layouts[i].vertex.content.^(inner)
end

map_reference_backward(::GraphLayoutToGraphicsCanvas, iomap, reference) = nothing

# A change whose route leads into the content of a vertex, such as a part of a
# drag that a part of that content started, goes to that content in the frame of
# its canvas. Any other change is read at the point of the graph.
function read_intent(p::GraphLayoutToGraphicsCanvas, recursion, change::Intent,
                     iomap::GraphLayoutToGraphicsCanvasIoMap)
    route = change.route
    (route === nothing || isempty(get_reference_steps(strip_reference_types(route)))) ||
        return read_routed_child(recursion, change, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    Intent(change.gesture, read_intent(p, iomap, payload), change.description, change.domain)
end

# The IO maps of the contents of the vertices, which a route reaches.
get_child_iomaps(iomap::GraphLayoutToGraphicsCanvasIoMap) =
    Any[Any[entry[3] for entry in iomap.child_iomaps if entry isa Tuple && entry[3] !== nothing]...,
        Any[label for label in iomap.label_iomaps if label !== nothing]...]

read_child_by_route(::GraphLayoutToGraphicsCanvas, recursion, change::Intent,
                    iomap::GraphLayoutToGraphicsCanvasIoMap, child) =
    read_routed_entry_child(recursion, change, child; entries = _collect_drawn_entries(iomap))

# The content of each vertex at the corner where the drawing draws it, as the
# entries `(x, y, content_iomap)` of a container.
_collect_drawn_entries(iomap::GraphLayoutToGraphicsCanvasIoMap) =
    Any[Any[box === nothing ? entry : (box[1], box[2], entry[3])
            for (box, entry) in zip(iomap.drawn_boxes, iomap.child_iomaps)]...,
        Any[(box[1], box[2], label) for (box, label) in zip(iomap.label_boxes, iomap.label_iomaps)
            if box !== nothing && label !== nothing]...]

# Route a left click into the node whose content box contains it. Coordinates are
# translated into the content canvas's local frame (mirrors TableToGraphics). A
# left press can start the drag of a vertex, and the parts of that drag come here
# by the path of the graph.
function read_intent(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    layout = iomap.input
    drag = layout.drag
    event isa Union{DragMove, DragEnd, DragCancel} && return _read_vertex_drag(iomap, drag, event)
    if event isa MouseMove
        (drag === nothing || drag.started) && return _read_graph_move(iomap, event)
        return join_move_answers(_read_vertex_press_move(iomap, drag, event),
                                 _read_graph_move(iomap, event))
    end
    # A left release ends a press that did not become a drag, which was a click,
    # and a drag that no drag wrapper took; a new left press ends a press whose
    # release came to no part of the graph.
    if event isa MouseUp && event.button === :left && drag !== nothing
        return join_move_answers(_write_vertex_drag(layout, nothing),
                                 _forward_to_selected(iomap, event))
    end
    if event isa MouseDown && event.button === :left
        return join_move_answers(drag === nothing ? nothing : _write_vertex_drag(layout, nothing),
                                 _read_vertex_press(iomap, event))
    end
    is_outward_gesture(event) && return _route_outward(iomap, event)
    if event isa MouseClick && event.button === :left
        op = _route_click(iomap, event)
        op === nothing || return op
        return nothing
    end
    event isa MouseScroll && event.modifiers.ctrl && return _read_ctrl_wheel(iomap, event)
    # Coordless events (keyboard) go to whichever node content holds the cursor.
    _forward_to_selected(iomap, event)
end

# Ctrl and the wheel. The content of the vertex under the point reads the turn
# first, in the frame of its canvas, so a part of the content that zooms keeps
# it. A turn that the content does not take zooms the layout.
function _read_ctrl_wheel(iomap::GraphLayoutToGraphicsCanvasIoMap, event::MouseScroll)
    hit = _find_vertex_at(iomap, event.x, event.y)
    if hit !== nothing && hit[2] !== nothing
        (i, cim, x, y) = hit
        answer = read_intent(cim.projection, cim, shift_event_position(event, x - event.x, y - event.y))
        answer = _reroot_vertex_answer(answer, i, cim.input)
        answer === nothing || return answer
    end
    notches = event.dy != 0 ? event.dy : event.dx
    notches == 0 && return nothing
    zoom = _compute_next_zoom(iomap.input, notches)
    zoom === nothing ? nothing : _write_layout_zoom(iomap.input, zoom)
end

# The box `(x, y, w, h)` of the label of each edge, by its index in
# `edge_layouts`: the canvas of the label, centred on the middle of the line of the
# edge, or `nothing` for an edge that is not drawn or has no label.
function _compute_label_boxes(edges, labels)
    boxes = Union{Nothing,NTuple{4,Int}}[]
    for i in eachindex(edges)
        label = i <= length(labels) ? labels[i] : nothing
        if edges[i] === nothing || label === nothing
            push!(boxes, nothing)
            continue
        end
        canvas = label.output
        w = canvas isa GraphicsCanvas ? Int(canvas.w) : 0
        h = canvas isa GraphicsCanvas ? Int(canvas.h) : 0
        x, y = _route_midpoint(edges[i].path)
        push!(boxes, (x - w ÷ 2, y - h ÷ 2, w, h))
    end
    boxes
end

# The edge whose label holds the point `(px, py)`: its index, the IO map of the
# label and the point in the frame of the canvas of the label, or `nothing`. The
# label drawn last is on top, so the search goes from the end.
function _find_label_at(iomap::GraphLayoutToGraphicsCanvasIoMap, px, py)
    boxes = iomap.label_boxes
    labels = iomap.label_iomaps
    for j in length(boxes):-1:1
        box = boxes[j]
        (box === nothing || j > length(labels) || labels[j] === nothing) && continue
        x, y, w, h = box
        (x <= px < x + w && y <= py < y + h) || continue
        label = labels[j]
        canvas = label.output
        ox = canvas isa GraphicsCanvas ? Int(canvas.x) : 0
        oy = canvas isa GraphicsCanvas ? Int(canvas.y) : 0
        return (j, label, px - x - ox, py - y - oy)
    end
    nothing
end

# A point on the label of an edge maps into the label, and a point on the label but
# on no part of it is the label itself. A point on no label maps to nothing.
function _map_label_point_backward(iomap::GraphLayoutToGraphicsCanvasIoMap, point)
    hit = _find_label_at(iomap, point.x, point.y)
    hit === nothing && return nothing
    (j, label, x, y) = hit
    inner = map_reference_backward(label.projection, label, PointReferenceStep(x, y))
    inner === nothing && return @reference iomap.input edge_layouts[j].edge.label
    @reference iomap.input edge_layouts[j].edge.label.^(inner)
end

# The vertex whose box holds the point `(px, py)`: its index, the IO map of its
# content (`nothing` when the content printed none), and the point in the frame
# of the content canvas. A click and a point find a vertex with this one hit test.
function _find_vertex_at(iomap::GraphLayoutToGraphicsCanvasIoMap, px, py)
    layout = iomap.input
    entries = iomap.child_iomaps
    boxes = iomap.drawn_boxes
    # The last box drawn is on top, so the search goes from the end.
    for i in length(layout.vertex_layouts):-1:1
        i <= length(boxes) && boxes[i] !== nothing || continue
        x, y, w, h = boxes[i]
        (px >= x && px < x + w && py >= y && py < y + h) || continue
        entry = i <= length(entries) ? entries[i] : nothing
        (entry === nothing || entry[3] === nothing) && return (i, nothing, 0, 0)
        cim = entry[3]
        canvas = cim.output
        ox = canvas isa GraphicsCanvas ? Int(canvas.x) : 0
        oy = canvas isa GraphicsCanvas ? Int(canvas.y) : 0
        return (i, cim, px - x - ox, py - y - oy)
    end
    nothing
end

# A move of the pointer. The content of the vertex that the graph's own mouse
# target is in gets it first, when the point is not on that content: for that
# content the move is the leave of the pointer. Then the part at the point answers:
# the content of a vertex reads the move itself, and a point in the box of a vertex
# but off its content is the vertex.
function _read_graph_move(iomap::GraphLayoutToGraphicsCanvasIoMap, event::MouseMove)
    hit = _find_vertex_at(iomap, event.x, event.y)
    new_answer = nothing
    new_vertex = 0
    if hit !== nothing
        (i, cim, x, y) = hit
        canvas = cim === nothing ? nothing : cim.output
        if canvas isa GraphicsCanvas && hit_element_at(canvas, x, y) !== nothing
            move = MouseMove(x, y, event.buttons, event.modifiers; time = event.time)
            answer = shift_operation_position(read_child_move(cim, move), event.x - x, event.y - y)
            new_answer = _reroot_vertex_answer(answer, i, cim.input)
            new_vertex = i
        else
            new_answer = ReplaceMouseTargetOperation(@reference iomap.input vertex_layouts[i].vertex)
        end
    end
    old = _get_target_vertex(iomap)
    (old == 0 || old == new_vertex) && return new_answer
    entry = iomap.child_iomaps[old]
    (entry === nothing || entry[3] === nothing) && return new_answer
    cim = entry[3]
    box = iomap.drawn_boxes[old]
    canvas = cim.output
    dx = box[1] + (canvas isa GraphicsCanvas ? Int(canvas.x) : 0)
    dy = box[2] + (canvas isa GraphicsCanvas ? Int(canvas.y) : 0)
    left = read_child_leave(cim, event, dx, dy)
    join_move_answers(_reroot_vertex_answer(left, old, cim.input), new_answer)
end

# The answer of `content`, the content of vertex `i`, in the graph's own space. A
# path gets the typed steps to the content, because it points to a place inside a
# node and only the graph holds the place of that node. A widget that holds its
# parts answers a path without types, which gets them from the content. An
# operation that names its part by a path of its own, such as the open of the menu
# of a part, gets the same steps. An operation that carries its own subject
# travels, and any other operation is dropped: an operation that no reader can
# place is worse than no answer.
_reroot_vertex_answer(answer, i::Int, content) =
    _reroot_part_answer(answer, (part, path) -> _make_vertex_content_reference(i, part, path), content)

# The answer of `label`, the label of edge `i`, in the graph's own space, by the
# rules of the content of a vertex.
_reroot_label_answer(answer, i::Int, label) =
    _reroot_part_answer(answer, (part, path) -> _make_edge_label_reference(i, part, path), label)

# The answer of `part`, a part of the graph that `place(part, path)` places: a path
# in `part` becomes a path from the layout.
_reroot_part_answer(::Nothing, place, part) = nothing
_reroot_part_answer(op::CompoundOperation, place, part) =
    join_move_answers((_reroot_part_answer(member, place, part) for member in op.operations)...)
# A wrapper, such as a write of view state, travels with what it holds.
function _reroot_part_answer(op::WrappingOperation, place, part)
    inner = _reroot_part_answer(get_wrapped_operation(op), place, part)
    inner === nothing ? nothing : rewrap_operation(op, inner)
end
# A write that carries its own document travels as it is, such as the knob of a
# slider that is held.
_reroot_part_answer(op::ReplaceReferencedValueOperation, place, part) =
    op.document === nothing ? nothing : op
function _reroot_part_answer(op, place, part)
    if !(op isa ReplacePathOperation)
        is_self_contained_operation(op) && return op
        reference = operation_reference(op)
        reference === nothing && return nothing
        return retarget_operation(op, place(part, reference))
    end
    make_path_operation(op, place(part, get_operation_path(op)))
end

# The path `path` in the content of vertex `i` as a path from the layout, with the
# types of its nodes, which the stages of the graph read.
function _make_vertex_content_reference(i::Int, content, path)
    is_fully_typed_reference(path) ||
        (path = annotate_reference_types(content, strip_reference_types(path)))
    @reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex::GraphVertex.content.^(path)
end

# The path `path` in the label of edge `i` as a path from the layout.
function _make_edge_label_reference(i::Int, label, path)
    is_fully_typed_reference(path) ||
        (path = annotate_reference_types(label, strip_reference_types(path)))
    @reference ::GraphLayout.edge_layouts::CellVector[i]::EdgeLayout.edge::GraphEdge.label.^(path)
end

# The vertex `i` that the mouse target of `layout` names, a path that begins
# `vertex_layouts[i].vertex`: the vertex under the pointer, or 0.
function _find_lit_vertex(layout::GraphLayout)
    target = get_mouse_target(layout)
    target isa Reference || return 0
    steps = collect(get_reference_steps(strip_reference_types(target)))
    length(steps) >= 3 || return 0
    (steps[1] isa FieldReferenceStep && steps[1].name == "vertex_layouts" &&
     steps[2] isa RangeReferenceStep && steps[3] isa FieldReferenceStep &&
     steps[3].name == "vertex") || return 0
    i = steps[2].stop
    1 <= i <= length(layout.vertex_layouts) && layout.vertex_layouts[i] isa VertexLayout ? i : 0
end

# `vertex` and every vertex that an edge of the layout joins to it, or none for
# no vertex.
function _collect_joined_vertices(layout::GraphLayout, vertex)
    joined = Base.IdSet{Any}()
    vertex === nothing && return joined
    push!(joined, vertex)
    for edge_layout in layout.edge_layouts
        edge_layout isa EdgeLayout || continue
        edge = getfield(edge_layout, :edge)[]
        edge isa GraphEdge || continue
        edge.source === vertex && push!(joined, edge.target)
        edge.target === vertex && push!(joined, edge.source)
    end
    joined
end

# The vertex `i` whose content holds the part that the graph's own mouse target
# names, a path that begins `vertex_layouts[i].vertex.content`, or 0.
function _get_target_vertex(iomap::GraphLayoutToGraphicsCanvasIoMap)
    steps = get_reference_steps(something(get_mouse_target(iomap.input), EmptyReference()))
    length(steps) >= 4 || return 0
    (steps[1] isa FieldReferenceStep && steps[1].name == "vertex_layouts" &&
     steps[2] isa RangeReferenceStep && steps[3] isa FieldReferenceStep &&
     steps[3].name == "vertex" && steps[4] isa FieldReferenceStep &&
     steps[4].name == "content") || return 0
    i = steps[2].stop
    1 <= i <= length(iomap.child_iomaps) ? i : 0
end

# ── The drag of a vertex ─────────────────────────────────────────────────────
#
# `GraphLayout.drag` holds `(vertex, index, origin, offset, started)` while the
# button is down on a vertex. It is view state, so each write carries the layout
# itself, and no history records it; the drop is the edit. The graph is the part
# whose drag is on: it starts the drag after the small move, so a press that does
# not move is still a click, and the drag wrapper then sends it `DragMove`,
# `DragEnd` and `DragCancel` by its path.

# The pixels that a press on a vertex moves on one axis before it drags the
# vertex. A release counts as a click while each axis moved less than the same
# number (`ClickRecognition`), so a drag starts where a click stops.
const _VERTEX_DRAG_START = 5

_write_vertex_drag(layout::GraphLayout, drag) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(layout, "drag", drag))

# A left press. The content of the vertex under the point reads it first, in the
# frame of its canvas, so a part of the content that takes a press, such as the
# edge of a column of a table, keeps it. A plain press that the content does not
# take, on the box that the graph draws, keeps the vertex and the point of the
# press: no drag is on yet, so a release before the pointer moves is a click.
function _read_vertex_press(iomap::GraphLayoutToGraphicsCanvasIoMap, event::MouseDown)
    answer = _route_press(iomap, event)
    answer === nothing || return answer
    event.modifiers == ModifierKeys() || return nothing
    i = _find_node_at(iomap, event.x, event.y)
    i == 0 && return nothing
    layout = iomap.input
    _write_vertex_drag(layout, (vertex = layout.vertex_layouts[i].vertex, index = i,
                                origin = (event.x, event.y), offset = (0, 0),
                                started = false))
end

# The answer of the content of the vertex under the point of `event`, a press.
function _route_press(iomap::GraphLayoutToGraphicsCanvasIoMap, event::MouseDown)
    hit = _find_vertex_at(iomap, event.x, event.y)
    (hit === nothing || hit[2] === nothing) && return nothing
    (i, cim, x, y) = hit
    answer = read_intent(cim.projection, cim, shift_event_position(event, x - event.x, y - event.y))
    _reroot_vertex_answer(answer, i, cim.input)
end

# The vertex whose drawn box, its content and the padding around it, holds the
# point, or 0. The last box drawn is on top, so the search goes from the end.
function _find_node_at(iomap::GraphLayoutToGraphicsCanvasIoMap, px, py)
    boxes = iomap.drawn_boxes
    pad = unwrap_cell(iomap.projection.style).node_padding
    for i in length(boxes):-1:1
        boxes[i] === nothing && continue
        x, y, w, h = boxes[i]
        (x - pad <= px < x + w + pad && y - pad <= py < y + h + pad) && return i
    end
    0
end

# Before the drag of a vertex starts: a move with the left button held past the
# small move starts it, and the graph is the part whose drag is on. A move without
# the left button shows a release that the window did not get, and ends the press.
function _read_vertex_press_move(iomap::GraphLayoutToGraphicsCanvasIoMap, drag, event::MouseMove)
    event.buttons.left || return _write_vertex_drag(iomap.input, nothing)
    ox, oy = drag.origin
    max(abs(event.x - ox), abs(event.y - oy)) >= _VERTEX_DRAG_START || return nothing
    join_move_answers(
        _write_vertex_drag(iomap.input, merge(drag, (offset = (event.x - ox, event.y - oy),
                                                     started = true))),
        StartDragOperation(EmptyReference(), nothing),
        make_screen_pointer_shape_operation(:closed_hand))
end

# The parts of the drag of a vertex, which come by the path of the graph: a move
# sets how far the vertex moved, the release drops it there, and a cancel puts it
# back where it was.
function _read_vertex_drag(iomap::GraphLayoutToGraphicsCanvasIoMap, drag, event)
    (drag === nothing || !drag.started) && return nothing
    layout = iomap.input
    ox, oy = drag.origin
    if event isa DragMove
        offset = (event.x - ox, event.y - oy)
        offset == drag.offset && return nothing
        return _write_vertex_drag(layout, merge(drag, (offset = offset,)))
    end
    clear = join_move_answers(_write_vertex_drag(layout, nothing),
                                   make_screen_pointer_shape_operation(nothing))
    event isa DragCancel && return clear
    dropped = merge(drag, (offset = (event.x - ox, event.y - oy),))
    join_move_answers(_make_vertex_drop_operation(layout, dropped,
                                                  unwrap_cell(iomap.projection.style)), clear)
end

# The drop of the dragged vertex, as one edit of the constraints of the graph.
# The constraints of other kinds and the pins of the other vertices stay; the
# dragged vertex gets a pin at its new corner; and every other vertex without a
# pin gets a start at its corner, so the next layout begins from what the person
# saw. The constraints hold corners of the layout, so the pin is the corner where
# the pointer took the box, through the inverse of the zoom.
function _make_vertex_drop_operation(layout::GraphLayout, drag, style)
    graph = layout.graph
    graph isa GraphGraph || return nothing
    _find_started_drag(layout) === nothing && return nothing
    constraints = GraphConstraint[]
    pinned = Set{UInt}()
    for constraint in graph.constraints
        constraint.kind === :start && continue
        if constraint.kind === :pin
            constraint.target === drag.vertex && continue
            push!(pinned, objectid(constraint.target))
        end
        push!(constraints, constraint)
    end
    drawing_map = _compute_drawing_map(layout, style)
    for (i, vertex_layout) in enumerate(layout.vertex_layouts)
        vertex_layout isa VertexLayout || continue
        if i == drag.index
            corner = _get_dragged_corner(round.(Int, _get_zoomed_corner(drawing_map, vertex_layout)),
                                         drag.offset, drawing_map.margin)
            push!(constraints, GraphConstraint(drag.vertex, :pin,
                                               _get_layout_corner(drawing_map, vertex_layout, corner)))
        elseif !(objectid(vertex_layout.vertex) in pinned)
            push!(constraints, GraphConstraint(vertex_layout.vertex, :start,
                                               (Int(vertex_layout.x), Int(vertex_layout.y))))
        end
    end
    ReplaceReferencedValueOperation(graph, "constraints", constraints)
end

# The drag of a vertex that has started, or `nothing`. A drag whose vertex is no
# longer at its index, after an edit of the graph, moves nothing.
function _find_started_drag(layout::GraphLayout)
    drag = layout.drag
    (drag === nothing || !drag.started) && return nothing
    1 <= drag.index <= length(layout.vertex_layouts) || return nothing
    vertex_layout = layout.vertex_layouts[drag.index]
    (vertex_layout isa VertexLayout && vertex_layout.vertex === drag.vertex) || return nothing
    drag
end

# The corner of a dragged box: the corner where the drawing draws it, moved by
# `offset`, and never nearer to the left or the top of the drawing than the
# margin, so its frame stays painted.
_get_dragged_corner(corner, offset, margin) =
    (max(margin, corner[1] + offset[1]), max(margin, corner[2] + offset[2]))

function _route_click(iomap::GraphLayoutToGraphicsCanvasIoMap, g::MouseClick)
    hit = _find_vertex_at(iomap, g.x, g.y)
    if hit === nothing
        # A click on the label of an edge goes to the label, in its own frame.
        label = _find_label_at(iomap, g.x, g.y)
        label === nothing && return nothing
        (j, lim, lx, ly) = label
        op = read_intent(lim.projection, lim, MouseClick(g.button, lx, ly, g.count, g.modifiers; time = g.time))
        return op === nothing ? nothing : _reroot_label_answer(op, j, lim.input)
    end
    (i, cim, x, y) = hit
    cim === nothing && return nothing
    local_evt = MouseClick(g.button, x, y, g.count, g.modifiers; time = g.time)
    op = read_intent(cim.projection, cim, local_evt)
    op === nothing ? nothing : _reroot_vertex_answer(op, i, cim.input)
end

# A dwell and a right click go to the content of the vertex at their point, as a
# click does, and the documents of the graph around that vertex read them outward.
# The answer is rerooted as it is, because a tooltip is no path into the content.
function _route_outward(iomap::GraphLayoutToGraphicsCanvasIoMap, gesture)
    hit = _find_vertex_at(iomap, gesture.x, gesture.y)
    (hit === nothing || hit[2] === nothing) &&
        return read_container_gesture(nothing, gesture, iomap.input)
    (i, cim, x, y) = hit
    answer = read_child_event(cim, shift_event_position(gesture, x - gesture.x, y - gesture.y))
    steps = _get_vertex_content_steps(i)
    answer = reroot_operation(shift_operation_position(answer, gesture.x - x, gesture.y - y), steps)
    read_container_gesture(answer, gesture, iomap.input; steps)
end

_get_vertex_content_steps(i::Integer) =
    (FieldReferenceStep("vertex_layouts"), RangeReferenceStep(i - 1, i),
     FieldReferenceStep("vertex"), FieldReferenceStep("content"))

# Dispatch a coordless event to every node's content reader, and then to the reader
# of each edge label; the part that carries the cursor answers. Mirrors
# TableToGraphics.
function _forward_to_selected(iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    entries = iomap.child_iomaps
    for i in 1:length(entries)
        entry = entries[i]
        (entry === nothing || entry[3] === nothing) && continue
        cim = entry[3]
        op = read_intent(cim.projection, cim, event)
        op === nothing && continue
        answer = _reroot_vertex_answer(op, i, cim.input)
        answer === nothing || return answer
    end
    labels = iomap.label_iomaps
    for j in 1:length(labels)
        lim = labels[j]
        lim === nothing && continue
        op = read_intent(lim.projection, lim, event)
        op === nothing && continue
        answer = _reroot_label_answer(op, j, lim.input)
        answer === nothing || return answer
    end
    nothing
end

# @optional: the layout engine stands first, as the algorithm the pipeline runs;
# the rest is its chrome.
"""
    GraphToGraphics(engine = make_deferred_layout_engine(); extent = nothing,
                    border = 0, constraints = nothing, theme = nothing,
                    edge_shape = :straight) -> ChainingProjection

The pipeline from a `GraphGraph` straight to a `GraphicsCanvas`, with no
`TextToGraphics` step, like `TableToGraphics`: the chain of
`GraphGraphToGraphLayout(engine; extent, border, constraints)` and
`GraphLayoutToGraphicsCanvas(; theme, edge_shape)`. The stages have no recursion of
their own, so the content of a vertex prints through the recursion that encloses the
chain, for example a `NestingProjection`.
"""
GraphToGraphics(engine::GraphLayoutEngine = make_deferred_layout_engine();
                extent = nothing, border::Integer = 0, constraints = nothing,
                theme = nothing, edge_shape::Symbol = :straight) =
    ChainingProjection(GraphGraphToGraphLayout(engine; extent = extent, border = border,
                                               constraints = constraints),
                       GraphLayoutToGraphicsCanvas(; theme, edge_shape))

# ── Natural-projection registration ─────────────────────────────────────────
# A graph is a diagram, not a syntax tree: it goes through its own two stages
# (size and place, then draw), in a scroll pane of its own, so a large graph
# scrolls where it is made. The content of a vertex goes on to the natural
# renderer, so it is whatever it is, rendered the same way it would be anywhere
# else. That is what lets a diagram node be a widget, or prose, or a table.

function __init__()
    register_natural_graphics!(:graph, (; measure, appearance) -> Pair{Type,Any}[
        GraphGraph => make_scrolling_graph_projection(
            ChainingProjection(GraphGraphToGraphLayout(),
                               GraphLayoutToGraphicsCanvas(theme = get_scaled_theme!(appearance, GraphTheme)));
            measure, widget_theme = get_scaled_theme!(appearance, WidgetTheme)),
    ])
    # The names a model draws a graph with: the vertices, the edges between them,
    # and the graph that holds both.
    register_assistant_api!(GraphModule => (:GraphGraph, :GraphVertex, :GraphEdge);
        description = "A graph is `GraphGraph(vertices, edges)` of `GraphVertex(content)` " *
                      "and `GraphEdge(source, target)`; the content of a vertex is a " *
                      "document, such as `WidgetLabel(\"Paris\")`, and `open_pane!` draws " *
                      "the graph.")
end
