"""
    GraphComponentModule

The graph algorithms both ported layouters read, from OMNeT++'s
`src/layout/graphcomponent.h` and `.cc`: a vertex, an edge, and the component
that owns them, with a spanning tree and a split into connected parts.

This is a working copy of the topology, not the document. A `LayoutVertex` holds
its neighbours, its placed rectangle and an `identity` the caller recognises it
by; nothing here knows what the identity means.

Two deviations from the original. It has no `owner` flag, because Julia frees
what nothing points at. And `colorize_connected_sub_component!` runs from an
explicit stack rather than by recursion, which visits the vertices in the same
order and cannot exhaust the call stack on a long chain.

The original names — `Vertex` and `Edge` — would sit beside this domain's own
`GraphVertex` and `GraphEdge` documents and read as the same thing. They are
`LayoutVertex` and `LayoutEdge` here for that reason.
"""
module GraphComponentModule

import ..LayoutGeometryModule: Pt, Rs, Rc, pt_nil, rc_left, rc_right, rc_top, rc_bottom

export LayoutVertex, LayoutEdge, GraphComponent,
       add_vertex!, add_edge!, index_of_vertex, find_vertex, get_bounding_rectangle,
       calculate_spanning_tree!, calculate_connected_sub_components!,
       get_vertex_count, get_edge_count

"""
    LayoutVertex(pt, rs, identity = nothing)

A vertex of the working graph, placed at the top-left `pt` with size `rs`.

`identity` is what the caller looks the vertex up by and no algorithm here reads
it. `color` is scratch space that the spanning tree and the component split both
use, one after the other. The `star_tree_*` fields belong to `StarTreeEmbedding`
and mean nothing until it runs.
"""
mutable struct LayoutVertex
    neighbours::Vector{LayoutVertex}
    edges::Vector{Any}
    rc::Rc
    identity::Any
    spanning_tree_parent::Union{Nothing,LayoutVertex}
    spanning_tree_children::Vector{LayoutVertex}
    connected_sub_component::Any
    color::Int
    star_tree_center::Pt
    star_tree_circle_center::Pt
    star_tree_radius::Float64
end

LayoutVertex(pt::Pt, rs::Rs, identity = nothing) =
    LayoutVertex(LayoutVertex[], Any[], Rc(pt, rs), identity, nothing, LayoutVertex[],
                 nothing, 0, pt_nil(), pt_nil(), -1.0)

"""
    LayoutEdge(source, target, identity = nothing)

An edge between two `LayoutVertex`. It is undirected as far as every algorithm
here is concerned; which end is the source only matters to the caller.
"""
mutable struct LayoutEdge
    source::LayoutVertex
    target::LayoutVertex
    identity::Any
    connected_sub_component::Any
    color::Int
end

LayoutEdge(source::LayoutVertex, target::LayoutVertex, identity = nothing) =
    LayoutEdge(source, target, identity, nothing, 0)

"""
    GraphComponent()

A graph, or one connected part of one. `connected_sub_components` holds the
parts after [`calculate_connected_sub_components!`](@ref); those parts share the
vertices and edges of the whole rather than copying them.
"""
mutable struct GraphComponent
    vertices::Vector{LayoutVertex}
    edges::Vector{LayoutEdge}
    spanning_tree_root::Union{Nothing,LayoutVertex}
    spanning_tree_vertices::Vector{LayoutVertex}
    connected_sub_components::Vector{GraphComponent}
end

GraphComponent() =
    GraphComponent(LayoutVertex[], LayoutEdge[], nothing, LayoutVertex[], GraphComponent[])

get_vertex_count(component::GraphComponent) = length(component.vertices)
get_edge_count(component::GraphComponent) = length(component.edges)
Base.isempty(component::GraphComponent) = isempty(component.vertices)

"""
    add_vertex!(component, vertex) -> Int

Append `vertex` and answer its index.
"""
function add_vertex!(component::GraphComponent, vertex::LayoutVertex)
    push!(component.vertices, vertex)
    length(component.vertices)
end

"""
    add_edge!(component, edge) -> Int

Append `edge`, and record it on both of its endpoints as an edge and as a
neighbour. Answer its index.
"""
function add_edge!(component::GraphComponent, edge::LayoutEdge)
    push!(component.edges, edge)
    push!(edge.source.edges, edge)
    push!(edge.target.edges, edge)
    push!(edge.source.neighbours, edge.target)
    push!(edge.target.neighbours, edge.source)
    length(component.edges)
end

"The index of `vertex`, or 0 when it is not in `component`."
function index_of_vertex(component::GraphComponent, vertex::LayoutVertex)
    for i in 1:length(component.vertices)
        component.vertices[i] === vertex && return i
    end
    0
