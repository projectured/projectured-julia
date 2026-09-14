# Fragment of `GraphModule`.
#
# `SpringEmbedderLayout`, the port of OMNeT++'s
# `src/layout/basicspringembedderlayout.cc`.
#
# This is the layouter OMNeT++ 3.x shipped, and the one Qtenv still reaches for
# when a module has twenty submodules or more, because it is the fast one. Every
# edge is a spring pulling its ends to a preferred length, every pair of nodes
# pushes apart, and a halving friction stops the whole thing eventually.
#
# Three things in it are not the textbook algorithm, and all three matter:
#
# - **Repulsion between unconnected parts dies off.** Two nodes of different
#   colour — different connected parts — stop repelling past 100 units. Without
#   that, a graph in several pieces blows itself apart instead of laying out.
# - **Movement is capped, not the force.** A node moves at most 50 units per
#   iteration, and the velocity that produced it is kept, so a large force turns
#   into sustained movement rather than one jump.
# - **A node not connected to anything fixed may leave through the top and the
#   left** while it settles, and is shifted back at the end. Letting it out gives
#   a better arrangement than pressing it against a wall.
#
# The header of the original states the simplification that decides where this
# layouter is used and where the force-directed one is: **it ignores node sizes**.
# An edge's preferred length grows a little with its endpoints, and nothing else
# in the simulation knows how big a box is. A network of equal-sized icons reads
# well; a network of cards does not.
# ── The engine ───────────────────────────────────────────────────────────────

"""
    SpringEmbedderLayout(; default_edge_length=40, max_iterations=500,
                         repulsive_force=50, attraction_force=0.3, seed=1)

The spring embedder, with OMNeT++'s own constants. They are the four numbers
Qtenv exposes as the `bgl` display-string tag, in that order.

`seed` is what makes a layout repeatable. The algorithm scatters its start
positions at random, so a layout without a fixed seed is a different picture
every time and nothing downstream can cache, compare or screenshot it. Qtenv
seeds each module type with 1 the first time it lays that type out, so 1 is the
default here.

It implements `:pin` (a fixed node), `:cluster` (an anchor, which is how a
module vector is laid out as one body) and `:fixed_size`.
"""
struct SpringEmbedderLayout <: GraphLayoutEngine
    default_edge_length::Float64
    max_iterations::Int
    repulsive_force::Float64
    attraction_force::Float64
    seed::Int32
end

SpringEmbedderLayout(; default_edge_length::Real = 40, max_iterations::Integer = 500,
                     repulsive_force::Real = 50, attraction_force::Real = 0.3,
                     seed::Integer = 1) =
    SpringEmbedderLayout(Float64(default_edge_length), Int(max_iterations),
                         Float64(repulsive_force), Float64(attraction_force),
                         Int32(seed))

get_supported_constraint_kinds(::SpringEmbedderLayout) = (:pin, :fixed_size, :cluster)
layout_engine_name(::SpringEmbedderLayout) = :spring_embedder

# ── The layouter's own structures ────────────────────────────────────────────

# An anchor point several nodes hang off. They keep their offsets to it and so
# can only move together, which is how a module vector keeps its shape.
mutable struct Anchor
    name::Any
    x::Float64
    y::Float64
    refcount::Int
    x1off::Float64          # the bounding box of the anchored nodes,
    y1off::Float64          # relative to (x, y)
    x2off::Float64
    y2off::Float64
    vx::Float64
    vy::Float64
end

Anchor(name) = Anchor(name, 0.0, 0.0, 0, Inf, Inf, -Inf, -Inf, 0.0, 0.0)

mutable struct Node
    node_id::Int
    fixed::Bool
    anchor::Union{Nothing,Anchor}
    x::Float64              # the centre of the node
    y::Float64
    offx::Float64           # anchored nodes: the offset to the anchor point
    offy::Float64
    sx::Float64             # half width and half height
    sy::Float64
    vx::Float64             # the distance moved at each step, kept between steps
    vy::Float64
    color::Int              # connected nodes share a colour
    connected_to_fixed::Bool
end

Node(node_id::Int) = Node(node_id, false, nothing, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                          0.0, 0.0, -1, false)

struct Edge
    source::Node
    target::Node
    len::Float64
end

mutable struct SpringEmbedderState
    engine::SpringEmbedderLayout
    random::LcgRandom
    anchors::Vector{Anchor}
    nodes::Vector{Node}
    edges::Vector{Edge}
    node_map::Dict{Int,Node}
    width::Float64          # 0 means unspecified
    height::Float64
    border::Float64
    have_fixed_node::Bool
    have_anchored_node::Bool
    all_nodes_are_fixed::Bool
    minx::Float64
    miny::Float64
    maxx::Float64
    maxy::Float64
