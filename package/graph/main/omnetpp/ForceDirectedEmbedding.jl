"""
    ForceDirectedEmbeddingModule

The solver, from OMNeT++'s `src/layout/forcedirectedembedding.cc`.

The layout is a differential equation: a variable's value is a position, its
first derivative a velocity, its second an acceleration, and the forces say what
the acceleration is. It is integrated by a modified Runge-Kutta of fourth order:

```
a1 = a[pn, vn]
a2 = a[pn + h/2 * vn + h*h/8 * a1, vn + h/2 * a1]
a3 = a[pn + h/2 * vn + h*h/8 * a2, vn + h/2 * a2]
a4 = a[pn + h   * vn + h*h/2 * a3, vn + h   * a3]

pn+1 = pn + h * vn + h*h/6 * (a1 + a2 + a3)
vn+1 = vn + h/6 * (a1 + 2*a2 + 2*a3 + a4)
```

The step `h` is not fixed. The four acceleration estimates should agree; how far
apart they are is the error, and the step is doubled while the error is too
small and halved while it is too large. That is why a graph that is nearly
settled advances in long steps and a graph in a violent phase advances in short
ones, at about the same cost per cycle.

**One deviation.** OMNeT++ also stops on elapsed wall-clock time, which makes
the drawing depend on the machine that drew it. `max_calculation_time` is here
and honoured, but `ForceDirectedLayout` leaves it at `Inf`; §3.6 of the plan
requires that a seed and a graph decide a picture, and a clock is neither.
"""
module ForceDirectedEmbeddingModule

import ..LayoutGeometryModule: Pt, Rs, Rc, pt_zero, pt_length, pt_distance,
                               pt_normalize
import ..ForceDirectedParametersBaseModule: ForceDirectedParameters, Variable,
                                            IBody, IForceProvider,
                                            reinitialize!, apply_forces!, potential_energy,
                                            set_embedding!, get_position, assign_position!,
                                            get_velocity, assign_velocity!,
                                            get_acceleration, kinetic_energy, reset_force!,
                                            get_mass, set_mass!, reset_force!,
                                            body_variable, body_mass,
                                            body_left, body_right, body_top, body_bottom
import ..ForceDirectedParametersModule: WallBody
import ..LcgRandomModule: LcgRandom, next01!

export ForceDirectedEmbedding, default_force_directed_parameters,
       add_body!, add_force_provider!, embed!, embedding_bounding_rectangle,
       total_kinetic_energy, total_potential_energy

"""
    ForceDirectedEmbedding()

The solver and everything it solves for. Add bodies and force providers, call
[`embed!`](@ref) until `finished`, and read the positions off the variables.
"""
mutable struct ForceDirectedEmbedding
    parameters::ForceDirectedParameters
    initialized::Bool
    finished::Bool
    cycle::Int
    probe_cycle::Int
    "Virtual time: the sum of the accepted time steps."
    elapsed_time::Float64
    "Wall-clock milliseconds since the run started."
    elapsed_calculation_time::Float64
    kinetic_energy_sum::Float64
    total_mass::Float64
    last_acceleration_error::Float64
    last_max_velocity::Float64
    last_max_acceleration::Float64
    "0 at the start and 1 when settled. `BasePlaneSpring` reads it."
    relax_factor::Float64
    updated_time_step::Float64

    pn::Vector{Pt}      # positions
    vn::Vector{Pt}      # velocities
    an::Vector{Pt}      # accelerations
    a1::Vector{Pt}
    a2::Vector{Pt}
    a3::Vector{Pt}
    a4::Vector{Pt}
    dpn::Vector{Pt}
    tpn::Vector{Pt}
    dvn::Vector{Pt}
    tvn::Vector{Pt}

    variables::Vector{Variable}
    force_providers::Vector{IForceProvider}
    bodies::Vector{IBody}
end

ForceDirectedEmbedding() =
    ForceDirectedEmbedding(default_force_directed_parameters(), false, false, 0, 0,
                           0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                           Pt[], Pt[], Pt[], Pt[], Pt[], Pt[], Pt[],
                           Pt[], Pt[], Pt[], Pt[],
                           Variable[], IForceProvider[], IBody[])

