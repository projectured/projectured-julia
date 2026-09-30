# Fragment of `GraphModule`.
#
# `FruchtermanReingoldLayout`, the force-directed placement of Fruchterman and
# Reingold ("Graph Drawing by Force-directed Placement", Software — Practice and
# Experience 21(11), 1991), written from the paper. An edge pulls its two ends
# together with `d²/k`, every pair of bodies pushes apart with `k²/d`, and a
# temperature that falls each round caps how far a body moves.
#
# Four things are added for the boxes that this package draws, and each one is
# named where it is done:
#
# - **Sizes.** `k`, the ideal distance, comes from the boxes, and the distances
#   that the forces read are measured between the rims of two bodies, not
#   between their centres, so a large card gets the room it needs.
# - **Constraints.** A pinned vertex is a body that does not move. A cluster is
#   one body that carries its members at their offsets.
# - **Parts that are not connected** feel a weak pull to the centre of the
#   drawing, so no part drifts away from the others.
# - **No overlap.** After the simulation, each pair of boxes that still overlap
#   is pushed apart along the axis where they overlap less.
#
# The start is a sunflower spiral in the order of `layout_vertices`, so the
# placement is a function of its input and needs no random numbers.

"""
    FruchtermanReingoldLayout(; iterations = 300, spacing = 20)

The force-directed engine of this package. `iterations` is the number of
rounds of the simulation, and `spacing` the gap it keeps between two boxes.
It implements `:pin`, `:fixed_size` and `:cluster`, and it routes edges as
straight lines.
"""
struct FruchtermanReingoldLayout <: GraphLayoutEngine
    iterations::Int
    spacing::Float64
end

FruchtermanReingoldLayout(; iterations::Integer = 300, spacing::Real = 20) =
    FruchtermanReingoldLayout(Int(iterations), Float64(spacing))

get_supported_constraint_kinds(::FruchtermanReingoldLayout) =
    (:pin, :fixed_size, :cluster)
layout_engine_name(::FruchtermanReingoldLayout) = :fruchterman_reingold

# The angle between two neighbours on a sunflower spiral, in radians.
const _GOLDEN_ANGLE = pi * (3 - sqrt(5))

# The pull to the centre of the drawing, as a share of the distance to it. At
# ten times the ideal distance it is a fifth of that distance, which keeps the
# parts of a graph near each other and does not press a connected part together.
const _CENTRE_PULL = 0.02

# One thing that moves as a whole: a free vertex, a pinned vertex, or the
# family of a cluster. `members` are indices into the vertices, `offsets` the
# centre of each member relative to the body, and `radius` the distance from
# the body to the farthest corner of a member.
struct _LayoutBody
    members::Vector{Int}
    offsets::Vector{Tuple{Float64,Float64}}
    fixed::Bool
    radius::Float64
end

function layout_graph(engine::FruchtermanReingoldLayout, graph::GraphGraph, sizes::Dict,
                      constraints::Vector; extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)
    vertices = layout_vertices(graph)
    n = length(vertices)
    positions = Dict{UInt,NTuple{4,Int}}()
    n == 0 && return (positions, Dict{UInt,Vector{Tuple{Int,Int}}}())

    widths, heights = get_vertex_sizes(vertices, sizes, constraints)
    pins = get_constraint_pins(constraints)
    bodies, body_of = _make_layout_bodies(vertices, widths, heights, pins,
                                          get_constraint_clusters(constraints))
    # The ideal distance between two bodies, from the mean size of a box.
    k = sum(sqrt(widths[i] * heights[i]) for i in 1:n) / n + engine.spacing

    x = zeros(Float64, length(bodies)); y = zeros(Float64, length(bodies))
    _place_on_spiral!(x, y, bodies, vertices, widths, heights, pins, k)
    edges = _collect_body_edges(graph, vertices, body_of)
    _simulate_forces!(x, y, bodies, edges, k, engine.iterations)
    _remove_overlaps!(x, y, bodies, widths, heights, engine.spacing / 2)

    cx = zeros(Float64, n); cy = zeros(Float64, n)
    _place_members!(cx, cy, x, y, bodies)
    if extent !== nothing && isempty(pins)
        _fit_bodies_into_extent!(x, y, cx, cy, bodies, widths, heights, extent, border)
    elseif extent !== nothing
        _keep_bodies_inside_extent!(x, y, bodies, widths, heights, extent, border)
    elseif isempty(pins)
        # With no box and no pin the placement has no origin of its own, so it
        # starts at the border.
        left = minimum(cx[i] - widths[i]/2 for i in 1:n)
        top = minimum(cy[i] - heights[i]/2 for i in 1:n)
        x .+= border - left; y .+= border - top
    end
    _place_members!(cx, cy, x, y, bodies)

    for i in 1:n
        positions[objectid(vertices[i])] =
            (round(Int, cx[i] - widths[i]/2), round(Int, cy[i] - heights[i]/2),
             round(Int, widths[i]), round(Int, heights[i]))
    end
    (positions, get_straight_routes(graph, positions))
