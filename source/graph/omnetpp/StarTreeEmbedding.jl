"""
    StarTreeEmbeddingModule

A planar embedding for one connected component, from OMNeT++'s
`src/layout/startreeembedding.cc`.

Where `HeapEmbedding` packs rectangles, this packs **circles**. Every subtree is
wrapped in a circle; a parent sits in the middle and its subtrees are placed
around it, each new circle set against two already placed so that it touches
both and lies as near the parent as it can. When all the children are placed,
the whole is wrapped in one circle and becomes a child of its own parent.

A second pass turns each subtree in place so that its weight falls away from its
parent, which is what stops a tree from folding back over itself. A third pass
turns the relative centres into absolute positions.

Nothing overlaps, and a tree drawn this way reads as a tree. The layouter picks
it over `HeapEmbedding` whenever the component really is a tree.
"""
module StarTreeEmbeddingModule

import ..LayoutGeometryModule: Pt, Rc, Cc, pt_zero, pt_distance,
                               get_diagonal_length, area, get_base_plane_angle,
                               rotate_base_plane, cc_intersect, cc_enclosing,
                               cc_center_top, cc_center_bottom, cc_left_center,
                               cc_right_center
import ..GraphComponentModule: GraphComponent, LayoutVertex

export StarTreeEmbedding, embed_star_tree!

"""
    StarTreeEmbedding(component, vertex_spacing)

`component` must already have a spanning tree; `vertex_spacing` is the least gap
kept between two subtree circles.
"""
struct StarTreeEmbedding
    component::GraphComponent
    vertex_spacing::Float64
end

StarTreeEmbedding(component::GraphComponent, vertex_spacing::Real) =
    StarTreeEmbedding(component, Float64(vertex_spacing))

"""
    embed_star_tree!(embedding)

Place every vertex of the component, writing into each vertex's `rc.pt`.
"""
function embed_star_tree!(embedding::StarTreeEmbedding)
    root = embedding.component.spanning_tree_root
    root === nothing && return nothing
    _calculate_center!(embedding, root)
    _rotate_center!(root)
    _calculate_position!(root, pt_zero())
    nothing
end

# Each child subtree is placed against the circles already there: the parent's
# own circle, and one circle per sibling already placed. A candidate position is
# where two of those circles cross, which is the position touching both.
function _calculate_center!(embedding::StarTreeEmbedding, vertex::LayoutVertex)
    spacing = embedding.vertex_spacing

    if isempty(vertex.spanning_tree_children)
        vertex.star_tree_radius = get_diagonal_length(vertex.rc.rs) / 2
        vertex.star_tree_center = pt_zero()
        vertex.star_tree_circle_center = pt_zero()
        return nothing
    end

    vertex.star_tree_center = pt_zero()
    for child in vertex.spanning_tree_children
        _calculate_center!(embedding, child)
    end

    for child in vertex.spanning_tree_children
        circles = Cc[Cc(pt_zero(),
                        get_diagonal_length(vertex.rc.rs) / 2 + spacing + child.star_tree_radius)]
        for placed in vertex.spanning_tree_children
            placed === child && break
            push!(circles, Cc(placed.star_tree_center + placed.star_tree_circle_center,
                              placed.star_tree_radius + spacing + child.star_tree_radius))
        end

        points = Pt[]
        for i in 1:length(circles), j in (i+1):length(circles)
            append!(points, cc_intersect(circles[i], circles[j]))
        end

        # The first child has only the parent's circle to go against, so its
        # candidates are that circle's four cardinal points.
        if length(circles) == 1
            self = circles[1]
            push!(points, cc_center_top(self), cc_center_bottom(self),
                          cc_left_center(self), cc_right_center(self))
        end

        # A candidate inside any of the circles would overlap; the one-unit
        # slack is the original's, and it forgives the rounding of an
        # intersection point that should lie exactly on a circle.
        filter!(pt -> !any(cc -> pt_distance(pt, cc.origin) < cc.radius - 1, circles), points)

        least = Inf
        for pt in points
            cost = pt_distance(vertex.star_tree_center, pt)
            if cost < least
                least = cost
                child.star_tree_center = pt - child.star_tree_circle_center
            end
        end
    end

    # Wrap the parent and all its children in one circle, which is what this
    # subtree looks like to its own parent.
    circles = Cc[Cc(pt_zero(), get_diagonal_length(vertex.rc.rs) / 2)]
    for child in vertex.spanning_tree_children
        push!(circles, Cc(child.star_tree_center + child.star_tree_circle_center,
                          child.star_tree_radius))
    end
    enclosing = cc_enclosing(circles)
    vertex.star_tree_radius = enclosing.radius
    vertex.star_tree_circle_center = enclosing.origin
    nothing
end

# Turn each subtree about its own circle centre so that the weight of its
# children falls opposite its parent. Without this a subtree can point back the
# way it came and fold over the rest of the tree.
function _rotate_center!(vertex::LayoutVertex)
    isempty(vertex.spanning_tree_children) && return nothing

    if vertex.spanning_tree_parent !== nothing
        angle = get_base_plane_angle(vertex.star_tree_center + vertex.star_tree_circle_center)

        weight_point = pt_zero()
        total_area = 0.0
        for child in vertex.spanning_tree_children
            child_area = area(child.rc.rs)
            total_area += child_area
            weight_point = weight_point +
                (child.star_tree_center + vertex.star_tree_circle_center) * child_area
        end
        weight_point = weight_point / total_area
        rotate_by = angle - get_base_plane_angle(weight_point)

        if !isnan(rotate_by)
            for child in vertex.spanning_tree_children
                pt = child.star_tree_center + child.star_tree_circle_center +
                     vertex.star_tree_circle_center
                child.star_tree_center =
                    rotate_base_plane(pt, rotate_by) - child.star_tree_circle_center
            end

            pt = rotate_base_plane(-vertex.star_tree_circle_center, rotate_by)
            vertex.star_tree_center =
                vertex.star_tree_center + vertex.star_tree_circle_center + pt
            vertex.star_tree_circle_center = -pt

            for child in vertex.spanning_tree_children
                child.star_tree_center =
                    child.star_tree_center - vertex.star_tree_circle_center
            end
        end
    end

    for child in vertex.spanning_tree_children
        _rotate_center!(child)
    end
    nothing
end

# Turn the relative subtree centres into absolute top-left corners.
function _calculate_position!(vertex::LayoutVertex, pt::Pt)
    vertex.rc = Rc(Pt(pt.x - vertex.rc.rs.width/2, pt.y - vertex.rc.rs.height/2, pt.z),
                   vertex.rc.rs)

    vertex.spanning_tree_parent === nothing ||
        (vertex.star_tree_circle_center = vertex.star_tree_circle_center + pt)

    for child in vertex.spanning_tree_children
        _calculate_position!(child, pt + child.star_tree_center)
    end
    nothing
end

end # module
