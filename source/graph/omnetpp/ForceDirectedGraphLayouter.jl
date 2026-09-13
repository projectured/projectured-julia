"""
    ForceDirectedGraphLayouterModule

`ForceDirectedLayout`, the port of OMNeT++'s
`src/layout/forcedirectedgraphlayouter.cc`.

This is the layouter Qtenv reaches for below twenty submodules, the one it calls
"advanced". Unlike the spring embedder it **carries node sizes** through every
force, which is what makes it the answer for a network of cards rather than a
network of icons.

What it builds:

1. Expected measures — the average body size decides the edge length everything
   else is scaled against, and whether a body may be treated as a point.
2. Parameters, most of them drawn from the layouter's own seeded generator, so
   one graph under two seeds is two pictures.
3. The connected parts, and, half the time, a pre-embedding per part — a star
   tree if the part is a tree, a heap otherwise — so that the simulation starts
   from an arrangement rather than from noise.
4. Wall bodies, when there is a box to fill or anything pinned, with a repulsion
   from every body and a spring holding opposite walls apart.
5. An electric repulsion between every pair of bodies, weakened to a finite
   range between parts that are not connected.
6. A drag, and a spring pulling the third dimension flat, when the layout was
   allowed to leave the plane at all.

Then it integrates until the layout settles, and shifts the result so that
nothing has a negative coordinate.
"""
module ForceDirectedGraphLayouterModule

import ..GraphModule: GraphGraph, GraphEdge
import ..GraphLayoutEngineModule: GraphLayoutEngine, layout_graph, layout_engine_name,
                                  get_supported_constraint_kinds, check_constraints,
                                  get_constraint_pins, get_constraint_clusters,
                                  layout_vertices, get_vertex_sizes, get_straight_routes
import ..LcgRandomModule: LcgRandom, draw_uniform01!, draw_uniform!
import ..LayoutGeometryModule: Pt, Rs, Rc, pt_nil, pt_multiply,
                               get_diagonal_length, get_area, rc_center
import ..GraphComponentModule: GraphComponent, LayoutVertex, LayoutEdge,
                               add_vertex!, add_edge!, get_vertex_count,
                               get_edge_count, get_bounding_rectangle,
                               calculate_spanning_tree!,
                               calculate_connected_sub_components!
import ..ForceDirectedParametersBaseModule: Variable, PointConstrainedVariable, AbstractBody,
                                            get_position, assign_position!,
                                            get_body_position, get_body_size, get_body_top,
                                            get_body_bottom, get_body_left, get_body_right,
                                            get_body_variable
import ..ForceDirectedParametersModule: Body, RelativelyPositionedBody, WallBody,
                                        set_wall_position!, set_wall_variable!,
                                        ElectricRepulsion, VerticalElectricRepulsion,
                                        HorizontalElectricRepulsion, Spring,
                                        VerticalSpring, HorizontalSpring,
                                        BasePlaneSpring, Drag
import ..ForceDirectedEmbeddingModule: ForceDirectedEmbedding,
                                       default_force_directed_parameters,
                                       add_body!, add_force_provider!, embed!,
                                       get_embedding_bounding_rectangle
import ..StarTreeEmbeddingModule: StarTreeEmbedding, embed_star_tree!
import ..HeapEmbeddingModule: HeapEmbedding, embed_heap!

export ForceDirectedLayout

# ── The engine ───────────────────────────────────────────────────────────────

"""
    ForceDirectedLayout(; seed = 1, max_cycle = 1000, max_calculation_time = Inf,
                        three_d = true, pre_embedding = true)

The advanced layouter, with OMNeT++'s own constants.

`seed` decides the picture. Most of the parameters — the spring coefficient, the
repulsion coefficient, the friction, whether to pre-embed, how far into the
third dimension to go — are drawn from a generator of this seed, exactly as the
original draws them.

`max_calculation_time` is in milliseconds and is `Inf` here, where OMNeT++ draws
a random 1000 to 20000. A wall-clock limit makes a drawing depend on the machine
that drew it, and the interface here promises that a seed and a graph decide a
picture. Set it if you would rather have a bounded wait than a repeatable
answer; `max_cycle` bounds the work either way.

`three_d` and `pre_embedding` force the two choices the original leaves to the
seed. `nothing` keeps the original's coin toss.

**What it costs.** Every cycle asks for a force between every pair of bodies,
four times, so the cost grows with the square of the vertex count. Measured by
`graphlayoutbench` on a sparse network-shaped graph: 10 vertices in about 5
milliseconds, 60 in 0.55 seconds, 300 in 41 seconds. That is why Qtenv stops
using it at twenty submodules and why [`DeferredLayout`](@ref) does too. Name it
directly for a large graph only if you mean to wait, or give it a
`max_calculation_time`.

It implements `:pin` (a point-constrained variable, free only in the third
dimension), `:cluster` (bodies sharing one variable at fixed offsets) and
`:fixed_size`.
"""
struct ForceDirectedLayout <: GraphLayoutEngine
    seed::Int32
    max_cycle::Int
    max_calculation_time::Float64
    three_d::Union{Nothing,Bool}
    pre_embedding::Union{Nothing,Bool}
