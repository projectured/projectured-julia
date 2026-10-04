# Fragment of `GraphModule`.
#
# GraphLayout → Graphics projection. Draws each `VertexLayout` as a node box (a
# rounded `GraphicsRect` outline at `(x, y, w, h)`) with the vertex's projected
# content canvas placed inside, and each `EdgeLayout` as a `GraphicsPolyline`
# connector along its `route` (an end arrowhead when the edge is directed), with the
# edge's optional `label` recursed to a canvas and centred on the route midpoint.
# Edges are drawn first, nodes on top.
#
# Selection: a path `vertex_layouts[i].vertex.content.…` routes into the i-th
# node's content sub-pipeline (tutorial School A — peel the steps this projection
# owns and delegate the tail through the stored child IO maps). The
# `GraphToGraphLayout` stage above maps `vertices[i].content.…` ↔
# `vertex_layouts[i].vertex.content.…`, so a selection into vertex content
# round-trips through the whole graph pipeline. Edges are decorations in v1
# (selectable later via the Phase 1 polyline hit-test).
#
# The highlight (`GraphLayout.highlight_vertex` / `highlight_edge`) is a ring
# just outside the node's box, and a re-stroke over the edge's own line. Both
# are *extra* elements keyed on the highlight cells alone — never a change to a
# node's content or geometry, so a highlight move never re-runs the layout.

# The point halfway along a polyline route by arc length — where an edge label
# sits. Falls back to the single point / origin for degenerate routes.
function _route_midpoint(route)
    n = length(route)
    n == 0 && return (0, 0)
    n == 1 && return (Int(route[1][1]), Int(route[1][2]))
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
    (Int(route[n][1]), Int(route[n][2]))
end

"""
    GraphLayoutToGraphicsCanvas(; theme = nothing)

The drawing of a `GraphLayout`. `theme` is a [`GraphTheme`](@ref), scaled or not,
or `nothing` for the default values; `style` holds every value of the theme as one
`NamedTuple`, read once at each print with `unwrap_cell`.
"""
struct GraphLayoutToGraphicsCanvas <: Projection
    style::Any
end

GraphLayoutToGraphicsCanvas(; theme = nothing) =
    GraphLayoutToGraphicsCanvas(make_theme_values_field(GraphTheme, theme))

