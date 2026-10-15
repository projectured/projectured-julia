# Fragment of `GraphModule` — the graph document types: the abstract
# `GraphDocument`, its insertion cursor, and the vertex and edge nodes a graph
# holds.

abstract type GraphDocument <: Document end

"""
A placeholder for graph content being entered (the insert-by-typing cursor).
"""
@document struct GraphInsertion <: GraphDocument
    value::Any = nothing
end

"""
A vertex whose `content` is an arbitrary `Document`. Identity = the object
itself, so an edge can point at it (same identity model as `TableCell.content`).

Use it to draw one node of a graph: a box that shows its content, such as a name.

# Example

    vertex_1 = GraphVertex(PrimitiveString("Paris"))
    vertex_2 = GraphVertex(PrimitiveString("Lyon"))
    open_pane!(GraphGraph([vertex_1, vertex_2], [GraphEdge(vertex_1, vertex_2)]); title = "Roads")

See also `GraphGraph`, which holds it, and `GraphEdge`.
"""
@document struct GraphVertex <: GraphDocument
    content::Any          # required: keeps the 1-arg `GraphVertex(content)` ctor
                          # (macro Rule Y needs req≥1; all-defaulted would drop it)
end

"""
An edge from `source` to `target` (both `GraphVertex`, held by identity).
`directed` draws an end arrowhead; `label` is an optional content document.

Use it to draw a link between two nodes of a graph, with an arrow or a label.

# Example

    vertex_1 = GraphVertex(PrimitiveString("Paris"))
    vertex_2 = GraphVertex(PrimitiveString("Lyon"))
    edge_1 = GraphEdge(vertex_1, vertex_2; directed = false)
    open_pane!(GraphGraph([vertex_1, vertex_2], [edge_1]); title = "Roads")

See also `GraphGraph`, which holds it, and `GraphVertex`.
"""
@document struct GraphEdge <: GraphDocument
    source::Document
    target::Document
    directed::Bool = true
    label::Any = nothing
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

`highlight_vertex` / `highlight_edge` name one vertex and one edge to draw
emphasized — a ring around the node, a thickened stroke on the edge. They are
**presentation state, not content**: a producer wires them as derived cells over
whatever it is tracking (a running state machine's current state, a search hit),
and they flow through `GraphLayout` to the renderer without touching a vertex's
`content` — which is what keeps a highlight change from invalidating the
measured sizes and re-running the whole layout. Both hold the referent by
identity, like an edge's endpoints; a `VertexLayout` is rebuilt on every layout
recompute and must never be held here.

`constraints` is a `Vector` of `GraphConstraint` that the graph gives every
layout of it: the places that the person gave its vertices. A drop of a dragged
vertex writes a `:pin` for that vertex and a `:start` for each other vertex at
the place where it is drawn, so the next layout begins from what the person saw.
Each write replaces the whole vector, which makes a drop one edit. A layout
gives the engine these constraints after the ones of its projection, so a pin
here wins over a pin of the projection.

Use it to draw nodes and the links between them: a map, a network or a state machine.

# Example

    vertex_1 = GraphVertex(PrimitiveString("Paris"))
    vertex_2 = GraphVertex(PrimitiveString("Lyon"))
    open_pane!(GraphGraph([vertex_1, vertex_2], [GraphEdge(vertex_1, vertex_2)]); title = "Roads")

See also `GraphVertex` and `GraphEdge`.
"""
@document struct GraphGraph <: GraphDocument
    vertices::CellVector = CellVector()
    edges::CellVector = CellVector()
    highlight_vertex::Any = nothing
    highlight_edge::Any = nothing
    constraints::Any = GraphConstraint[]
end

# Two-CellVector convenience: Rule C only covers a single CellVector, so this
# Vector→CellVector form is not macro-generated.
function GraphGraph(vertices::Vector, edges::Vector)
    GraphGraph(CellVector(Cell[v isa Cell ? v : Cell(v) for v in vertices]),
               CellVector(Cell[e isa Cell ? e : Cell(e) for e in edges]),
               Cell(nothing), Cell(nothing), Cell(GraphConstraint[]), Cell(nothing))
end