end

SpringEmbedderState(engine::SpringEmbedderLayout) =
    SpringEmbedderState(engine, LcgRandom(engine.seed), Anchor[], Node[], Edge[],
                        Dict{Int,Node}(), 0.0, 0.0, 0.0, false, false, true,
                        0.0, 0.0, 0.0, 0.0)

_rand01(state::SpringEmbedderState) = draw_uniform01!(state.random)

function set_size!(state::SpringEmbedderState, width::Real, height::Real, border::Real)
    if (width != 0 && width < 2*border) || (height != 0 && height < 2*border)
        throw(ArgumentError(
            "SpringEmbedderLayout: the extent $((width, height)) is smaller than " *
            "twice the border $border."))
    end
    state.width = Float64(width)
    state.height = Float64(height)
    state.border = Float64(border)
    nothing
end

find_node(state::SpringEmbedderState, node_id::Int) = get(state.node_map, node_id, nothing)

function add_movable_node!(state::SpringEmbedderState, node_id::Int,
                           width::Real, height::Real)
    state.all_nodes_are_fixed = false
    node = Node(node_id)
    node.sx = width/2
    node.sy = height/2
    push!(state.nodes, node)
    state.node_map[node_id] = node
    node
end

# (x, y) is the centre of the node, which is what getNodePosition answers too.
function add_fixed_node!(state::SpringEmbedderState, node_id::Int, x::Real, y::Real,
                         width::Real, height::Real)
    state.have_fixed_node = true
    node = Node(node_id)
    node.fixed = true
    node.x = Float64(x)
    node.y = Float64(y)
    node.sx = width/2
    node.sy = height/2
    push!(state.nodes, node)
    state.node_map[node_id] = node
    node
end

function add_anchored_node!(state::SpringEmbedderState, node_id::Int, anchor_name,
                            offx::Real, offy::Real, width::Real, height::Real)
    state.have_anchored_node = true
    state.all_nodes_are_fixed = false

    anchor = nothing
    for candidate in state.anchors
        if isequal(candidate.name, anchor_name)
            anchor = candidate
            break
        end
    end
    if anchor === nothing
        anchor = Anchor(anchor_name)
        push!(state.anchors, anchor)
    end

    node = Node(node_id)
    node.anchor = anchor
    anchor.refcount += 1
    node.offx = Float64(offx)
    node.offy = Float64(offy)
    node.sx = width/2
    node.sy = height/2
    push!(state.nodes, node)
    state.node_map[node_id] = node
    node
end

function add_edge!(state::SpringEmbedderState, source_id::Int, target_id::Int,
                   len::Real = 0)
    source = find_node(state, source_id)
    target = find_node(state, target_id)
    (source === nothing || target === nothing) && return nothing
    length = len > 0 ? Float64(len) : state.engine.default_edge_length
    # The one place a node's size is read: an edge between two big boxes wants to
    # be a little longer. A quarter of the smaller dimension of each endpoint.
    length += min(source.sx, source.sy)/2 + min(target.sx, target.sy)/2
    push!(state.edges, Edge(source, target, length))
    nothing
end

"The centre of the node, which is what the caller converts back to a corner."
function node_position(state::SpringEmbedderState, node_id::Int)
    node = find_node(state, node_id)
    node === nothing ? (0.0, 0.0) : (node.x, node.y)
end

# ── execute ──────────────────────────────────────────────────────────────────