end

# The bodies of the simulation, and the body of each vertex. A pin wins over a
# cluster, as it does in every engine here: a pinned vertex is where the caller
# put it.
function _make_layout_bodies(vertices, widths, heights, pins, clusters)
    n = length(vertices)
    body_of = zeros(Int, n)
    bodies = _LayoutBody[]
    family_of = Dict{Any,Int}()
    corner(i, offset) = hypot(abs(offset[1]) + widths[i]/2, abs(offset[2]) + heights[i]/2)
    for i in 1:n
        id = objectid(vertices[i])
        cluster = get(clusters, id, nothing)
        if haskey(pins, id) || cluster === nothing
            push!(bodies, _LayoutBody([i], [(0.0, 0.0)], haskey(pins, id),
                                      corner(i, (0.0, 0.0))))
            body_of[i] = length(bodies)
            continue
        end
        group, offx, offy = cluster
        b = get(family_of, group, 0)
        if b == 0
            push!(bodies, _LayoutBody(Int[], Tuple{Float64,Float64}[], false, 0.0))
            b = family_of[group] = length(bodies)
        end
        family = bodies[b]
        push!(family.members, i)
        push!(family.offsets, (offx, offy))
        bodies[b] = _LayoutBody(family.members, family.offsets, false,
                                max(family.radius, corner(i, (offx, offy))))
        body_of[i] = b
    end
    (bodies, body_of)
end

# The start: pinned bodies at their pins, and every other body on a sunflower
# spiral around the centre of the pins, in the order of its first vertex. A
# spiral has no two bodies on one line, so the forces have a side to push to.
function _place_on_spiral!(x, y, bodies, vertices, widths, heights, pins, k)
    centre = (0.0, 0.0)
    if !isempty(pins)
        pinned = [(p[1] + widths[i]/2, p[2] + heights[i]/2)
                  for (i, v) in enumerate(vertices)
                  for p in (get(pins, objectid(v), nothing),)
                  if p !== nothing]
        centre = (sum(first, pinned) / length(pinned), sum(last, pinned) / length(pinned))
    end
    turn = 0
    for (b, body) in enumerate(bodies)
        if body.fixed
            i = body.members[1]
            pin = pins[objectid(vertices[i])]
            x[b] = pin[1] + widths[i]/2
            y[b] = pin[2] + heights[i]/2
        else
            turn += 1
            radius = k * sqrt(turn)
            x[b] = centre[1] + radius * cos(turn * _GOLDEN_ANGLE)
            y[b] = centre[2] + radius * sin(turn * _GOLDEN_ANGLE)
        end
    end
    nothing
end

# The edges as pairs of bodies. An edge inside one body pulls nothing, and a
# second edge between the same two bodies pulls again, as it does in the paper.
function _collect_body_edges(graph, vertices, body_of)
    index = Dict{UInt,Int}(objectid(vertices[i]) => i for i in eachindex(vertices))
    edges = Tuple{Int,Int}[]
    for e in 1:length(graph.edges)
        edge = graph.edges[e]
        edge isa GraphEdge || continue
        source = get(index, objectid(getfield(edge, :source)[]), 0)
        target = get(index, objectid(getfield(edge, :target)[]), 0)
        (source == 0 || target == 0) && continue
        a, b = body_of[source], body_of[target]
        a == b || push!(edges, (a, b))
    end
    edges
end

# The simulation of the paper: repulsion between every pair of bodies,
# attraction along every edge, and a displacement capped by a temperature that
# falls to nothing. The distances are measured between the rims of two bodies,
# and a weak pull to the centre keeps the parts of a graph together.
function _simulate_forces!(x, y, bodies, edges, k, iterations)
    m = length(bodies)
    movable = [b for b in 1:m if !bodies[b].fixed]
    isempty(movable) && return nothing
    dx = zeros(Float64, m); dy = zeros(Float64, m)
    start_temperature = k * sqrt(length(movable))
    rim(a, b, distance) = max(distance - bodies[a].radius - bodies[b].radius, 0.05 * k)
    for round in 1:iterations
        fill!(dx, 0.0); fill!(dy, 0.0)
        for a in 1:m, b in (a+1):m
            ex, ey = x[a] - x[b], y[a] - y[b]
            distance = hypot(ex, ey)
            # Two bodies on one point are pushed apart along the order of their
            # indices, so the result stays a function of the input.
            distance == 0 && ((ex, ey, distance) = (1.0 * (b - a), 0.0, 1.0 * (b - a)))
            force = k^2 / rim(a, b, distance)
            dx[a] += ex / distance * force; dy[a] += ey / distance * force
            dx[b] -= ex / distance * force; dy[b] -= ey / distance * force
        end
        for (a, b) in edges
            ex, ey = x[a] - x[b], y[a] - y[b]
            distance = hypot(ex, ey)
            distance == 0 && continue
            force = max(distance - bodies[a].radius - bodies[b].radius, 0.0)^2 / k
            dx[a] -= ex / distance * force; dy[a] -= ey / distance * force
            dx[b] += ex / distance * force; dy[b] += ey / distance * force
        end
        centre_x = sum(x[b] for b in movable) / length(movable)
        centre_y = sum(y[b] for b in movable) / length(movable)
        temperature = start_temperature * (1 - (round - 1) / iterations)
        for b in movable
            gx = dx[b] - _CENTRE_PULL * (x[b] - centre_x)
            gy = dy[b] - _CENTRE_PULL * (y[b] - centre_y)
            length_ = hypot(gx, gy)
            length_ == 0 && continue
            step = min(length_, temperature)
            x[b] += gx / length_ * step
            y[b] += gy / length_ * step
        end
    end
    nothing