end

"The vertex whose `identity` is `identity`, or `nothing`."
function find_vertex(component::GraphComponent, identity)
    for vertex in component.vertices
        vertex.identity === identity && return vertex
    end
    nothing
end

"""
    get_bounding_rectangle(component) -> Rc

The rectangle covering every vertex.

The seeds are OMNeT++'s: `DBL_MAX` and `DBL_MIN`, and `DBL_MIN` is the smallest
**positive** double rather than the most negative one. A component lying wholly
above or left of the origin therefore reports a box that reaches the origin. It
is reproduced rather than corrected, because this box seeds a pre-embedding that
is scaled and translated afterwards, and a port that "fixes" it draws a
different picture from the one it is a port of.
"""
function get_bounding_rectangle(component::GraphComponent)
    top = floatmax(Float64); bottom = floatmin(Float64)
    left = floatmax(Float64); right = floatmin(Float64)
    for vertex in component.vertices
        top = min(top, rc_top(vertex.rc))
        bottom = max(bottom, rc_bottom(vertex.rc))
        left = min(left, rc_left(vertex.rc))
        right = max(right, rc_right(vertex.rc))
    end
    Rc(left, top, 0.0, right - left, bottom - top)
end

"""
    calculate_spanning_tree!(component[, root])

Fill in `spanning_tree_root`, every vertex's `spanning_tree_parent` and
`spanning_tree_children`, and `spanning_tree_vertices` in visit order.

Without a `root`, the tree starts at the vertex with the most neighbours, which
puts the busiest vertex at the centre of whatever the pre-embedding draws. The
search is breadth-first, so `spanning_tree_vertices` is in level order.
"""
function calculate_spanning_tree!(component::GraphComponent)
    root = nothing
    empty!(component.spanning_tree_vertices)
    for vertex in component.vertices
        if root === nothing || length(root.neighbours) < length(vertex.neighbours)
            root = vertex
        end
    end
    root === nothing || calculate_spanning_tree!(component, root)
    nothing
end

function calculate_spanning_tree!(component::GraphComponent, root::LayoutVertex)
    component.spanning_tree_root = root

    for vertex in component.vertices
        empty!(vertex.spanning_tree_children)
        vertex.spanning_tree_parent = nothing
        vertex.color = 0
    end

    _add_to_spanning_tree_parent!(nothing, root)
    pending = LayoutVertex[root]
    push!(component.spanning_tree_vertices, root)

    while !isempty(pending)
        vertex = popfirst!(pending)
        for neighbour in vertex.neighbours
            neighbour.color == 0 || continue
            _add_to_spanning_tree_parent!(vertex, neighbour)
            push!(pending, neighbour)
            push!(component.spanning_tree_vertices, neighbour)
        end
    end
    nothing
end

function _add_to_spanning_tree_parent!(parent, vertex::LayoutVertex)
    vertex.color = 1
    vertex.spanning_tree_parent = parent
    parent === nothing || push!(parent.spanning_tree_children, vertex)
    nothing
end

"""
    calculate_connected_sub_components!(component)

Split `component` into its connected parts and leave them in
`connected_sub_components`, each part sharing the vertices and edges of the
whole. Every vertex also learns which part it is in, which is what lets the
force-directed layouter make repulsion between two parts die off with distance
while repulsion inside one part does not.
"""
function calculate_connected_sub_components!(component::GraphComponent)
    empty!(component.connected_sub_components)
    for vertex in component.vertices
        vertex.color = 0
    end
    for edge in component.edges
        edge.color = 0
    end

    color = 1
    for vertex in component.vertices
        vertex.color == 0 || continue
        child = GraphComponent()
        push!(component.connected_sub_components, child)
        _colorize_connected_sub_component!(child, vertex, color)
        color += 1
    end
    nothing
end

# Depth-first, from an explicit stack. Neighbours go on in reverse so the first
# neighbour comes off first: that is the order the recursive original visits in,
# and the order decides which vertex a pre-embedding puts where.
function _colorize_connected_sub_component!(child::GraphComponent,
                                            start::LayoutVertex, color::Int)
    pending = LayoutVertex[start]
    while !isempty(pending)
        vertex = pop!(pending)
        vertex.color == 0 || continue

        vertex.color = color
        vertex.connected_sub_component = child
        push!(child.vertices, vertex)

        for edge in vertex.edges
            edge.color == 0 || continue
            edge.color = color
            edge.connected_sub_component = child
            push!(child.edges, edge)
        end

        for i in length(vertex.neighbours):-1:1
            neighbour = vertex.neighbours[i]
            neighbour.color == 0 && push!(pending, neighbour)
        end
    end
    nothing
end

end # module
