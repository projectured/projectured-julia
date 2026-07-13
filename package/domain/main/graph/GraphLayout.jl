"""
    GraphLayoutModule

Geometry layer for the graph domain: `VertexLayout` places a `GraphVertex`;
`EdgeLayout` routes a `GraphEdge`; `GraphLayout` bundles them with
direction/spacing knobs. `GraphConstraint` is the policy wrapper (mirrors
`LayoutConstraint`).
"""
module GraphLayoutModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export GraphLayoutDocument

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
"""
@document struct GraphLayout <: GraphLayoutDocument
    vertex_layouts::CellVector = CellVector()
    edge_layouts::CellVector = CellVector()
    direction::Symbol = :tb
    node_sep::Int = 40
    rank_sep::Int = 60
end

"""
Per-vertex/edge policy wrapper. `kind` is one of `:pin`, `:same_rank`,
`:align`, `:fixed_size`, `:min_separation`, `:cluster` (v1 ships `:pin` +
`:fixed_size`); `payload` carries kind-specific data.
"""
@document struct GraphConstraint <: GraphLayoutDocument
    target::Document
    kind::Symbol = :pin
    payload::Any = nothing
end

end # module
