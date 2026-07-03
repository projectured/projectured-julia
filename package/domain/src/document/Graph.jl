"""
    GraphModule

The graph document domain: vertices and edges, where a vertex's `content` is an
arbitrary `Document` (a table, an XML tree, JSON, even another graph) and an edge
connects two vertices held by identity.

The domain mirrors the `Table` semantic layer: it carries *no geometry* of its
own. A separate `GraphLayout` document (see `GraphLayout.jl`) holds positions,
sizes, and edge routes, produced by a `GraphLayoutEngine`. This file defines only
the semantic structure.

Types:
- `GraphInsertion` — the domain's type-in entry point.
- `GraphVertex`    — `content::Document` (any domain) + identity (the object itself).
- `GraphEdge`      — `source`/`target` `GraphVertex` (by identity), `directed`, `label`.
- `GraphGraph`     — `vertices` + `edges` + selection.

Field names (`content`, `source`, `target`, `vertices`, `edges`) are the public
reference vocabulary per the `Document` contract.
"""
module GraphModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export GraphDocument, GraphInsertion, GraphVertex, GraphEdge, GraphGraph,
       IGraphInsertion, IGraphVertex, IGraphEdge, IGraphGraph

# ── Abstract base ───────────────────────────────────────────────────────────

abstract type GraphDocument <: Document end

# ── GraphInsertion ──────────────────────────────────────────────────────────
#
# The domain's type-in entry point — the placeholder a user replaces by typing.

@document struct GraphInsertion <: GraphDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── GraphVertex ─────────────────────────────────────────────────────────────

"""
    GraphVertex(content)

A graph vertex whose `content` is an arbitrary `Document` (table/xml/json/…),
rendered via the shared recursion exactly like `TableCell.content`. Identity is
the document object itself (its `Cell` reference), so an edge can point at it —
the same identity model as the formula reference and `AnchoredEntry.target_document`.
"""
@document struct GraphVertex <: GraphDocument
    content::Document
    selection::Reference
end

GraphVertex() = GraphVertex(Cell(nothing), Cell(nothing))
GraphVertex(content::Document) = GraphVertex(Cell(content), Cell(nothing))

# ── GraphEdge ───────────────────────────────────────────────────────────────

"""
    GraphEdge(source, target; directed=true, label=nothing)

An edge connecting the `source` `GraphVertex` to the `target` `GraphVertex`,
both held by identity. `directed` draws an end arrowhead; `label` is an optional
small content document (or `nothing`).
"""
@document struct GraphEdge <: GraphDocument
    source::Document
    target::Document
    directed::Bool
    label::Any
    selection::Reference
end

function GraphEdge(source::GraphVertex, target::GraphVertex;
                   directed::Bool=true, label=nothing)
    GraphEdge(Cell(source), Cell(target), Cell(directed), Cell(label), Cell(nothing))
end

# ── GraphGraph ──────────────────────────────────────────────────────────────

"""
    GraphGraph(vertices, edges)

A graph: a `CellVector` of `GraphVertex` and a `CellVector` of `GraphEdge`.
Because `GraphGraph` is a `Document` and a vertex's `content` is arbitrary, a
vertex may itself hold a `GraphGraph` (nested graphs) for free via type dispatch.
"""
@document struct GraphGraph <: GraphDocument
    vertices::CellVector = CellVector()
    edges::CellVector = CellVector()
    selection::Reference = nothing
end

function GraphGraph(vertices::Vector, edges::Vector)
    GraphGraph(CellVector(Cell[v isa Cell ? v : Cell(v) for v in vertices]),
               CellVector(Cell[e isa Cell ? e : Cell(e) for e in edges]),
               Cell(nothing))
end

end # module
