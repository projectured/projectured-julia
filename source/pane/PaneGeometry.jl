# ──────────────────────────────────────────────────────────────────────────
# Folded in from PaneGeometry.jl.
#
# Where the groups of a pane tree sit, and which one lies in a given direction.
#
# The arithmetic runs on the **tree and its weights alone** — one walk gives every
# group a rectangle in the unit square. No font, no measurement, and no backend
# takes part, so directional navigation is decided the same way whatever the pane
# is rendered on, and it is testable on its own.
#
# A rectangle is a `NamedTuple` `(x, y, w, h)`, with `x` growing right and `y`
# growing down, matching the screen.
# Two edges that meet exactly must still read as "past each other", so every
# comparison allows this much slack.
const _PANE_EPSILON = 1e-9

# ── Rectangles ─────────────────────────────────────────────────────────────

"""
    get_pane_rectangles(tree) -> Vector{Pair{PaneGroup, NamedTuple}}

Every group with its rectangle in the unit square, in traversal order.
"""
function get_pane_rectangles(tree::PaneTree)
    result = Pair{PaneGroup, NamedTuple}[]
    _rectangle_walk!(tree.root, (x = 0.0, y = 0.0, w = 1.0, h = 1.0), result)
    result
end

_rectangle_walk!(group::PaneGroup, rectangle, result) = push!(result, group => rectangle)
_rectangle_walk!(::Any, rectangle, result) = result

function _rectangle_walk!(split::PaneSplit, rectangle, result)
    weights = get_pane_normalized_weights(get_pane_weights(split))
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
    get_pane_rectangle(tree, group) -> NamedTuple | Nothing

The rectangle of one group, or `nothing` when it is not in the tree.
"""
function get_pane_rectangle(tree::PaneTree, group::PaneGroup)
    for (other, rectangle) in get_pane_rectangles(tree)
        other === group && return rectangle
    end
    nothing
end

"""
    get_pane_group_at_point(tree, x, y) -> PaneGroup | Nothing

The group whose rectangle holds the unit-square point `(x, y)`.
"""
function get_pane_group_at_point(tree::PaneTree, x::Real, y::Real)
    for (group, r) in get_pane_rectangles(tree)
        (r.x - _PANE_EPSILON <= x <= r.x + r.w + _PANE_EPSILON &&
         r.y - _PANE_EPSILON <= y <= r.y + r.h + _PANE_EPSILON) && return group
    end
    nothing
end

# ── The direction search ───────────────────────────────────────────────────

"""
    get_pane_neighbour_group(tree, group, direction) -> PaneGroup | Nothing

The group that lies in `direction` (`:left`, `:right`, `:up`, or `:down`) from
`group`, or `nothing` when there is none.

A candidate must lie wholly past `group`'s edge in that direction and must
overlap it on the other axis. The nearest candidate wins; a tie goes to the one
that overlaps most, and then to the one nearest the top left. So a move right
from a tall pane into a column of short panes lands on the one the pointer would
expect — the one facing it most.
"""
function get_pane_neighbour_group(tree::PaneTree, group::PaneGroup, direction::Symbol)
    here = get_pane_rectangle(tree, group)
    here === nothing && return nothing
    best = nothing
    best_key = nothing
    for (other, there) in get_pane_rectangles(tree)
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

# ── Drop zones ─────────────────────────────────────────────────────────────

"""
    get_pane_drop_zone(tree, x, y; strip = 0.0, band = 0.2) -> (group, zone) | Nothing

The group under the unit-square point `(x, y)`, and which part of it the point
landed in:

  * `:strip`  — the tab strip across its top. `strip` is its height **in units of
    the whole square**, because a strip is a fixed number of pixels rather than a
    share of its group; it is divided by the group's height here. A drop there
    means "into this group", the same as its middle.
  * `:center` — the middle. A drop there moves the tab into the group.
  * `:left`, `:right`, `:above`, `:below` — an edge band, `band` wide as a
    fraction of the group. A drop there splits the group and puts the tab in the
    new pane.

A band wins over the centre, and the strip wins over everything, so the three
never overlap.
"""
function get_pane_drop_zone(tree::PaneTree, x::Real, y::Real; strip::Real = 0.0, band::Real = 0.2)
    group = get_pane_group_at_point(tree, x, y)
    group === nothing && return nothing
    r = get_pane_rectangle(tree, group)
    (r === nothing || r.w <= 0 || r.h <= 0) && return nothing
    u = (x - r.x) / r.w
    v = (y - r.y) / r.h
    local_strip = min(0.5, strip / r.h)
    v <= local_strip && return (group, :strip)
    below_strip = (v - local_strip) / (1 - local_strip)
    u < band && return (group, :left)
    u > 1 - band && return (group, :right)
    below_strip < band && return (group, :above)
    below_strip > 1 - band && return (group, :below)
    (group, :center)
end

"""
    get_pane_zone_orientation(zone) -> Symbol | Nothing

The split a drop on `zone` makes: `:vertical` for a side band (the new pane sits
beside), `:horizontal` for a top or bottom one (it sits above or below).
`nothing` for a zone that moves rather than splits.
"""
get_pane_zone_orientation(zone::Symbol) =
    zone === :left || zone === :right ? :vertical :
    zone === :above || zone === :below ? :horizontal : nothing

# ── Traversal ──────────────────────────────────────────────────────────────

"""
    get_pane_next_group(tree, group; backward = false) -> PaneGroup | Nothing

The next group in traversal order, wrapping around at both ends. A `group` that
is not in the tree answers the first group, so a traversal from nowhere starts at
the beginning.
"""
function get_pane_next_group(tree::PaneTree, group; backward::Bool = false)
    groups = get_pane_groups(tree)
    isempty(groups) && return nothing
    index = findfirst(other -> other === group, groups)
    index === nothing && return backward ? groups[end] : groups[1]
    n = length(groups)
    groups[backward ? (index == 1 ? n : index - 1) : (index == n ? 1 : index + 1)]
end