end

ForceDirectedLayout(; seed::Integer = 1, max_cycle::Integer = 1000,
                    max_calculation_time::Real = Inf,
                    three_d::Union{Nothing,Bool} = nothing,
                    pre_embedding::Union{Nothing,Bool} = nothing) =
    ForceDirectedLayout(Int32(seed), Int(max_cycle), Float64(max_calculation_time),
                        three_d, pre_embedding)

get_supported_constraint_kinds(::ForceDirectedLayout) = (:pin, :fixed_size, :cluster)
layout_engine_name(::ForceDirectedLayout) = :force_directed

# ── The layouter's own state ─────────────────────────────────────────────────

mutable struct ForceDirectedState
    engine::ForceDirectedLayout
    random::LcgRandom
    embedding::ForceDirectedEmbedding
    graph_component::GraphComponent
    width::Float64          # 0 means unspecified
    height::Float64
    border::Float64

    has_movable_node::Bool
    has_fixed_node::Bool
    has_anchored_node::Bool
    has_edge_to_border::Bool

    three_d_factor::Float64
    three_d_coefficient::Float64
    pre_embedding::Bool
    force_directed_embedding::Bool

    expected_embedding_width::Float64
    expected_embedding_height::Float64
    expected_edge_length::Float64
    slippery::Bool
    point_like_distance::Bool

    top_border::Union{Nothing,WallBody}
    bottom_border::Union{Nothing,WallBody}
    left_border::Union{Nothing,WallBody}
    right_border::Union{Nothing,WallBody}

    anchor_variables::Dict{Any,Variable}
    node_bodies::Dict{Int,AbstractBody}
    # `GraphComponent::findVertex` is a linear scan, and the repulsion loop asks
    # it twice per pair of bodies, which is cubic. The answer never changes once
    # a vertex is added, so it is remembered here instead.
    variable_vertices::IdDict{Variable,LayoutVertex}
end

ForceDirectedState(engine::ForceDirectedLayout) =
    ForceDirectedState(engine, LcgRandom(engine.seed), ForceDirectedEmbedding(),
                       GraphComponent(), 0.0, 0.0, 0.0,
                       false, false, false, false,
                       0.0, 0.0, false, true,
                       -1.0, -1.0, -1.0, false, true,
                       nothing, nothing, nothing, nothing,
                       Dict{Any,Variable}(), Dict{Int,AbstractBody}(),
                       IdDict{Variable,LayoutVertex}())

# Add a vertex to the working graph and remember which variable it stands for.
function add_layout_vertex!(state::ForceDirectedState, vertex::LayoutVertex)
    add_vertex!(state.graph_component, vertex)
    vertex.identity isa Variable && (state.variable_vertices[vertex.identity] = vertex)
    vertex
end

vertex_for(state::ForceDirectedState, variable) =
    variable isa Variable ? get(state.variable_vertices, variable, nothing) : nothing

_rand01(state::ForceDirectedState) = draw_uniform01!(state.random)
_uniform(state::ForceDirectedState, a::Real, b::Real) = draw_uniform!(state.random, a, b)

function set_size!(state::ForceDirectedState, width::Real, height::Real, border::Real)
    if (width != 0 && width < 2*border) || (height != 0 && height < 2*border)
        throw(ArgumentError(
            "ForceDirectedLayout: the extent $((width, height)) is smaller than " *
            "twice the border $border."))
    end
    state.width = Float64(width)
    state.height = Float64(height)
    state.border = Float64(border)
    nothing
end

add_node_body!(state::ForceDirectedState, node_id::Int, body::AbstractBody) =
    (add_body!(state.embedding, body); state.node_bodies[node_id] = body; nothing)