function execute!(state::SpringEmbedderState)
    (isempty(state.nodes) || state.all_nodes_are_fixed) && return nothing

    compute_anchor_bounding_boxes!(state)

    # Scatter the movable nodes over an area proportional to how many there are,
    # and over whatever the fixed nodes already cover.
    assign_initial_positions!(state)

    if !state.have_fixed_node
        # Lay out on an infinite area: with nothing pinned, the whole picture can
        # be scaled and shifted into the box afterwards.
        state.minx = -100000000.0
        state.miny = -100000000.0
        state.maxx = 100000000.0
        state.maxy = 100000000.0
    else
        # The top-left corner is assumed to be (0, 0): the background-position
        # tag is not implemented over there either.
        state.minx = state.border
        state.miny = state.border
        state.maxx = state.width == 0 ? 100000000.0 : state.width - state.border
        state.maxy = state.height == 0 ? 100000000.0 : state.height - state.border
    end

    num_colors = do_coloring!(state)
    mark_nodes_connected_to_fixed!(state, num_colors)

    # Stop when the largest movement stays under 0.05 for twenty iterations in a
    # row, or at the iteration cap.
    maxd_counter = 0
    i = 1
    while i < state.engine.max_iterations && maxd_counter < 20
        maxd = relax!(state)
        maxd_counter = maxd < 0.05 ? maxd_counter + 1 : 0
        i += 1
    end

    if !state.have_fixed_node
        # Rescale and shift into the given area. Only possible with nothing
        # fixed: a pinned coordinate is the caller's and must not be rewritten,
        # and an anchored group's spacing must be preserved.
        x1, y1, x2, y2 = compute_bounding_box(state, _any_node)
        xfact = (state.width == 0 || x1 == x2 || state.have_anchored_node) ? 1.0 :
                (state.width - 2*state.border) / (x2 - x1)
        yfact = (state.height == 0 || y1 == y2 || state.have_anchored_node) ? 1.0 :
                (state.height - 2*state.border) / (y2 - y1)
        for node in state.nodes
            node.x = state.border + (node.x - x1) * xfact
            node.y = state.border + (node.y - y1) * yfact
        end
    elseif state.width == 0 && state.height == 0
        # Nodes not connected to anything fixed were allowed out through the top
        # and the left for a better arrangement. Shift them back.
        x1, y1, _, _ = compute_bounding_box(state, _is_not_connected_to_fixed)
        dx = x1 < state.border ? state.border - x1 : 0.0
        dy = y1 < state.border ? state.border - y1 : 0.0
        for node in state.nodes
            if !node.connected_to_fixed
                node.x += dx
                node.y += dy
            end
        end
    end
    nothing
end

function assign_initial_positions!(state::SpringEmbedderState)
    # Scatter over the area the fixed nodes already cover, or over an area
    # computed from the node count, whichever is larger. The former matters
    # because an incremental layout — placing new modules while the simulation
    # runs — takes every existing module as fixed.
    local initial_width::Float64, initial_height::Float64
    local offset_x::Float64, offset_y::Float64

    if state.width != 0 && state.height != 0
        initial_width = state.width - 2*state.border
        initial_height = state.height - 2*state.border
        offset_x = offset_y = state.border
    else
        # One node is assumed to need 60 by 60 pixels of space.
        area = max(60.0 * 60.0 * length(state.nodes), 600.0 * 400.0)
        aspect_ratio = 1.5
        initial_width = sqrt(area) * aspect_ratio
        initial_height = sqrt(area) / aspect_ratio

        # Leave a quarter free at the top and the left, so fewer movable nodes
        # end up pressed against a wall.
        margin = 0.25 * min(initial_width, initial_height)
        offset_x = offset_y = margin
        if state.have_fixed_node
            x1, y1, x2, y2 = compute_bounding_box(state, _is_fixed_node)

            # Shrink that box a little, so nodes are not placed near its edges:
            # others could push them out, and the next incremental round would
            # then start from a larger box again.
            xmargin = min(150.0, (x2 - x1)/2)
            ymargin = min(150.0, (y2 - y1)/2)
            x1 += xmargin; x2 -= xmargin
            y1 += ymargin; y2 -= ymargin

            right = offset_x + initial_width
            bottom = offset_y + initial_height
            offset_x = min(x1, offset_x)
            offset_y = min(y1, offset_y)
            right = max(x2, right)
            bottom = max(y2, bottom)
            initial_width = right - offset_x
            initial_height = bottom - offset_y
        end
    end

    for anchor in state.anchors
        nodes_width = anchor.x2off - anchor.x1off
        nodes_height = anchor.y2off - anchor.y1off
        left = offset_x + max(0.0, initial_width - nodes_width) * _rand01(state)
        top = offset_y + max(0.0, initial_height - nodes_height) * _rand01(state)
        anchor.x = left - anchor.x1off
        anchor.y = top - anchor.y1off
        anchor.vx = anchor.vy = 0.0
    end
    for node in state.nodes
        if node.fixed
            # nothing: it is where the caller put it
        elseif node.anchor !== nothing
            node.x = node.anchor.x + node.offx
            node.y = node.anchor.y + node.offy
        else
            node.x = offset_x + initial_width * _rand01(state)
            node.y = offset_y + initial_height * _rand01(state)
        end
        node.vx = node.vy = 0.0
    end
    nothing
end

