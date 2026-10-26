# Fragment of `GraphModule`.
#
# Graph → GraphLayout projection. The chicken-and-egg step: **sizing precedes
# placement.**
#
# For each `GraphVertex` the projection recurses its `content` through `recursion`
# to a `GraphicsCanvas` and reads its `w`/`h` cells — the vertex's intrinsic size
# (reactive: a size change invalidates the layout). It collects constraints, runs
# the `GraphLayoutEngine` (memoized on topology + sizes + constraints), and builds a
# `GraphLayout` whose `VertexLayout`/`EdgeLayout` cells hold the engine's positions
# and routes.
#
# A `VertexLayout.vertex` field carries the **original `GraphVertex`** (by
# identity), so the downstream `GraphLayoutToGraphicsCanvas` projection recurses the same
# content again to draw it, and selection round-trips: `vertices[i]` ↔
# `vertex_layouts[i].vertex` (tutorial School A — peel the one step this projection
# owns and delegate the tail through the same field unchanged).
# IoMap carrying the per-vertex content iomaps (used only for sizing — the
# content is *not* re-rooted into the output here; the original vertex rides in
# `VertexLayout.vertex`). Shaped like ChildrenIoMap for the mappers.
@iomap struct GraphGraphToGraphLayoutIoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
end

"""
    GraphGraphToGraphLayout(engine = make_deferred_layout_engine(); extent = nothing,
                            border = 0, constraints = nothing)

Size the vertices, place them, and build the `GraphLayout`.

The default engine is the one that defers its choice to the time of the layout:
`FruchtermanReingoldLayout`, or an engine that a package registered.

`extent` is the box the view has room for, as `(width, height)`, and `border` is
the inset kept inside it. They live on the projection rather than on the engine,
because a projection is what a view builds: the same graph in two panes is two
projections and two extents. Naming no extent asks for an unbounded placement.

`constraints` is `nothing`, or a function of the graph that answers a
`Vector{GraphConstraint}`. It is a function because a constraint names a vertex,
and the vertices are known only once there is a document. It is read inside the
layout cell, so a constraint derived from a reactive field re-runs the layout
when that field changes. The engine gets these constraints first and
`graph.constraints` after them, so a pin of the graph wins over a pin of the
projection.
"""
struct GraphGraphToGraphLayout <: Projection
    engine::GraphLayoutEngine
    extent::Union{Nothing,Tuple{Int,Int}}
    border::Int
    constraints::Any
end

# @optional: the layout engine stands first, as the algorithm the pipeline runs;
# the rest is its chrome.
GraphGraphToGraphLayout(engine::GraphLayoutEngine = make_deferred_layout_engine();
                        extent = nothing, border::Integer = 0, constraints = nothing) =
    GraphGraphToGraphLayout(engine,
                            extent === nothing ? nothing :
                                (Int(extent[1]), Int(extent[2])),
                            Int(border), constraints)

# The context of a part of a graph that the graph prints through its recursion:
# the content of a vertex or the label of an edge. It offers no room on either
# axis, so the part takes the size that it needs. A part that fills the room it
# gets, such as a table, would otherwise take all the room that the host offers
# the graph, and push the other vertices out of the view.
_make_graph_part_context(ctx, document, steps...) =
    with_exact_size(make_child_context(ctx, document, steps...); width = nothing, height = nothing)

# The vertices, by `objectid`, that a `:pin` or a `:start` of `constraints` places.
_collect_placed_vertices(constraints::Vector) =
    Set{UInt}(objectid(constraint.target) for constraint in constraints
              if constraint.kind === :pin || constraint.kind === :start)

# A `:start` at its last corner for each vertex of `graph` in `corners`, when
# `engine` takes a start. A vertex in `placed` has a place already, and gets none.
function _make_kept_starts(engine::GraphLayoutEngine, graph::GraphGraph, corners::IdDict,
                           placed::Set{UInt})
    (isempty(corners) || !(:start in get_supported_constraint_kinds(engine))) &&
        return GraphConstraint[]
    GraphConstraint[GraphConstraint(vertex, :start, corners[vertex])
                    for vertex in layout_vertices(graph)
                    if haskey(corners, vertex) && !(objectid(vertex) in placed)]
end

# The corner of each vertex of `graph` that the engine placed by itself: a vertex
# in `placed` is left out.
function _collect_vertex_corners(graph::GraphGraph, positions::Dict, placed::Set{UInt})
    corners = IdDict{Any,Tuple{Int,Int}}()
    for vertex in layout_vertices(graph)
        objectid(vertex) in placed && continue
        position = get(positions, objectid(vertex), nothing)
        position === nothing || (corners[vertex] = (position[1], position[2]))
    end
    corners
end

_canvas_wh(im) = begin
    o = im === nothing ? nothing : im.output
    o isa GraphicsCanvas ? (Int(o.w), Int(o.h)) : (60, 30)
end

