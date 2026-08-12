"""
    HeapEmbeddingModule

A planar embedding for one connected component, from OMNeT++'s
`src/layout/heapembedding.cc`.

Vertices are placed in spanning-tree order. A list of candidate points is kept;
each vertex is tried against every candidate with each of its eight edge and
corner points, every placement that would overlap something already placed is
rejected, and the survivor nearest to the neighbours already placed wins. Then
the vertex's own four edge midpoints become new candidates.

Nothing overlaps, and a vertex ends up beside the neighbours it already has. It
is the cheaper of the two pre-embeddings and the one the layouter uses when the
component is not a tree.
"""
module HeapEmbeddingModule

import ..LayoutGeometryModule: Pt, Rs, Rc, pt_zero, pt_nil, is_nil, pt_distance,
                               rc_center, rc_center_top, rc_center_bottom,
                               rc_left_center, rc_right_center,
                               rc_base_plane_contains, rc_base_plane_intersects
import ..GraphComponentModule: GraphComponent, LayoutVertex, vertex_count

export HeapEmbedding, heap_embed!

"""
    HeapEmbedding(component, vertex_spacing)

`component` must already have a spanning tree; `vertex_spacing` is the least gap
kept between two vertices.
"""
struct HeapEmbedding
    component::GraphComponent
    vertex_spacing::Float64
end

HeapEmbedding(component::GraphComponent, vertex_spacing::Real) =
    HeapEmbedding(component, Float64(vertex_spacing))

# The eight ways a rectangle of size `rs` can be hung off one point: by each
# corner and by each edge midpoint of its top and bottom, and by its left and
# right at half height.
function _candidate_rectangle(pt::Pt, rs::Rs, k::Int)
    offset = if k == 0
        Pt(0, 0, 0)                             # the point is the top left
    elseif k == 1
        Pt(rs.width/2, 0, 0)                    # top centre
    elseif k == 2
        Pt(rs.width, 0, 0)                      # top right
    elseif k == 3
        Pt(0, rs.height/2, 0)                   # centre left
    elseif k == 4
        Pt(rs.width, rs.height/2, 0)            # centre right
    elseif k == 5
        Pt(0, rs.height, 0)                     # bottom left
    elseif k == 6
        Pt(rs.width/2, rs.height, 0)            # bottom centre
    else
        Pt(rs.width, rs.height, 0)              # bottom right
    end
    Rc(pt - offset, rs)
end

function _push_unless_covered!(points::Vector{Pt}, rectangles::Vector{Rc}, pt::Pt)
    for rectangle in rectangles
        rc_base_plane_contains(rectangle, pt; strictly = true) && return nothing
    end
    push!(points, pt)
    nothing
end

"""
    heap_embed!(embedding)

Place every vertex of the component, writing into each vertex's `rc.pt`.
"""
function heap_embed!(embedding::HeapEmbedding)
    component = embedding.component
    spacing = embedding.vertex_spacing
    rectangles = Rc[]                   # what has been placed
    points = Pt[pt_zero()]              # where something might go

    for vertex in component.vertices
        vertex.rc = Rc(pt_nil(), vertex.rc.rs)
    end

    for vertex in component.spanning_tree_vertices
        rs = vertex.rc.rs

        best_distance = Inf
        best = Rc(pt_zero(), rs)

        for pt in points, k in 0:7
            candidate = _candidate_rectangle(pt, rs, k)

            overlaps = false
            for rectangle in rectangles
                if rc_base_plane_intersects(candidate, rectangle; strictly = true)
                    overlaps = true
                    break
                end
            end
            overlaps && continue

            # How far this placement is from the neighbours already placed.
            distance = 0.0
            for neighbour in vertex.neighbours
                is_nil(neighbour.rc.pt) && continue
                distance += pt_distance(rc_center(candidate), rc_center(neighbour.rc))
            end

            if distance < best_distance
                best = candidate
                best_distance = distance
            end
        end

        vertex.rc = Rc(best.pt, vertex.rc.rs)

        # Grow the placed rectangle by the spacing, so nothing lands closer than
        # that and so the new candidate points sit clear of it.
        grown = Rc(best.pt - Pt(spacing, spacing, 0),
                   Rs(best.rs.width + 2*spacing, best.rs.height + 2*spacing))

        filter!(pt -> !rc_base_plane_contains(grown, pt; strictly = true), points)

        _push_unless_covered!(points, rectangles, rc_center_top(grown))
        _push_unless_covered!(points, rectangles, rc_center_bottom(grown))
        _push_unless_covered!(points, rectangles, rc_left_center(grown))
        _push_unless_covered!(points, rectangles, rc_right_center(grown))

        push!(rectangles, grown)
    end
    nothing
end

end # module
