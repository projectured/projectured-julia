"""
    GraphLayoutModule

The geometry layer for the graph domain, mirroring `Layout.jl` /
`LayoutConstraint`. A `GraphLayout` is a real, persistent intermediate document
(not a transient): it holds the placed positions/sizes of vertices and the routed
edge waypoints produced by a `GraphLayoutEngine`. Persisting geometry makes it
inspectable and testable, lets later manual edits survive, and keeps the engine
call out of frequently-rerun reactive thunks.

Types:
- `VertexLayout` — the placed rect `(x, y, w, h)` for a `GraphVertex` (by identity),
  with a `pinned` flag (engine treats the position as fixed when true).
- `EdgeLayout`   — the `route` (waypoints) for a `GraphEdge` (by identity), with
  `source_port`/`target_port` anchor hints.
- `GraphLayout`  — `vertex_layouts` + `edge_layouts` + direction/spacing knobs.
- `GraphConstraint` — a per-vertex/edge policy wrapper, analogous to
  `LayoutConstraint`.
"""
module GraphLayoutModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export GraphLayoutDocument, VertexLayout, EdgeLayout, GraphLayout, GraphConstraint,
       IVertexLayout, IEdgeLayout, IGraphLayout, IGraphConstraint

abstract type GraphLayoutDocument <: Document end

# ── VertexLayout ─────────────────────────────────────────────────────────────

"""
    VertexLayout(vertex, x, y, w, h; pinned=false)

The placed rectangle for `vertex` (a `GraphVertex`, held by identity). `w`/`h`
are seeded from the vertex's projected size. `pinned` foundations later
drag-to-move: when true the engine treats the position as fixed (always
engine-driven in v1).
"""
@document struct VertexLayout <: GraphLayoutDocument
    vertex::Document
    x::Int
    y::Int
    w::Int
    h::Int
    pinned::Bool
    selection::Reference
end

function VertexLayout(vertex::Document, x::Integer, y::Integer, w::Integer, h::Integer;
                      pinned::Bool=false)
    VertexLayout(Cell(vertex), Cell(Int(x)), Cell(Int(y)), Cell(Int(w)), Cell(Int(h)),
                 Cell(pinned), Cell(nothing))
end

# ── EdgeLayout ───────────────────────────────────────────────────────────────

"""
    EdgeLayout(edge, route; source_port=:auto, target_port=:auto)

The routed waypoints for `edge` (a `GraphEdge`, held by identity). `route` is a
`Vector{Tuple{Int,Int}}` of polyline waypoints (or spline control points).
`source_port`/`target_port` are anchor-side hints (`:auto`, `:top`, …).
"""
@document struct EdgeLayout <: GraphLayoutDocument
    edge::Document
    route::Any                 # Vector{Tuple{Int,Int}}
    source_port::Symbol
    target_port::Symbol
    selection::Reference
end

function EdgeLayout(edge::Document, route::AbstractVector;
                    source_port::Symbol=:auto, target_port::Symbol=:auto)
    pts = Tuple{Int,Int}[(Int(p[1]), Int(p[2])) for p in route]
    EdgeLayout(Cell(edge), Cell(pts), Cell(source_port), Cell(target_port), Cell(nothing))
end

# ── GraphLayout ──────────────────────────────────────────────────────────────

"""
    GraphLayout(vertex_layouts, edge_layouts; direction=:tb, node_sep=40, rank_sep=60)

The placed layout for a graph: the `VertexLayout`/`EdgeLayout` cells plus the
direction/spacing knobs fed to the engine. `direction` is a rank-direction hint
(`:tb`, `:lr`, `:none`).
"""
@document struct GraphLayout <: GraphLayoutDocument
    vertex_layouts::CellVector = CellVector()
    edge_layouts::CellVector = CellVector()
    direction::Symbol = :tb
    node_sep::Int = 40
    rank_sep::Int = 60
    selection::Reference = nothing
end

function GraphLayout(vertex_layouts, edge_layouts;
                     direction::Symbol=:tb, node_sep::Integer=40, rank_sep::Integer=60)
    vl = vertex_layouts isa CellVector ? vertex_layouts :
         CellVector(Cell[v isa Cell ? v : Cell(v) for v in vertex_layouts])
    el = edge_layouts isa CellVector ? edge_layouts :
         CellVector(Cell[e isa Cell ? e : Cell(e) for e in edge_layouts])
    GraphLayout(vl, el, Cell(direction), Cell(Int(node_sep)), Cell(Int(rank_sep)), Cell(nothing))
end

# ── GraphConstraint ──────────────────────────────────────────────────────────

"""
    GraphConstraint(target; kind=:pin, payload=nothing)

A per-vertex/edge policy wrapper, analogous to `LayoutConstraint`. `kind` is one
of `:pin`, `:same_rank`, `:align`, `:fixed_size`, `:min_separation`, `:cluster`;
`payload` carries kind-specific data. Constraint readers translate these into
engine constraint objects. v1 ships `:pin` + `:fixed_size`; the rest are
scaffolding for later phases.
"""
@document struct GraphConstraint <: GraphLayoutDocument
    target::Document
    kind::Symbol
    payload::Any
    selection::Reference
end

function GraphConstraint(target::Document; kind::Symbol=:pin, payload=nothing)
    GraphConstraint(Cell(target), Cell(kind), Cell(payload), Cell(nothing))
end

end # module