"""
    default_force_directed_parameters(seed = 1) -> ForceDirectedParameters

The defaults, four of which are drawn from a generator of this seed's own: the
spring coefficient, the repulsion coefficient, the friction and the calculation
time limit. That is deliberate — one graph laid out under two seeds is two
different-looking pictures, and the caller picks the one it likes.

`max_calculation_time` is `Inf` here and a random 1000 to 10000 milliseconds
over there, so that a picture does not depend on how fast the machine is.
"""
function default_force_directed_parameters(seed::Integer = 1)
    random = LcgRandom(seed)
    ForceDirectedParameters(
        Rs(10, 10),                          # default_body_size
        10.0,                                # default_body_mass
        1.0,                                 # default_body_charge
        0.1 + 0.9 * next01!(random),         # default_spring_coefficient
        50.0,                                # default_spring_repose_length
        10000 + 90000 * next01!(random),     # electric_repulsion_coefficient
        -1.0,                                # default_electric_repulsion_linearity_distance
        -1.0,                                # default_electric_repulsion_max_distance
        1 + 4 * next01!(random),             # friction_coefficient
        false,                               # default_slippery
        false,                               # default_point_like_distance
        1.0,                                 # time_step
        0.0,                                 # min_time_step
        floatmax(Float64),                   # max_time_step
        2.0,                                 # time_step_multiplier
        0.2,                                 # min_acceleration_error
        0.5,                                 # max_acceleration_error
        0.2,                                 # velocity_relax_limit
        1.0,                                 # acceleration_relax_limit
        1000.0,                              # default_max_force
        100.0,                               # max_velocity
        1000,                                # max_cycle
        Inf)                                 # max_calculation_time
end

"""
    add_body!(embedding, body)

Add a body, and its variable if that variable is new. Several bodies may share
one variable; the variable is added once and carries the sum of their masses.
"""
function add_body!(embedding::ForceDirectedEmbedding, body::IBody)
    push!(embedding.bodies, body)
    set_embedding!(body, embedding)
    variable = body_variable(body)
    if variable !== nothing && !any(v -> v === variable, embedding.variables)
        push!(embedding.variables, variable)
    end
    nothing
end

function add_force_provider!(embedding::ForceDirectedEmbedding, provider::IForceProvider)
    push!(embedding.force_providers, provider)
    set_embedding!(provider, embedding)
    nothing
end

total_kinetic_energy(embedding::ForceDirectedEmbedding) =
    sum(kinetic_energy, embedding.variables; init = 0.0)

total_potential_energy(embedding::ForceDirectedEmbedding) =
    sum(potential_energy, embedding.force_providers; init = 0.0)

"Clear every result of an earlier run and set the initial values."
function reinitialize!(embedding::ForceDirectedEmbedding)
    embedding.initialized = true
    embedding.finished = false
    embedding.relax_factor = 0.0
    embedding.cycle = 0
    embedding.probe_cycle = 0
    embedding.elapsed_time = 0.0
    embedding.elapsed_calculation_time = 0.0
    embedding.kinetic_energy_sum = 0.0
    embedding.total_mass = 0.0

    count = length(embedding.variables)
    zeros_of(count) = [pt_zero() for _ in 1:count]
    embedding.pn = zeros_of(count); embedding.vn = zeros_of(count)
    embedding.an = zeros_of(count); embedding.a1 = zeros_of(count)
    embedding.a2 = zeros_of(count); embedding.a3 = zeros_of(count)
    embedding.a4 = zeros_of(count); embedding.dpn = zeros_of(count)
    embedding.tpn = zeros_of(count); embedding.dvn = zeros_of(count)
    embedding.tvn = zeros_of(count)

    for variable in embedding.variables
        reinitialize!(variable)
    end
    for provider in embedding.force_providers
        reinitialize!(provider)
    end
    for body in embedding.bodies
        reinitialize!(body)
    end

    for i in 1:count
        variable = embedding.variables[i]
        embedding.pn[i] = get_position(variable)
        embedding.vn[i] = get_velocity(variable)
        mass = 0.0
        for body in embedding.bodies
            body_variable(body) === variable && (mass += body_mass(body))
        end
        set_mass!(variable, mass)
        embedding.total_mass += mass
    end

    embedding.updated_time_step = embedding.parameters.time_step
    nothing
end