"Give every connected part its own colour, and answer how many there are."
function do_coloring!(state::SpringEmbedderState)
    for node in state.nodes
        node.color = -1
    end

    current_color = 0
    pending = Node[]
    for start in state.nodes
        start.color == -1 || continue

        # Depth-first over the edge list. It is a poor data structure for this,
        # but the cost is nothing beside the relax iterations.
        push!(pending, start)
        while !isempty(pending)
            node = pop!(pending)
            node.color = current_color
            for edge in state.edges
                if edge.source === node && edge.target.color == -1
                    push!(pending, edge.target)
                elseif edge.target === node && edge.source.color == -1
                    push!(pending, edge.source)
                end
            end
        end
        current_color += 1
    end
    current_color
end

function mark_nodes_connected_to_fixed!(state::SpringEmbedderState, num_colors::Int)
    colors_with_fixed_nodes = Set{Int}()
    for node in state.nodes
        node.fixed && push!(colors_with_fixed_nodes, node.color)
    end
    for node in state.nodes
        node.connected_to_fixed = node.color in colors_with_fixed_nodes
    end
    nothing
end

function compute_anchor_bounding_boxes!(state::SpringEmbedderState)
    for anchor in state.anchors
        anchor.x1off = Inf; anchor.y1off = Inf
        anchor.x2off = -Inf; anchor.y2off = -Inf
    end
    for node in state.nodes
        anchor = node.anchor
        anchor === nothing && continue
        anchor.x1off = min(anchor.x1off, node.offx - node.sx)
        anchor.y1off = min(anchor.y1off, node.offy - node.sy)
        anchor.x2off = max(anchor.x2off, node.offx + node.sx)
        anchor.y2off = max(anchor.y2off, node.offy + node.sy)
    end
    nothing
end

_any_node(node::Node) = true
_is_fixed_node(node::Node) = node.fixed
_is_not_connected_to_fixed(node::Node) = !node.connected_to_fixed

function compute_bounding_box(state::SpringEmbedderState, predicate)
    x1 = Inf; y1 = Inf; x2 = -Inf; y2 = -Inf
    for node in state.nodes
        predicate(node) || continue
        x1 = min(x1, node.x - node.sx)
        y1 = min(y1, node.y - node.sy)
        x2 = max(x2, node.x + node.sx)
        y2 = max(y2, node.y + node.sy)
    end
    (x1, y1, x2, y2)
end

