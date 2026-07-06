"""
    GraphModule

The graph document domain: vertices with a content `Document` (any domain — a
table, JSON, another graph) and edges connecting vertices by identity.
`GraphLayout.jl` holds positions/routes; this file is pure semantic structure.
"""
module GraphModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export GraphDocument

abstract type GraphDocument <: Document end

"""
A placeholder for graph content being entered (the insert-by-typing cursor).
"""
@document struct GraphInsertion <: GraphDocument
    value::Any = nothing
    selection::Reference = nothing
end

"""
A vertex whose `content` is an arbitrary `Document`. Identity = the object
itself, so an edge can point at it (same identity model as `TableCell.content`).
"""
@document struct GraphVertex <: GraphDocument
    content::Any          # required: keeps the 1-arg `GraphVertex(content)` ctor
                          # (macro Rule Y needs req≥1; all-defaulted would drop it)
    selection::Reference = nothing
end

"""
An edge from `source` to `target` (both `GraphVertex`, held by identity).
`directed` draws an end arrowhead; `label` is an optional content document.
"""
@document struct GraphEdge <: GraphDocument
    source::Document
    target::Document
    directed::Bool = true
    label::Any = nothing
    selection::Reference = nothing
end

# Mixed positional+keyword form the macro can't generate (source/target are
# positional; directed/label are keywords). Typed args keep it distinct from the
# macro's Rule Y `GraphEdge(source, target)`.
function GraphEdge(source::GraphVertex, target::GraphVertex;
                   directed::Bool=true, label=nothing)
    GraphEdge(Cell(source), Cell(target), Cell(directed), Cell(label), Cell(nothing))
end

"""
A graph: `CellVector` of `GraphVertex` + `CellVector` of `GraphEdge`. Because a
vertex's `content` is arbitrary, a vertex may hold another `GraphGraph` for free.
"""
@document struct GraphGraph <: GraphDocument
    vertices::CellVector = CellVector()
    edges::CellVector = CellVector()
    selection::Reference = nothing
end

# Two-CellVector convenience: Rule C only covers a single CellVector, so this
# Vector→CellVector form is not macro-generated.
function GraphGraph(vertices::Vector, edges::Vector)
    GraphGraph(CellVector(Cell[v isa Cell ? v : Cell(v) for v in vertices]),
               CellVector(Cell[e isa Cell ? e : Cell(e) for e in edges]),
               Cell(nothing))
end

end # module