# an = a[pn, vn]: put the positions and velocities in, ask every force provider
# for its forces, and read the accelerations out.
function accelerations!(embedding::ForceDirectedEmbedding, an::Vector{Pt},
                        pn::Vector{Pt}, vn::Vector{Pt})
    for i in 1:length(embedding.variables)
        variable = embedding.variables[i]
        assign_position!(variable, pn[i])
        assign_velocity!(variable, vn[i])
        reset_force!(variable)
    end
    for provider in embedding.force_providers
        apply_forces!(provider)
    end
    for i in 1:length(embedding.variables)
        an[i] = get_acceleration(embedding.variables[i])
    end
    nothing
end

# The average distance between consecutive acceleration estimates, relative to
# how large they are. This is the error the time step chases.
function average_relative_error(a1, a2, a3, a4)
    sum1 = 0.0
    sum2 = 0.0
    for i in 1:length(a1)
        sum1 += pt_distance(a1[i], a2[i])
        sum1 += pt_distance(a2[i], a3[i])
        sum1 += pt_distance(a3[i], a4[i])
        sum2 += pt_length(a1[i]) + pt_length(a2[i]) + pt_length(a3[i]) + pt_length(a4[i])
    end
    sum1 /= length(a1) * 3
    sum2 /= length(a1) * 4
    sum2 == 0 ? 0.0 : sum1 / sum2
end

add_multiplied!(pts, a, b::Real, c) =
    (for i in 1:length(pts); pts[i] = c[i] * b + a[i]; end; nothing)
increment_with_multiplied!(pts, a::Real, b) =
    (for i in 1:length(pts); pts[i] = pts[i] + b[i] * a; end; nothing)
add_into!(pts, a, b) = (for i in 1:length(pts); pts[i] = a[i] + b[i]; end; nothing)
increment!(pts, a) = (for i in 1:length(pts); pts[i] = pts[i] + a[i]; end; nothing)
multiply!(pts, a::Real) = (for i in 1:length(pts); pts[i] = pts[i] * a; end; nothing)