find_node_body(state::ForceDirectedState, node_id::Int) = get(state.node_bodies, node_id, nothing)

ensure_anchor_variable!(state::ForceDirectedState, name) =
    get!(() -> Variable(pt_nil()), state.anchor_variables, name)

function add_movable_node!(state::ForceDirectedState, node_id::Int, width::Real, height::Real)
    state.has_movable_node = true
    variable = Variable(pt_nil())
    add_node_body!(state, node_id, Body(variable, Rs(width, height)))
    add_layout_vertex!(state, LayoutVertex(pt_nil(), Rs(width, height), variable))
    nothing
end

# A pinned node is a variable constrained to a point: it cannot move in the
# plane, and it may still travel through the third dimension so the rest of the
# graph can untangle around it.
function add_fixed_node!(state::ForceDirectedState, node_id::Int, x::Real, y::Real,
                         width::Real, height::Real)
    state.has_fixed_node = true
    ensure_borders!(state)
    variable = PointConstrainedVariable(Pt(x, y, NaN))
    add_node_body!(state, node_id, Body(variable, Rs(width, height)))
    add_layout_vertex!(state,
                       LayoutVertex(Pt(x - width/2, y - height/2, NaN), Rs(width, height), variable))
    nothing
end

function add_anchored_node!(state::ForceDirectedState, node_id::Int, anchor_name,
                            offx::Real, offy::Real, width::Real, height::Real)
    state.has_anchored_node = true
    variable = ensure_anchor_variable!(state, anchor_name)
    add_node_body!(state, node_id,
                   RelativelyPositionedBody(variable, Pt(offx, offy, 0), Rs(width, height)))

    # The anchor gets one vertex in the working graph, sized to hold everything
    # hanging off it.
    vertex = vertex_for(state, variable)
    if vertex === nothing
        add_layout_vertex!(state,
                           LayoutVertex(pt_nil(), Rs(offx + width/2, offy + height/2), variable))
    else
        vertex.rc = Rc(vertex.rc.pt, Rs(max(vertex.rc.rs.width, offx + width/2),
                                        max(vertex.rc.rs.height, offy + height/2)))
    end
    nothing
end

function add_edge_between!(state::ForceDirectedState, source_id::Int, target_id::Int,
                           len::Real = 0)
    source = find_node_body(state, source_id)
    target = find_node_body(state, target_id)
    (source === nothing || target === nothing) && return nothing
    # -1 means "use the expected edge length", which is only known later.
    spring = Spring(source, target, -1, len > 0 ? len : -1)
    add_force_provider!(state.embedding, spring)
    source_vertex = vertex_for(state, get_body_variable(source))
    target_vertex = vertex_for(state, get_body_variable(target))
    (source_vertex === nothing || target_vertex === nothing) && return nothing
    add_edge!(state.graph_component, LayoutEdge(source_vertex, target_vertex))
    nothing
end

# ── Setting up ───────────────────────────────────────────────────────────────

function calculate_expected_measures!(state::ForceDirectedState)
    bodies = state.embedding.bodies
    count = 0
    max_body_length = 0.0
    expected_size = 0.0
    average_body_length = 0.0

    for body in bodies
        body isa WallBody && continue
        length = get_diagonal_length(get_body_size(body))
        count += 1
        max_body_length = max(max_body_length, length)
        average_body_length += length
        expected_size += get_area(get_body_size(body))
    end
    count == 0 && return nothing

    average_body_length /= count
    # Treat bodies as points when none of them is much bigger than the rest; it
    # makes every distance cheaper to compute.
    state.point_like_distance = max_body_length < 2 * average_body_length

    # Integer division, because it is integer division over there: `2400` and
    # `20 + bodies.size()` are both integral in C++, so the quotient is
    # truncated before it is widened to a double. Eight bodies give 105 rather
    # than 105.714, and every length in the layout is measured against this one.
    minimum_edge_length = 20 + div(2400, 20 + length(bodies))
    state.expected_edge_length = state.point_like_distance ?
        minimum_edge_length + average_body_length : minimum_edge_length

    expected_size += 2 * state.expected_edge_length^2 * length(bodies)
    expected_size = sqrt(expected_size)
    state.expected_embedding_width =
        state.width != 0 ? state.width : expected_size + 2*state.border
    state.expected_embedding_height =
        state.height != 0 ? state.height : expected_size + 2*state.border
    nothing
