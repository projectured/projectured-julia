# Fragment of `GraphModule`.
#
# Geometry layer for the graph domain: `VertexLayout` places a `GraphVertex`;
# `EdgeLayout` routes a `GraphEdge`; `GraphLayout` bundles them with
# direction/spacing knobs. `GraphConstraint` is the policy wrapper (mirrors
# `LayoutConstraint`).
abstract type GraphLayoutDocument <: Document end

# ── VertexLayout ─────────────────────────────────────────────────────────────

"""
The placed rect `(x, y, w, h)` for `vertex` (a `GraphVertex`, held by identity).
`pinned` freezes the position (engine won't move it).
"""
@document struct VertexLayout <: GraphLayoutDocument
    vertex::Document
    x::Int
    y::Int
    w::Int
    h::Int
    pinned::Bool = false
end

# ── EdgeLayout ───────────────────────────────────────────────────────────────

"""
Routed waypoints for `edge` (a `GraphEdge`, held by identity). `route` is a
`Vector{Tuple{Int,Int}}`; `source_port`/`target_port` are anchor hints.
"""
@document struct EdgeLayout <: GraphLayoutDocument
    edge::Document
    route::Any = Tuple{Int,Int}[]
    source_port::Symbol = :auto
    target_port::Symbol = :auto
end

"""
The placed layout for a graph: `VertexLayout`/`EdgeLayout` collections + the
direction/spacing knobs fed to the engine.

`highlight_vertex` / `highlight_edge` carry the graph's emphasis through to the
renderer, by identity (a `GraphVertex` / `GraphEdge` — never a layout, which is
rebuilt on every recompute). They are derived cells over the graph's own fields,
so changing a highlight repaints without re-running the layout engine.

`engine` names the algorithm that placed this layout — `:grid`,
`:fruchterman_reingold`, or the name of an engine that a package registered,
such as `:adaptagrams`. A caller that asks for
the engine that defers its choice does not otherwise learn which one ran, and
without that a view cannot say what a reader is looking at and a test cannot
assert that the choice went the way it should have.

`graph` is the `GraphGraph` that this layout places, held by identity. A drop of
a vertex writes its pin and the start positions into `graph.constraints`.

`drag` is the drag of a vertex while the button is down, as view state: a
`NamedTuple` `(vertex, index, origin, offset, started)`, or `nothing`. `vertex`
is the `GraphVertex` and `index` its place in `vertex_layouts`; `origin` is the
point of the press and `offset` how far the pointer moved from it; `started` is
false until the pointer moved far enough to start the drag. Only the drawing
reads it, so a move of the pointer repaints and does not run the engine.

`zoom` is the zoom of the layout, as view state: `nothing` for no zoom, or a
`NamedTuple` `(scale, shift)`. The drawing draws the centre `c` of each box at
`scale .* c .+ shift`, and the box keeps its size and its content. Only the
drawing reads it, so a zoom repaints and does not run the engine.
"""
@document struct GraphLayout <: GraphLayoutDocument
    vertex_layouts::CellVector = CellVector()
    edge_layouts::CellVector = CellVector()
    direction::Symbol = :tb
    node_sep::Int = 40
    rank_sep::Int = 60
    highlight_vertex::Any = nothing
    highlight_edge::Any = nothing
    engine::Symbol = :unknown
    graph::Any = nothing
    drag::Any = nothing
    zoom::Any = nothing
end

"""
Per-vertex/edge policy wrapper. `kind` is one of `GRAPH_CONSTRAINT_KINDS`, and
`payload` carries kind-specific data: a corner `(x, y)` for `:pin` and
`:start`. An engine lists the kinds it implements in
`get_supported_constraint_kinds`.
"""
@document struct GraphConstraint <: GraphLayoutDocument
    target::Document
    kind::Symbol = :pin
    payload::Any = nothing
end
