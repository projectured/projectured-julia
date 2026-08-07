"""
    PaneGeometryModule

Where the groups of a pane tree sit, and which one lies in a given direction.

The arithmetic runs on the **tree and its weights alone** — one walk gives every
group a rectangle in the unit square. No font, no measurement, and no backend
takes part, so directional navigation is decided the same way whatever the pane
is rendered on, and it is testable on its own.

A rectangle is a `NamedTuple` `(x, y, w, h)`, with `x` growing right and `y`
growing down, matching the screen.
"""
module PaneGeometryModule

import ..PaneModule: PaneTree, PaneSplit, PaneGroup, PaneTab,
                     pane_groups, pane_weights, pane_normalized_weights

export pane_rectangles, pane_rectangle, pane_neighbour_group, pane_next_group,
       pane_group_at

# Two edges that meet exactly must still read as "past each other", so every
# comparison allows this much slack.
const _PANE_EPSILON = 1e-9

# ── Rectangles ─────────────────────────────────────────────────────────────

"""
    pane_rectangles(tree) -> Vector{Pair{PaneGroup, NamedTuple}}

Every group with its rectangle in the unit square, in traversal order.
"""
function pane_rectangles(tree::PaneTree)
    result = Pair{PaneGroup, NamedTuple}[]
    _rectangle_walk!(tree.root, (x = 0.0, y = 0.0, w = 1.0, h = 1.0), result)
    result
end

_rectangle_walk!(group::PaneGroup, rectangle, result) = push!(result, group => rectangle)
_rectangle_walk!(::Any, rectangle, result) = result

function _rectangle_walk!(split::PaneSplit, rectangle, result)
    weights = pane_normalized_weights(pane_weights(split))
    offset = 0.0
    for i in 1:length(split.elements)
        share = weights[i]
        # A vertical split divides the width (its children sit side by side); a
        # horizontal one divides the height.
        child = split.orientation === :vertical ?
            (x = rectangle.x + offset * rectangle.w, y = rectangle.y,
             w = share * rectangle.w, h = rectangle.h) :
            (x = rectangle.x, y = rectangle.y + offset * rectangle.h,
             w = rectangle.w, h = share * rectangle.h)
        _rectangle_walk!(split.elements[i], child, result)
        offset += share
    end
    result
end

"""
    pane_rectangle(tree, group) -> NamedTuple | Nothing

The rectangle of one group, or `nothing` when it is not in the tree.
"""
function pane_rectangle(tree::PaneTree, group::PaneGroup)
    for (other, rectangle) in pane_rectangles(tree)
        other === group && return rectangle
    end
    nothing
end

"""
    pane_group_at(tree, x, y) -> PaneGroup | Nothing

The group whose rectangle holds the unit-square point `(x, y)`.
"""
function pane_group_at(tree::PaneTree, x::Real, y::Real)
    for (group, r) in pane_rectangles(tree)
        (r.x - _PANE_EPSILON <= x <= r.x + r.w + _PANE_EPSILON &&
         r.y - _PANE_EPSILON <= y <= r.y + r.h + _PANE_EPSILON) && return group
    end
    nothing
end

# ── The direction search ───────────────────────────────────────────────────

"""
    pane_neighbour_group(tree, group, direction) -> PaneGroup | Nothing

The group that lies in `direction` (`:left`, `:right`, `:up`, or `:down`) from
`group`, or `nothing` when there is none.

A candidate must lie wholly past `group`'s edge in that direction and must
overlap it on the other axis. The nearest candidate wins; a tie goes to the one
that overlaps most, and then to the one nearest the top left. So a move right
from a tall pane into a column of short panes lands on the one the pointer would
expect — the one facing it most.
"""
function pane_neighbour_group(tree::PaneTree, group::PaneGroup, direction::Symbol)
    here = pane_rectangle(tree, group)
    here === nothing && return nothing
    best = nothing
    best_key = nothing
    for (other, there) in pane_rectangles(tree)
        other === group && continue
        measure = _direction_measure(here, there, direction)
        measure === nothing && continue
        gap, overlap = measure
        overlap > _PANE_EPSILON || continue
        key = (gap, -overlap, there.y, there.x)
        if best === nothing || key < best_key
            best = other
            best_key = key
        end
    end
    best
end

# `(gap, overlap)` for a candidate that lies in `direction`, or `nothing` when it
# does not. `gap` is the distance between the two facing edges; `overlap` is how
# much the two rectangles share on the other axis.
function _direction_measure(here, there, direction::Symbol)
    if direction === :right
        gap = there.x - (here.x + here.w)
        gap < -_PANE_EPSILON && return nothing
        return (gap, _overlap(here.y, here.h, there.y, there.h))
    elseif direction === :left
        gap = here.x - (there.x + there.w)
        gap < -_PANE_EPSILON && return nothing
        return (gap, _overlap(here.y, here.h, there.y, there.h))
    elseif direction === :down
        gap = there.y - (here.y + here.h)
        gap < -_PANE_EPSILON && return nothing
        return (gap, _overlap(here.x, here.w, there.x, there.w))
    elseif direction === :up
        gap = here.y - (there.y + there.h)
        gap < -_PANE_EPSILON && return nothing
        return (gap, _overlap(here.x, here.w, there.x, there.w))
    end
    nothing
end

_overlap(a, a_length, b, b_length) = min(a + a_length, b + b_length) - max(a, b)

# ── Traversal ──────────────────────────────────────────────────────────────

"""
    pane_next_group(tree, group; backward = false) -> PaneGroup | Nothing

The next group in traversal order, wrapping around at both ends. A `group` that
is not in the tree answers the first group, so a traversal from nowhere starts at
the beginning.
"""
function pane_next_group(tree::PaneTree, group; backward::Bool = false)
    groups = pane_groups(tree)
    isempty(groups) && return nothing
    index = findfirst(other -> other === group, groups)
    index === nothing && return backward ? groups[end] : groups[1]
    n = length(groups)
    groups[backward ? (index == 1 ? n : index - 1) : (index == n ? 1 : index + 1)]
end

end # module PaneGeometryModule