end

# The draws below happen in this order in the original, and the order is part of
# the picture: change it and every seeded layout moves.
function set_parameters!(state::ForceDirectedState)
    engine = state.engine
    parameters = default_force_directed_parameters(state.random.seed)
    state.embedding.parameters = parameters

    parameters.default_slippery = state.slippery
    parameters.default_point_like_distance = state.point_like_distance
    parameters.default_spring_coefficient = _uniform(state, 0.1, 1)
    parameters.default_spring_repose_length =
        _uniform(state, state.expected_edge_length / 2, state.expected_edge_length)
    parameters.electric_repulsion_coefficient = _uniform(state, 10000, 100000)
    parameters.friction_coefficient = _uniform(state, 1, 5)
    parameters.velocity_relax_limit = 0.2
    parameters.max_calculation_time = engine.max_calculation_time
    parameters.max_cycle = engine.max_cycle

    # OMNeT++ draws `mct` here as uniform(1000, 20000). The draw is kept so the
    # sequence stays in step, and the value is dropped: see the engine's docs.
    _uniform(state, 1000, 20000)

    three_d = _rand01(state) < 0.5 ? 0.0 : _uniform(state, 0, 1)
    state.three_d_factor = engine.three_d === nothing ? three_d :
                           (engine.three_d ? max(three_d, 0.5) : 0.0)
    state.three_d_coefficient = _uniform(state, 0, 10)

    pre_embedding = _rand01(state) < 0.5
    state.pre_embedding = engine.pre_embedding === nothing ? pre_embedding : engine.pre_embedding
    state.force_directed_embedding = true
    nothing
end

function set_random_positions!(state::ForceDirectedState)
    for variable in state.embedding.variables
        pt = get_position(variable)
        x = isnan(pt.x) ? _uniform(state, state.border,
                                   state.expected_embedding_width - state.border) : pt.x
        y = isnan(pt.y) ? _uniform(state, state.border,
                                   state.expected_embedding_height - state.border) : pt.y
        z = isnan(pt.z) ?
            (_rand01(state) - 0.5) *
                sqrt(state.expected_embedding_width * state.expected_embedding_height) *
                state.three_d_factor : pt.z
        assign_position!(variable, Pt(x, y, z))
    end
    nothing
end

function ensure_borders!(state::ForceDirectedState)
    if state.top_border === nothing &&
       (state.height != 0 || state.has_fixed_node || state.has_edge_to_border)
        state.top_border = WallBody(true)
        state.bottom_border = WallBody(true)
    end
    if state.left_border === nothing &&
       (state.width != 0 || state.has_fixed_node || state.has_edge_to_border)
        state.left_border = WallBody(false)
        state.right_border = WallBody(false)
    end
    nothing
end

function add_border_force_providers!(state::ForceDirectedState)
    for body in copy(state.embedding.bodies)
        if state.top_border !== nothing
            add_force_provider!(state.embedding, VerticalElectricRepulsion(state.top_border, body))
            add_force_provider!(state.embedding, VerticalElectricRepulsion(state.bottom_border, body))
        end
        if state.left_border !== nothing
            add_force_provider!(state.embedding, HorizontalElectricRepulsion(state.left_border, body))
            add_force_provider!(state.embedding, HorizontalElectricRepulsion(state.right_border, body))
        end
    end

    if state.top_border !== nothing
        set_wall_variable!(state.top_border,
            state.has_fixed_node || state.height != 0 ?
                PointConstrainedVariable(Pt(NaN, 0, NaN)) : Variable(pt_nil()))
        set_wall_variable!(state.bottom_border,
            state.height != 0 ? PointConstrainedVariable(Pt(NaN, state.height, NaN)) :
                                Variable(pt_nil()))
        add_body!(state.embedding, state.top_border)
        add_body!(state.embedding, state.bottom_border)
        state.height == 0 && add_force_provider!(state.embedding,
            VerticalSpring(state.top_border, state.bottom_border, -1,
                           state.expected_embedding_height))
    end
    if state.left_border !== nothing
        set_wall_variable!(state.left_border,
            state.has_fixed_node || state.width != 0 ?
                PointConstrainedVariable(Pt(0, NaN, NaN)) : Variable(pt_nil()))
        set_wall_variable!(state.right_border,
            state.width != 0 ? PointConstrainedVariable(Pt(state.width, NaN, NaN)) :
                               Variable(pt_nil()))
        add_body!(state.embedding, state.left_border)
        add_body!(state.embedding, state.right_border)
        state.width == 0 && add_force_provider!(state.embedding,
            HorizontalSpring(state.left_border, state.right_border, -1,
                             state.expected_embedding_width))
    end
    nothing