@iomap struct GraphLayoutToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell      # vector of (x, y, content_iomap) per vertex layout
    node_elements::Cell     # index into `output.elements` of each vertex's box
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
                    cim = print_child(recursion, content, make_child_context(ctx, layout, (@reference_step vertex_layouts), (@reference_step [i]), (@reference_step vertex), (@reference_step content)))
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

    # Recurse each edge's optional label into a canvas. A decoration, like the
    # edges themselves — not selectable in v1, so no per-label iomap delegation.
    edge_label_iomaps = Cell(@computation begin
        m = length(layout.edge_layouts)
        out = Any[]
        for i in 1:m
            el = layout.edge_layouts[i]
            e = el isa EdgeLayout ? getfield(el, :edge)[] : nothing
            label = e isa GraphEdge ? getfield(e, :label)[] : nothing
            if label !== nothing
                push!(out, print_child(recursion, label, make_child_context(ctx, layout, (@reference_step edge_layouts), (@reference_step [i]), (@reference_step edge), (@reference_step label))))
            else
                push!(out, nothing)
            end
        end
        out
    end)

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
        # Where each vertex's node box lands in `result` — the reference target
        # for "beside node i", which is what an annotation anchors to.
        node_at = Union{Int,Nothing}[nothing for _ in 1:length(layout.vertex_layouts)]
        # Edges first (behind the nodes), each with its optional label centred on
        # the route midpoint.
        labels = edge_label_iomaps[]
        for i in 1:length(layout.edge_layouts)
            el = layout.edge_layouts[i]
            el isa EdgeLayout || continue
            route = el.route
            length(route) < 2 && continue
            e = getfield(el, :edge)[]
            directed = e isa GraphEdge ? e.directed : false
            push!(result, GraphicsPolyline(route; color = style.edge,
                width = style.edge_width, end_arrow = directed, arrow_size = style.arrow_size))
            # The highlighted edge is re-stroked over its own line, keeping the
            # arrowhead it already drew.
            if highlight_edge !== nothing && e === highlight_edge
                push!(result, GraphicsPolyline(route; color = style.highlight,
                    width = style.highlight_width, end_arrow = directed,
                    arrow_size = style.arrow_size))
            end
            lim = i <= length(labels) ? labels[i] : nothing
            if lim !== nothing
                lo = lim.output
                lw = lo isa GraphicsCanvas ? Int(lo.w) : 0
                lh = lo isa GraphicsCanvas ? Int(lo.h) : 0
                mx, my = _route_midpoint(route)
                push!(result, GraphicsCanvas(CellVector(Cell[Cell(lo)]);
                                             x = mx - lw ÷ 2, y = my - lh ÷ 2))
            end
        end
        # Node boxes + content on top.
        entries = child_iomaps[]
        for i in 1:length(layout.vertex_layouts)
            vl = layout.vertex_layouts[i]
            vl isa VertexLayout || continue
            x, y, w, h = Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h)
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
        for vertex_layout in layout.vertex_layouts
            vertex_layout isa VertexLayout || continue
            # The node BOX is the vertex inflated by its padding on every side,
            # and a highlight ring sits outside that — both are painted, so both
            # count.
            margin = style.node_padding + style.highlight_gap + style.highlight_width
            right  = max(right,  Int(vertex_layout.x) + Int(vertex_layout.w) + margin)
            bottom = max(bottom, Int(vertex_layout.y) + Int(vertex_layout.h) + margin)
        end
        # A route may bow outside every box it connects, and an edge label sits
        # on the route, so the waypoints count too.
        for edge_layout in layout.edge_layouts
            edge_layout isa EdgeLayout || continue
            for point in edge_layout.route
                right  = max(right,  Int(point[1]))
                bottom = max(bottom, Int(point[2]))
            end
        end
        (right, bottom)
    end))

    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(extent[][1])),
                            Cell(@computation Int32(extent[][2])),
                            elements, layout_none, true, Cell(nothing))
    GraphLayoutToGraphicsCanvasIoMap(p, layout, canvas, child_iomaps, node_elements)
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
    hit === nothing && return nothing
    (i, cim, x, y) = hit
    inner = cim === nothing ? nothing :
            map_reference_backward(cim.projection, cim, PointReferenceStep(x, y))
    inner === nothing &&
        return @reference iomap.input vertex_layouts[i].vertex
    @reference iomap.input vertex_layouts[i].vertex.content.^(inner)
end

map_reference_backward(::GraphLayoutToGraphicsCanvas, iomap, reference) = nothing

# Route a left click into the node whose content box contains it. Coordinates are
# translated into the content canvas's local frame (mirrors TableToGraphics).
function read_intent(p::GraphLayoutToGraphicsCanvas, iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    event isa MouseMove && return _read_graph_move(iomap, event)
    is_outward_gesture(event) && return _route_outward(iomap, event)
    if event isa MouseClick && event.button === :left
        op = _route_click(iomap, event)
        op === nothing || return op
        return nothing
    end
    # Coordless events (keyboard) go to whichever node content holds the cursor.
    _forward_to_selected(iomap, event)
end

# The vertex whose box holds the point `(px, py)`: its index, the IO map of its
# content (`nothing` when the content printed none), and the point in the frame
# of the content canvas. A click and a point find a vertex with this one hit test.
function _find_vertex_at(iomap::GraphLayoutToGraphicsCanvasIoMap, px, py)
    layout = iomap.input
    entries = iomap.child_iomaps
    for i in 1:length(layout.vertex_layouts)
        vl = layout.vertex_layouts[i]
        vl isa VertexLayout || continue
        x, y, w, h = Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h)
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
    vl = iomap.input.vertex_layouts[old]
    canvas = cim.output
    dx = Int(vl.x) + (canvas isa GraphicsCanvas ? Int(canvas.x) : 0)
    dy = Int(vl.y) + (canvas isa GraphicsCanvas ? Int(canvas.y) : 0)
    left = read_child_leave(cim, event, dx, dy)
    join_move_answers(_reroot_vertex_answer(left, old, cim.input), new_answer)