function print_document(p::GraphGraphToGraphLayout, recursion, graph::GraphGraph, ctx)
    iomap_cell = Cell(nothing)

    # Recurse each vertex's content to measure its intrinsic size. Reactive: a
    # content edit that changes w/h re-runs the layout cell below.
    child_iomaps = Cell(@computation begin
        n = length(graph.vertices)
        ims = Any[]
        for i in 1:n
            v = graph.vertices[i]
            content = v isa GraphVertex ? getfield(v, :content)[] : nothing
            if content !== nothing
                push!(ims, print_child(recursion, content, _make_graph_part_context(ctx, graph, (@reference_step vertices), (@reference_step [i]), (@reference_step content))))
            else
                push!(ims, nothing)
            end
        end
        ims
    end)

    # The corner of each vertex that the last run of the engine placed by itself.
    # The next run starts each of them there, so a change of a size moves only the
    # boxes that overlap after it, and a new vertex is placed among the others. A
    # vertex that a constraint placed keeps no corner, so the undo of a drop puts
    # it back where the engine places it. A new print starts with no corner, and
    # lays out the graph from the start.
    last_corners = Ref(IdDict{Any,Tuple{Int,Int}}())

    # Run the engine (keyed on the live sizes + topology + constraints). Held in
    # one cell so it re-runs only when a size, the vertex/edge list or a
    # constraint changes.
    placed = Cell(@computation begin
        ims = child_iomaps[]
        n = length(graph.vertices)
        sizes = Dict{UInt,Tuple{Int,Int}}()
        for i in 1:n
            v = graph.vertices[i]
            v isa GraphVertex || continue
            sizes[objectid(v)] = _canvas_wh(i <= length(ims) ? ims[i] : nothing)
        end
        # Which engine really runs is decided inside this cell, because an engine
        # that defers its choice reads the vertex count to make it.
        engine = resolve_layout_engine(p.engine, length(sizes))
        # The graph's own constraints come last, so a pin that the person dropped
        # wins over a pin of the projection, and both win over the last corners.
        given = vcat(p.constraints === nothing ? GraphConstraint[] : p.constraints(graph),
                     graph.constraints)
        placed_by_given = _collect_placed_vertices(given)
        constraints = vcat(_make_kept_starts(engine, graph, last_corners[], placed_by_given), given)
        positions, routes = layout_graph(engine, graph, sizes, constraints;
                                         extent = p.extent, border = p.border)
        last_corners[] = _collect_vertex_corners(graph, positions, placed_by_given)
        (positions, routes, layout_engine_name(engine))
    end)

    vertex_layouts = CellVector(@computation begin
        positions, _, _ = placed[]
        n = length(graph.vertices)
        out = Any[]
        for i in 1:n
            v = graph.vertices[i]
            v isa GraphVertex || continue
            x, y, w, h = get(positions, objectid(v), (0, 0, 60, 30))
            push!(out, VertexLayout(v, x, y, w, h))
        end
        out
    end)

    edge_layouts = CellVector(@computation begin
        _, routes, _ = placed[]
        n = length(graph.edges)
        out = Any[]
        for i in 1:n
            e = graph.edges[i]
            e isa GraphEdge || continue
            route = get(routes, objectid(e), Tuple{Int,Int}[])
            push!(out, EdgeLayout(e, route))
        end
        out
    end)

    # The highlights pass through as derived cells. They are read by the
    # renderer only, so changing one repaints without disturbing `child_iomaps`
    # or `placed` — the expensive engine run stays cached across a highlight
    # change, which is what makes a live current-state marker affordable.
    layout = GraphLayout(vertex_layouts, edge_layouts, Cell(:tb), Cell(40), Cell(60),
        Cell(@computation graph.highlight_vertex),
        Cell(@computation graph.highlight_edge),
        Cell(@computation placed[][3]),
        Cell(graph), Cell(nothing), Cell(nothing), Cell(nothing),
        Cell(@computation let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, graph.selection)
        end),
        Cell(@computation map_mouse_target_forward(graph, path -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, path)
        end)))

    iomap = GraphGraphToGraphLayoutIoMap(p, graph, layout, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

# vertices[i].rest... ↔ vertex_layouts[i].vertex.rest..., and the same for an edge:
# edges[i].rest... ↔ edge_layouts[i].edge.rest...
# The content sub-tree rides unchanged under `.vertex`, so no per-child iomap
# delegation is needed here.
function map_reference_forward(::GraphGraphToGraphLayout, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::GraphLayout
        ::GraphGraph.vertices[i].rest... => (@reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex.^(rest))
        ::GraphGraph.edges[i].rest... => (@reference ::GraphLayout.edge_layouts::CellVector[i]::EdgeLayout.edge.^(rest))
        __ => nothing
    end
end

function map_reference_backward(::GraphGraphToGraphLayout, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::GraphGraph
        ::GraphLayout.vertex_layouts[i].vertex.rest... => (@reference ::GraphGraph.vertices::CellVector[i].^(rest))
        ::GraphLayout.edge_layouts[i].edge.rest... => (@reference ::GraphGraph.edges::CellVector[i].^(rest))
        __ => nothing
    end
end

"""
    GraphToGraphLayout(; engine=make_deferred_layout_engine(), extent=nothing,
                       border=0, constraints=nothing)

Convenience: the type-dispatching graph→layout projection. The default engine
defers its choice to the time of the layout; pass `GridEmbedding()` for a grid,
or an `AdaptagramsLayout` (when available) for the native engine.
"""
function GraphToGraphLayout(; engine::GraphLayoutEngine=make_deferred_layout_engine(),
                            extent = nothing, border::Integer = 0,
                            constraints = nothing)
    GraphGraphToGraphLayout(engine; extent = extent, border = border,
                            constraints = constraints)
end