end

function set_border_positions!(state::ForceDirectedState)
    distance = 100.0
    top = floatmax(Float64); bottom = floatmin(Float64)
    left = floatmax(Float64); right = floatmin(Float64)

    if state.width == 0 || state.height == 0
        for body in state.embedding.bodies
            body isa WallBody && continue
            if state.height == 0
                top = min(top, get_body_top(body))
                bottom = max(bottom, get_body_bottom(body))
            end
            if state.width == 0
                left = min(left, get_body_left(body))
                right = max(right, get_body_right(body))
            end
        end
    end

    if state.top_border !== nothing
        set_wall_position!(state.top_border,
                           state.has_fixed_node || state.height != 0 ? 0.0 : top - distance)
        set_wall_position!(state.bottom_border,
                           state.height != 0 ? state.height : bottom + distance)
    end
    if state.left_border !== nothing
        set_wall_position!(state.left_border,
                           state.has_fixed_node || state.width != 0 ? 0.0 : left - distance)
        set_wall_position!(state.right_border,
                           state.width != 0 ? state.width : right + distance)
    end
    nothing
end

# Two bodies in different connected parts repel only over a finite range, so
# parts that share no edge settle at a readable distance instead of flying apart.
function add_electric_repulsions!(state::ForceDirectedState)
    bodies = copy(state.embedding.bodies)
    for i in 1:length(bodies), j in (i+1):length(bodies)
        body1 = bodies[i]; body2 = bodies[j]
        (body1 isa WallBody || body2 isa WallBody) && continue
        variable1 = get_body_variable(body1); variable2 = get_body_variable(body2)
        variable1 === variable2 && continue

        vertex1 = vertex_for(state, variable1)
        vertex2 = vertex_for(state, variable2)
        (vertex1 === nothing || vertex2 === nothing) && continue

        if vertex1.connected_sub_component !== vertex2.connected_sub_component
            add_force_provider!(state.embedding,
                ElectricRepulsion(body1, body2, state.expected_edge_length / 2,
                                  state.expected_edge_length))
        else
            add_force_provider!(state.embedding, ElectricRepulsion(body1, body2))
        end
    end
    nothing
end

function add_base_plane_springs!(state::ForceDirectedState)
    for body in copy(state.embedding.bodies)
        body isa WallBody && continue
        add_force_provider!(state.embedding, BasePlaneSpring(body, state.three_d_coefficient, 0))
    end
    nothing
end

# A scale and a translate both go through assign_position!, so a pinned variable
# keeps its coordinates: the caller named them and no later pass may rewrite
# them. That is the original's behaviour, and it is why assignPosition is
# virtual there.
scale_embedding!(state::ForceDirectedState, pt::Pt) =
    (for variable in state.embedding.variables
         assign_position!(variable, pt_multiply(get_position(variable), pt))
     end; nothing)

translate_embedding!(state::ForceDirectedState, pt::Pt) =
    (for variable in state.embedding.variables
         assign_position!(variable, get_position(variable) + pt)
     end; nothing)