end

# The answer of `content`, the content of vertex `i`, in the graph's own space. A
# path gets the typed steps to the content, because it points to a place inside a
# node and only the graph holds the place of that node. A widget that holds its
# parts answers a path without types, which gets them from the content. An
# operation that carries its own subject travels, and any other operation is
# dropped: an operation that no reader can place is worse than no answer.
_reroot_vertex_answer(::Nothing, i::Int, content) = nothing
_reroot_vertex_answer(op::CompoundOperation, i::Int, content) =
    join_move_answers((_reroot_vertex_answer(member, i, content) for member in op.operations)...)
function _reroot_vertex_answer(op, i::Int, content)
    op isa ReplacePathOperation || return is_self_contained_operation(op) ? op : nothing
    path = get_operation_path(op)
    is_fully_typed_reference(path) ||
        (path = annotate_reference_types(content, strip_reference_types(path)))
    make_path_operation(op, @reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex::GraphVertex.content.^(path))
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

function _route_click(iomap::GraphLayoutToGraphicsCanvasIoMap, g::MouseClick)
    hit = _find_vertex_at(iomap, g.x, g.y)
    hit === nothing && return nothing
    (i, cim, x, y) = hit
    cim === nothing && return nothing
    local_evt = MouseClick(g.button, x, y, g.count, g.modifiers; time = g.time)
    op = read_intent(cim.projection, cim, local_evt)
    op isa ReplacePathOperation ||
        return op !== nothing && is_self_contained_operation(op) ? op : nothing
    _reroot_vertex_answer(op, i, cim.input)
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

# Dispatch a coordless event to every node's content reader; the active node (the
# one whose content carries the cursor) answers. Mirrors TableToGraphics.
function _forward_to_selected(iomap::GraphLayoutToGraphicsCanvasIoMap, event)
    entries = iomap.child_iomaps
    for i in 1:length(entries)
        entry = entries[i]
        (entry === nothing || entry[3] === nothing) && continue
        cim = entry[3]
        op = read_intent(cim.projection, cim, event)
        if op isa ReplacePathOperation
            return make_path_operation(op, @reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex::GraphVertex.content.^(get_operation_path(op)))
        elseif op !== nothing && is_self_contained_operation(op)
            return op
        end
    end
    nothing
end

"""
    GraphToGraphics(engine = GridEmbedding(); extent = nothing, border = 0,
                    constraints = nothing, theme = nothing) -> ChainingProjection

The pipeline from a `GraphGraph` straight to a `GraphicsCanvas`, with no
`TextToGraphics` step, like `TableToGraphics`: the chain of
`GraphGraphToGraphLayout(engine; extent, border, constraints)` and
`GraphLayoutToGraphicsCanvas(; theme)`. The stages have no recursion of their own, so
the content of a vertex prints through the recursion that encloses the chain,
for example a `NestingProjection`.
"""
# @optional: the layout engine stands first, as the algorithm the pipeline runs;
# the rest is its chrome.
GraphToGraphics(engine::GraphLayoutEngine = GridEmbedding();
                extent = nothing, border::Integer = 0, constraints = nothing,
                theme = nothing) =
    ChainingProjection(GraphGraphToGraphLayout(engine; extent = extent, border = border,
                                               constraints = constraints),
                       GraphLayoutToGraphicsCanvas(; theme))

# ── Natural-projection registration ─────────────────────────────────────────
# A graph is a diagram, not a syntax tree: it goes through its own two stages
# (size and place, then draw). No `NestingProjection` — the stages take the
# natural renderer as their recursion, so a vertex's content is whatever it is,
# rendered the same way it would be anywhere else. That is what lets a diagram
# node be a widget, or prose, or a table.

function __init__()
    register_natural_graphics!(:graph, (; measure, appearance) -> Pair{Type,Any}[
        GraphGraph => ChainingProjection(GraphGraphToGraphLayout(),
                                         GraphLayoutToGraphicsCanvas(
                                             theme = get_scaled_theme!(appearance, GraphTheme))),
    ])
end
