"""
    GraphToGraphLayoutModule

Graph → GraphLayout projection. The chicken-and-egg step: **sizing precedes
placement.**

For each `GraphVertex` the projection recurses its `content` through `recursion`
to a `GraphicsCanvas` and reads its `w`/`h` cells — the vertex's intrinsic size
(reactive: a size change invalidates the layout). It collects constraints, runs
the `GraphLayoutEngine` (memoized on topology + sizes + constraints), and builds a
`GraphLayout` whose `VertexLayout`/`EdgeLayout` cells hold the engine's positions
and routes.

A `VertexLayout.vertex` field carries the **original `GraphVertex`** (by
identity), so the downstream `GraphLayoutToGraphics` projection recurses the same
content again to draw it, and selection round-trips: `vertices[i]` ↔
`vertex_layouts[i].vertex` (tutorial School A — peel the one step this projection
owns and delegate the tail through the same field unchanged).
"""
module GraphToGraphLayoutModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..GraphModule: GraphGraph, GraphVertex, GraphEdge
import ..GraphLayoutModule: GraphLayout, VertexLayout, EdgeLayout, GraphConstraint
import ..GraphLayoutEngineModule: GraphLayoutEngine, FallbackLayoutEngine, layout_graph
import ..GraphicsModule: GraphicsCanvas
import ..IoMapModule: ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          EmptyReference
import ..ReferenceBuilderModule: var"@reference", var"@reference_step"
import ..ReferenceCaseModule: var"@reference_case"
import ..PrinterContextModule: make_child_context

export GraphGraphToGraphLayout, GraphToGraphLayout, GraphGraphToGraphLayoutIoMap

# IoMap carrying the per-vertex content iomaps (used only for sizing — the
# content is *not* re-rooted into the output here; the original vertex rides in
# `VertexLayout.vertex`). Shaped like ChildrenIoMap for the mappers.
struct GraphGraphToGraphLayoutIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
end

struct GraphGraphToGraphLayout <: Projection
    engine::GraphLayoutEngine
end

GraphGraphToGraphLayout(; engine::GraphLayoutEngine=FallbackLayoutEngine()) =
    GraphGraphToGraphLayout(engine)

_canvas_wh(im) = begin
    o = im === nothing ? nothing : im.output
    o isa GraphicsCanvas ? (Int(o.w), Int(o.h)) : (60, 30)
end

function print_document(p::GraphGraphToGraphLayout, recursion, graph::GraphGraph, ctx)
    iomap_cell = Cell(nothing)

    # Recurse each vertex's content to measure its intrinsic size. Reactive: a
    # content edit that changes w/h re-runs the layout cell below.
    child_iomaps = Cell(() -> begin
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

    # Collect constraints (v1: any GraphConstraint that wraps a vertex/edge in
    # the graph — none in the base example, so this is scaffolding).
    constraints = GraphConstraint[]

    # Run the engine (keyed on the live sizes + topology). Held in one cell so it
    # re-runs only when a size or the vertex/edge list changes.
    placed = Cell(() -> begin
        ims = child_iomaps[]
        n = length(graph.vertices)
        sizes = Dict{UInt,Tuple{Int,Int}}()
        for i in 1:n
            v = graph.vertices[i]
            v isa GraphVertex || continue
            sizes[objectid(v)] = _canvas_wh(i <= length(ims) ? ims[i] : nothing)
        end
        layout_graph(p.engine, graph, sizes, constraints)
    end)

    vertex_layouts = CellVector(() -> begin
        positions, _ = placed[]
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

    edge_layouts = CellVector(() -> begin
        _, routes = placed[]
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

    layout = GraphLayout(vertex_layouts, edge_layouts, Cell(:tb), Cell(40), Cell(60),
        Cell(() -> let im = iomap_cell[]
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
        _ => nothing
    end
end

function map_reference_backward(::GraphGraphToGraphLayout, iomap, reference)
    @reference_case reference begin
        ∅ => @reference ::GraphGraph
        ::GraphLayout.vertex_layouts[i].vertex.rest... => (@reference ::GraphGraph.vertices::CellVector[i].^(rest))
        _ => nothing
    end
end

"""
    GraphToGraphLayout(; engine=FallbackLayoutEngine())

Convenience: the type-dispatching graph→layout projection. Defaults to the pure-
Julia `FallbackLayoutEngine`; pass an `AdaptagramsEngine` (when available) to
swap the native engine in behind the same interface.
"""
function GraphToGraphLayout(; engine::GraphLayoutEngine=FallbackLayoutEngine())
    GraphGraphToGraphLayout(engine)
end

end # module