"""
    relax!(state) -> Float64

One iteration, and the largest movement in it.

The movement answered is the largest **signed** velocity component, as in the
original: it is compared against 0.05 to decide when the layout has settled, and
a layout drifting steadily in the negative direction is not what that test is
looking for.
"""
function relax!(state::SpringEmbedderState)
    engine = state.engine

    # Edge attraction: how much longer or shorter each edge is than it wants to
    # be, turned into movement of both of its ends.
    for edge in state.edges
        (edge.source.fixed && edge.target.fixed) && continue
        (edge.source.anchor !== nothing && edge.source.anchor === edge.target.anchor) && continue
        deltax = edge.target.x - edge.source.x
        deltay = edge.target.y - edge.source.y
        dist = sqrt(deltax*deltax + deltay*deltay)
        dist = dist == 0 ? 1.0 : dist
        f = engine.attraction_force * (edge.len - dist) / dist
        vx = f * deltax
        vy = f * deltay
        edge.target.vx += vx
        edge.target.vy += vy
        edge.source.vx -= vx
        edge.source.vy -= vy
    end

    # Nodes push each other apart. Only nodes of the same colour — nodes that are
    # connected — push at any distance; between different colours the push stops
    # after 100 units, so a graph in several pieces does not blow itself apart.
    for node1 in state.nodes
        node1.fixed && continue

        fx = 0.0
        fy = 0.0
        for node2 in state.nodes
            node1 === node2 && continue
            (node1.anchor !== nothing && node1.anchor === node2.anchor) && continue

            deltax = node1.x - node2.x
            deltay = node1.y - node2.y
            distsq = deltax*deltax + deltay*deltay

            if node1.color == node2.color || distsq < 100*100
                if distsq < 1.0
                    # Use 1.0 rather than distsq to avoid dividing by nearly
                    # nothing, and add noise so the two can find a way apart.
                    fx += deltax + _rand01(state) - 0.5
                    fy += deltay + _rand01(state) - 0.5
                else
                    fx += deltax / distsq
                    fy += deltay / distsq
                end
            end
        end

        node1.vx += engine.repulsive_force * fx
        node1.vy += engine.repulsive_force * fy
    end

    bgsize_given = state.width != 0 || state.height != 0

    # Move each node by its velocity, capped at 50 units, and keep it inside the
    # box. The velocity itself is not capped, so a large force keeps pushing.
    maxd = 0.0
    for node in state.nodes
        if node.fixed || node.anchor !== nothing
            # A fixed node does not move, and an anchored one moves with its
            # anchor, below.
        else
            node.x += max(-50.0, min(50.0, node.vx))
            node.y += max(-50.0, min(50.0, node.vy))

            # A node connected to nothing fixed may leave through the top and the
            # left while no box was given; execute! shifts it back at the end.
            let_out = !bgsize_given && !node.connected_to_fixed
            minx2 = let_out ? -100000000.0 : state.minx
            miny2 = let_out ? -100000000.0 : state.miny
            node.x = max(minx2, min(state.maxx, node.x))
            node.y = max(miny2, min(state.maxy, node.y))
        end

        maxd < node.vx && (maxd = node.vx)
        maxd < node.vy && (maxd = node.vy)

        # Friction: a node stops eventually when no force drives it.
        node.vx /= 2
        node.vy /= 2
    end

    # An anchor moves by the average of the movements of the nodes hanging off it.
    for anchor in state.anchors
        anchor.vx = 0.0
        anchor.vy = 0.0
    end
    for node in state.nodes
        anchor = node.anchor
        anchor === nothing && continue
        anchor.vx += node.vx / anchor.refcount
        anchor.vy += node.vy / anchor.refcount
    end

    for anchor in state.anchors
        anchor.x += max(-50.0, min(50.0, anchor.vx))
        anchor.y += max(-50.0, min(50.0, anchor.vy))

        # Back inside the box. Right and bottom first, so that a group too big
        # for the box has its top-left aligned rather than its bottom-right.
        anchor.x + anchor.x2off > state.maxx && (anchor.x = state.maxx - anchor.x2off)
        anchor.y + anchor.y2off > state.maxy && (anchor.y = state.maxy - anchor.y2off)
        anchor.x + anchor.x1off < state.minx && (anchor.x = state.minx - anchor.x1off)
        anchor.y + anchor.y1off < state.miny && (anchor.y = state.miny - anchor.y1off)

        maxd < anchor.vx && (maxd = anchor.vx)
        maxd < anchor.vy && (maxd = anchor.vy)

        anchor.vx /= 2
        anchor.vy /= 2
    end

    # The anchored nodes follow their anchor.
    for node in state.nodes
        anchor = node.anchor
        anchor === nothing && continue
        node.x = anchor.x + node.offx
        node.y = anchor.y + node.offy
        node.vx = anchor.vx
        node.vy = anchor.vy
    end

    maxd
end

# ── The engine interface ─────────────────────────────────────────────────────

function layout_graph(engine::SpringEmbedderLayout, graph::GraphGraph, sizes::Dict,
                      constraints::Vector; extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)

    vertices = layout_vertices(graph)
    n = length(vertices)
    positions = Dict{UInt,NTuple{4,Int}}()
    n == 0 && return (positions, Dict{UInt,Vector{Tuple{Int,Int}}}())

    widths, heights = get_vertex_sizes(vertices, sizes, constraints)
    pins = get_constraint_pins(constraints)
    clusters = get_constraint_clusters(constraints)

    state = SpringEmbedderState(engine)
    set_size!(state, extent === nothing ? 0 : extent[1],
                     extent === nothing ? 0 : extent[2], border)

    for i in 1:n
        id = objectid(vertices[i])
        pin = get(pins, id, nothing)
        cluster = get(clusters, id, nothing)
        if pin !== nothing
            # A pin names a corner; a fixed node is named by its centre.
            add_fixed_node!(state, i, pin[1] + widths[i]/2, pin[2] + heights[i]/2,
                            widths[i], heights[i])
        elseif cluster !== nothing
            add_anchored_node!(state, i, cluster[1], cluster[2], cluster[3],
                               widths[i], heights[i])
        else
            add_movable_node!(state, i, widths[i], heights[i])
        end
    end

    index = Dict{UInt,Int}(objectid(vertices[i]) => i for i in 1:n)
    for k in 1:length(graph.edges)
        edge = graph.edges[k]
        edge isa GraphEdge || continue
        source = get(index, objectid(getfield(edge, :source)[]), 0)
        target = get(index, objectid(getfield(edge, :target)[]), 0)
        (source == 0 || target == 0 || source == target) && continue
        add_edge!(state, source, target)
    end

    execute!(state)

    for i in 1:n
        x, y = node_position(state, i)
        positions[objectid(vertices[i])] =
            (round(Int, x - widths[i]/2), round(Int, y - heights[i]/2),
             round(Int, widths[i]), round(Int, heights[i]))
    end

    (positions, get_straight_routes(graph, positions))
end
