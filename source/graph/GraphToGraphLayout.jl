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
    GraphGraphToGraphLayout(engine = GridEmbedding(); extent = nothing, border = 0,
                            constraints = nothing)

Size the vertices, place them, and build the `GraphLayout`.

`extent` is the box the view has room for, as `(width, height)`, and `border` is
the inset kept inside it. They live on the projection rather than on the engine,
because a projection is what a view builds: the same graph in two panes is two
projections and two extents. Naming no extent asks for an unbounded placement.

`constraints` is `nothing`, or a function of the graph that answers a
`Vector{GraphConstraint}`. It is a function because a constraint names a vertex,
and the vertices are known only once there is a document. It is read inside the
layout cell, so a constraint derived from a reactive field re-runs the layout
when that field changes.
"""
struct GraphGraphToGraphLayout <: Projection
    engine::GraphLayoutEngine
    extent::Union{Nothing,Tuple{Int,Int}}
    border::Int
    constraints::Any
end

GraphGraphToGraphLayout(engine::GraphLayoutEngine = GridEmbedding();
                        extent = nothing, border::Integer = 0, constraints = nothing) =
    GraphGraphToGraphLayout(engine,
                            extent === nothing ? nothing :
                                (Int(extent[1]), Int(extent[2])),
                            Int(border), constraints)

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
                push!(ims, print_child(recursion, content, make_child_context(ctx, graph, (@reference_step vertices), (@reference_step [i]), (@reference_step content))))
            else
                push!(ims, nothing)
            end
        end
        ims
    end)

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
        constraints = p.constraints === nothing ? GraphConstraint[] : p.constraints(graph)
        positions, routes = layout_graph(p.engine, graph, sizes, constraints;
                                         extent = p.extent, border = p.border)
        # Which engine really ran is decided inside this cell, because an engine
        # that defers its choice reads the vertex count to make it.
        name = layout_engine_name(resolve_layout_engine(p.engine, length(sizes)))
        (positions, routes, name)
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
        Cell(@computation let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, graph.selection)
        end))

    iomap = GraphGraphToGraphLayoutIoMap(p, graph, layout, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

# vertices[i].rest... ↔ vertex_layouts[i].vertex.rest...
# The content sub-tree rides unchanged under `.vertex`, so no per-child iomap
# delegation is needed here.
function map_reference_forward(::GraphGraphToGraphLayout, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::GraphLayout
        ::GraphGraph.vertices[i].rest... => (@reference ::GraphLayout.vertex_layouts::CellVector[i]::VertexLayout.vertex.^(rest))
        __ => nothing
    end
end

function map_reference_backward(::GraphGraphToGraphLayout, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::GraphGraph
        ::GraphLayout.vertex_layouts[i].vertex.rest... => (@reference ::GraphGraph.vertices::CellVector[i].^(rest))
        __ => nothing
    end
end

"""
    GraphToGraphLayout(; engine=GridEmbedding(), extent=nothing, border=0,
                       constraints=nothing)

Convenience: the type-dispatching graph→layout projection. Defaults to the pure-
Julia `GridEmbedding`; pass an `AdaptagramsLayout` (when available) to
swap the native engine in behind the same interface.
"""
function GraphToGraphLayout(; engine::GraphLayoutEngine=GridEmbedding(),
                            extent = nothing, border::Integer = 0,
                            constraints = nothing)
    GraphGraphToGraphLayout(engine; extent = extent, border = border,
                            constraints = constraints)
end