# Pre-embed every connected part on its own, then treat each part as one vertex
# of a star and heap-embed that, so the parts do not land on top of each other.
function execute_pre_embedding!(state::ForceDirectedState)
    children_star = GraphComponent()
    star_root = nothing

    for child in state.graph_component.connected_sub_components
        calculate_spanning_tree!(child)

        if get_vertex_count(child) == get_edge_count(child) + 1 || _rand01(state) < 0.5
            embed_star_tree!(StarTreeEmbedding(child, state.expected_edge_length))
        else
            embed_heap!(HeapEmbedding(child, state.expected_edge_length))
        end

        child_vertex = LayoutVertex(pt_nil(), get_bounding_rectangle(child).rs, nothing)
        star_root === nothing && (star_root = child_vertex)
        add_vertex!(children_star, child_vertex)
        add_edge!(children_star, LayoutEdge(star_root, child_vertex))
    end

    calculate_spanning_tree!(children_star)
    embed_heap!(HeapEmbedding(children_star, state.expected_edge_length))

    for i in 1:length(state.graph_component.connected_sub_components)
        child_vertex = children_star.vertices[i]
        child = state.graph_component.connected_sub_components[i]
        for vertex in child.vertices
            variable = vertex.identity
            variable isa Variable || continue
            pt = rc_center(vertex.rc) + child_vertex.rc.pt
            assign_position!(variable, Pt(pt.x, pt.y, NaN))
        end
    end

    rc = get_bounding_box(state)
    translate_embedding!(state, Pt(-rc.pt.x, -rc.pt.y, 0))

    scalex = state.width / rc.rs.width
    scaley = state.height / rc.rs.height
    for body in state.embedding.bodies
        body isa WallBody && continue
        scalex = min(scalex, (state.width - state.border - get_body_size(body).width) / get_body_left(body))
        scaley = min(scaley, (state.height - state.border - get_body_size(body).height) / get_body_top(body))
    end

    scale_embedding!(state, Pt(state.width > 0 && scalex > 0 ? scalex : 1,
                               state.height > 0 && scaley > 0 ? scaley : 1,
                               NaN))
    rc = get_bounding_box(state)
    translate_embedding!(state, Pt(-rc.pt.x + state.border, -rc.pt.y + state.border, 0))
    nothing
end

get_bounding_box(state::ForceDirectedState) = get_embedding_bounding_rectangle(state.embedding)

function execute!(state::ForceDirectedState)
    (state.has_movable_node || state.has_anchored_node) || return nothing

    calculate_expected_measures!(state)
    set_parameters!(state)

    calculate_connected_sub_components!(state.graph_component)

    state.pre_embedding && execute_pre_embedding!(state)

    if state.force_directed_embedding
        (state.width != 0 || state.height != 0) && ensure_borders!(state)
        (state.top_border !== nothing || state.left_border !== nothing) &&
            add_border_force_providers!(state)

        add_electric_repulsions!(state)
        state.three_d_factor > 0 && add_base_plane_springs!(state)
        add_force_provider!(state.embedding, Drag())

        set_random_positions!(state)
        (state.top_border !== nothing || state.left_border !== nothing) &&
            set_border_positions!(state)

        _reinitialize_embedding!(state)
        embed!(state.embedding)

        rc = get_bounding_box(state)
        translate_embedding!(state,
            Pt(state.has_fixed_node || state.width != 0 ? 0 : -rc.pt.x + state.border,
               state.has_fixed_node || state.height != 0 ? 0 : -rc.pt.y + state.border, 0))
    end

    state.pre_embedding || state.force_directed_embedding || set_random_positions!(state)
    nothing
end

_reinitialize_embedding!(state::ForceDirectedState) =
    (state.embedding.initialized = false; nothing)

node_position(state::ForceDirectedState, node_id::Int) =
    let body = find_node_body(state, node_id)
        body === nothing ? (0.0, 0.0) :
            let pt = get_body_position(body); (pt.x, pt.y) end
    end

# ── The engine interface ─────────────────────────────────────────────────────

function layout_graph(engine::ForceDirectedLayout, graph::GraphGraph, sizes::Dict,
                      constraints::Vector; extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)

    vertices = layout_vertices(graph)
    n = length(vertices)
    positions = Dict{UInt,NTuple{4,Int}}()
    n == 0 && return (positions, Dict{UInt,Vector{Tuple{Int,Int}}}())

    widths, heights = get_vertex_sizes(vertices, sizes, constraints)
    pins = get_constraint_pins(constraints)
    clusters = get_constraint_clusters(constraints)

    state = ForceDirectedState(engine)
    set_size!(state, extent === nothing ? 0 : extent[1],
                     extent === nothing ? 0 : extent[2], border)

    for i in 1:n
        id = objectid(vertices[i])
        pin = get(pins, id, nothing)
        cluster = get(clusters, id, nothing)
        if pin !== nothing
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
        add_edge_between!(state, source, target)
    end

    execute!(state)

    for i in 1:n
        x, y = node_position(state, i)
        isfinite(x) || (x = 0.0)
        isfinite(y) || (y = 0.0)
        positions[objectid(vertices[i])] =
            (round(Int, x - widths[i]/2), round(Int, y - heights[i]/2),
             round(Int, widths[i]), round(Int, heights[i]))
    end

    (positions, get_straight_routes(graph, positions))
end

end # module