end

# The centre of each vertex: its body plus its offset.
function _place_members!(cx, cy, x, y, bodies)
    for (b, body) in enumerate(bodies),
        (member, offset) in zip(body.members, body.offsets)
        cx[member] = x[b] + offset[1]
        cy[member] = y[b] + offset[2]
    end
    nothing
end

# Push apart every two boxes of different bodies that overlap, with `margin`
# around each box, along the axis where they overlap less. A pinned body does
# not move, so its partner moves the whole way. It stops when nothing overlaps,
# or after a bounded number of passes.
function _remove_overlaps!(x, y, bodies, widths, heights, margin)
    n = length(widths)
    cx = zeros(Float64, n); cy = zeros(Float64, n)
    owner = zeros(Int, n)
    for (b, body) in enumerate(bodies), member in body.members
        owner[member] = b
    end
    for _ in 1:200
        _place_members!(cx, cy, x, y, bodies)
        moved = false
        for i in 1:n, j in (i+1):n
            a, b = owner[i], owner[j]
            a == b && continue
            (bodies[a].fixed && bodies[b].fixed) && continue
            ox = (widths[i] + widths[j]) / 2 + 2margin - abs(cx[i] - cx[j])
            oy = (heights[i] + heights[j]) / 2 + 2margin - abs(cy[i] - cy[j])
            (ox > 0 && oy > 0) || continue
            share_a = bodies[a].fixed ? 0.0 : bodies[b].fixed ? 1.0 : 0.5
            if ox <= oy
                direction = cx[i] < cx[j] || (cx[i] == cx[j] && i < j) ? -1.0 : 1.0
                x[a] += direction * ox * share_a; x[b] -= direction * ox * (1 - share_a)
                cx[i] += direction * ox * share_a; cx[j] -= direction * ox * (1 - share_a)
            else
                direction = cy[i] < cy[j] || (cy[i] == cy[j] && i < j) ? -1.0 : 1.0
                y[a] += direction * oy * share_a; y[b] -= direction * oy * (1 - share_a)
                cy[i] += direction * oy * share_a; cy[j] -= direction * oy * (1 - share_a)
            end
            moved = true
        end
        moved || return nothing
    end
    nothing
end

# With no pin, the drawing is scaled into the extent: the centres of the bodies
# move, the members keep their offsets, and a box keeps its size, as in every
# engine here.
function _fit_bodies_into_extent!(x, y, cx, cy, bodies, widths, heights, extent, border)
    indices = collect(1:length(widths))
    transform = get_extent_transform(cx, cy; widths, heights, indices, extent, border)
    transform === nothing && return nothing
    fx, fy, x1, y1, ox, oy = transform
    for b in eachindex(bodies)
        x[b] = ox + (x[b] - x1) * fx
        y[b] = oy + (y[b] - y1) * fy
    end
    nothing
end

# With a pin the drawing keeps its scale, because a pin is a place in the
# extent; every other body is moved just far enough to lie inside it.
function _keep_bodies_inside_extent!(x, y, bodies, widths, heights, extent, border)
    for (b, body) in enumerate(bodies)
        body.fixed && continue
        left = minimum(x[b] + o[1] - widths[i]/2
                       for (i, o) in zip(body.members, body.offsets))
        right = maximum(x[b] + o[1] + widths[i]/2
                        for (i, o) in zip(body.members, body.offsets))
        top = minimum(y[b] + o[2] - heights[i]/2
                      for (i, o) in zip(body.members, body.offsets))
        bottom = maximum(y[b] + o[2] + heights[i]/2
                         for (i, o) in zip(body.members, body.offsets))
        # When a body is wider than the room, its left side wins.
        shift_x = min(0.0, extent[1] - border - right)
        left + shift_x < border && (shift_x = border - left)
        shift_y = min(0.0, extent[2] - border - bottom)
        top + shift_y < border && (shift_y = border - top)
        x[b] += shift_x
        y[b] += shift_y
    end
    nothing
end