"""
    embed!(embedding)

Run cycles until the layout settles, the cycle cap is reached, or the
calculation time runs out. `finished` says which.
"""
function embed!(embedding::ForceDirectedEmbedding)
    embedding.finished && return nothing
    embedding.initialized || reinitialize!(embedding)
    isempty(embedding.variables) && (embedding.finished = true; return nothing)

    parameters = embedding.parameters
    # A wall clock is read only when the caller asked for a wall-clock cap.
    # Leaving `max_calculation_time` at `Inf` is what keeps a layout repeatable,
    # so the common path never calls `time`.
    timed = isfinite(parameters.max_calculation_time)
    began = timed ? time() : 0.0
    elapsed_ms() = timed ? (time() - began) * 1000 : 0.0

    while !embedding.finished
        h_multiplier = 0.0
        embedding.cycle += 1
        next_updated_time_step = Inf

        # Find a time step whose four acceleration estimates agree well enough.
        while true
            embedding.probe_cycle += 1
            embedding.elapsed_calculation_time = elapsed_ms()
            embedding.elapsed_calculation_time > parameters.max_calculation_time && break

            h = embedding.updated_time_step
            accelerations!(embedding, embedding.a1, embedding.pn, embedding.vn)

            add_multiplied!(embedding.tpn, embedding.pn, h/2, embedding.vn)
            increment_with_multiplied!(embedding.tpn, h*h/8, embedding.a1)
            add_multiplied!(embedding.tvn, embedding.vn, h/2, embedding.a1)
            accelerations!(embedding, embedding.a2, embedding.tpn, embedding.tvn)

            add_multiplied!(embedding.tpn, embedding.pn, h/2, embedding.vn)
            increment_with_multiplied!(embedding.tpn, h*h/8, embedding.a2)
            add_multiplied!(embedding.tvn, embedding.vn, h/2, embedding.a2)
            accelerations!(embedding, embedding.a3, embedding.tpn, embedding.tvn)

            add_multiplied!(embedding.tpn, embedding.pn, h, embedding.vn)
            increment_with_multiplied!(embedding.tpn, h*h/2, embedding.a3)
            add_multiplied!(embedding.tvn, embedding.vn, h, embedding.a3)
            accelerations!(embedding, embedding.a4, embedding.tpn, embedding.tvn)

            embedding.last_acceleration_error =
                average_relative_error(embedding.a1, embedding.a2, embedding.a3, embedding.a4)

            embedding.last_acceleration_error == 0 && break

            # Both the error and the step are in range: keep this step.
            if parameters.min_acceleration_error < embedding.last_acceleration_error <
                   parameters.max_acceleration_error &&
               parameters.min_time_step < embedding.updated_time_step <
                   parameters.max_time_step
                break
            end

            if embedding.last_acceleration_error < parameters.max_acceleration_error
                # Too accurate: try a longer step, unless we just shortened one,
                # in which case we would oscillate.
                if h_multiplier == 0
                    h_multiplier = parameters.time_step_multiplier
                elseif h_multiplier == 1 / parameters.time_step_multiplier
                    break
                end
            else
                if h_multiplier == 0 || h_multiplier == parameters.time_step_multiplier
                    h_multiplier = 1 / parameters.time_step_multiplier
                end
            end

            next_updated_time_step = embedding.updated_time_step * h_multiplier
            (next_updated_time_step < parameters.min_time_step ||
             parameters.max_time_step < next_updated_time_step) && break

            embedding.updated_time_step = next_updated_time_step
        end

        h = embedding.updated_time_step

        # pn+1 = pn + h * vn + h*h/6 * (a1 + a2 + a3)
        add_into!(embedding.dpn, embedding.a1, embedding.a2)
        increment!(embedding.dpn, embedding.a3)
        multiply!(embedding.dpn, h*h/6)
        increment_with_multiplied!(embedding.dpn, h, embedding.vn)
        increment!(embedding.pn, embedding.dpn)

        # vn+1 = vn + h/6 * (a1 + 2*a2 + 2*a3 + a4)
        add_multiplied!(embedding.dvn, embedding.a1, 2, embedding.a2)
        increment_with_multiplied!(embedding.dvn, 2, embedding.a3)
        increment!(embedding.dvn, embedding.a4)
        multiply!(embedding.dvn, h/6)
        increment!(embedding.vn, embedding.dvn)

        for i in 1:length(embedding.vn)
            speed = pt_length(embedding.vn[i])
            speed > parameters.max_velocity &&
                (embedding.vn[i] = pt_normalize(embedding.vn[i]) * parameters.max_velocity)
        end

        embedding.elapsed_time += h
        embedding.elapsed_calculation_time = elapsed_ms()

        embedding.last_max_velocity = 0.0
        embedding.last_max_acceleration = 0.0
        for i in 1:length(embedding.vn)
            velocity = pt_length(embedding.vn[i])
            velocity > embedding.last_max_velocity && (embedding.last_max_velocity = velocity)
            embedding.an[i] = (embedding.a1[i] + embedding.a2[i] +
                               embedding.a3[i] + embedding.a4[i]) / 4
            acceleration = pt_length(embedding.an[i])
            acceleration > embedding.last_max_acceleration &&
                (embedding.last_max_acceleration = acceleration)
        end
        velocity_relax = min(1.0, parameters.velocity_relax_limit / embedding.last_max_velocity)
        acceleration_relax =
            min(1.0, parameters.acceleration_relax_limit / embedding.last_max_acceleration)
        embedding.relax_factor =
            max(embedding.relax_factor, min(velocity_relax, acceleration_relax))

        if embedding.cycle > parameters.max_cycle ||
           embedding.elapsed_calculation_time > parameters.max_calculation_time ||
           (embedding.last_max_velocity <= parameters.velocity_relax_limit &&
            embedding.last_max_acceleration <= parameters.acceleration_relax_limit)
            embedding.finished = true
        end
    end

    # The variables are deliberately left holding what the fourth probe of the
    # last cycle assigned, not the accepted step `pn`. That is what OMNeT++
    # reports, and `getNodePosition` reads it, so writing `pn` back here would
    # be a different picture — a slightly better one, and the wrong one.
    nothing
end

"""
    embedding_bounding_rectangle(embedding) -> Rc

The box covering every body that is not a wall.

The seeds are OMNeT++'s `DBL_MAX` and `DBL_MIN`, and `DBL_MIN` is the smallest
positive double rather than the most negative one. Reproduced rather than
corrected, for the reason `GraphComponent`'s own bounding rectangle gives.
"""
function embedding_bounding_rectangle(embedding::ForceDirectedEmbedding)
    top = floatmax(Float64); bottom = floatmin(Float64)
    left = floatmax(Float64); right = floatmin(Float64)
    for body in embedding.bodies
        body isa WallBody && continue
        top = min(top, body_top(body))
        bottom = max(bottom, body_bottom(body))
        left = min(left, body_left(body))
        right = max(right, body_right(body))
    end
    Rc(left, top, 0.0, right - left, bottom - top)
end

end # module
