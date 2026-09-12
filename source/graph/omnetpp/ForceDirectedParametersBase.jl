"""
    ForceDirectedParametersBaseModule

The vocabulary the force-directed embedding is written in, from OMNeT++'s
`src/layout/forcedirectedparametersbase.h`: the parameter block, the `Variable`
the differential equation solves for, and the two interfaces — a body, which has
a position, a size, a mass and a charge, and a force provider, which pushes
variables around.

A variable is not a node. Several bodies may share one variable, and that is how
a family of nodes moves as one: each is a body, all of them read the same
variable, and a force on any of them lands on that one variable.

**One deviation.** `PointConstrainedVariable` is a subclass over there and a
`point_constrained` flag here. It differs from a plain variable in three
one-line methods, and a flag says that more plainly than a second type would.
"""
module ForceDirectedParametersBaseModule

import ..LayoutGeometryModule: Pt, Rs, pt_zero, pt_length, is_fully_specified

export ForceDirectedParameters, Variable, PointConstrainedVariable,
       AbstractBody, AbstractForceProvider,
       reinitialize!, apply_forces!, potential_energy, class_name, set_embedding!,
       get_position, assign_position!, get_velocity, assign_velocity!,
       get_acceleration, kinetic_energy, reset_force!, get_mass, set_mass!,
       get_force, add_force!, subtract_force!,
       body_position, body_size, body_mass, body_charge, body_variable,
       body_left, body_right, body_top, body_bottom, body_left_top

"""
    ForceDirectedParameters

Everything that drives the simulation. `ForceDirectedGraphLayouter` draws most
of these from its own random generator, so a seed decides not only where the
nodes start but how hard the springs pull and how thick the drag is.

A value of `-1` in a body or a force provider means "take the default from
here", which is why several fields are named `default_*`.
"""
mutable struct ForceDirectedParameters
    default_body_size::Rs
    default_body_mass::Float64
    default_body_charge::Float64
    default_spring_coefficient::Float64
    default_spring_repose_length::Float64
    electric_repulsion_coefficient::Float64
    default_electric_repulsion_linearity_distance::Float64
    default_electric_repulsion_max_distance::Float64
    "Friction takes energy out of the system, against the current velocity."
    friction_coefficient::Float64
    "Measure distance between two rectangles rather than two centres."
    default_slippery::Bool
    "Treat a body as a point when measuring distance, ignoring its size."
    default_point_like_distance::Bool
    time_step::Float64
    min_time_step::Float64
    max_time_step::Float64
    "The step is multiplied or divided by this to chase the acceleration error."
    time_step_multiplier::Float64
    min_acceleration_error::Float64
    max_acceleration_error::Float64
    "Below this velocity and acceleration everywhere, the layout has settled."
    velocity_relax_limit::Float64
    acceleration_relax_limit::Float64
    default_max_force::Float64
    max_velocity::Float64
    max_cycle::Int
    "Milliseconds. `Inf` here, unlike OMNeT++ — see `ForceDirectedLayout`."
    max_calculation_time::Float64
end

# ── Variable ─────────────────────────────────────────────────────────────────

"""
    Variable(position[, velocity])
    PointConstrainedVariable(position)

What the differential equation solves for: the value is a position, its first
derivative a velocity, its second an acceleration.

A `PointConstrainedVariable` has fixed x and y and a free z. That is how a
pinned node is pinned: it cannot move in the plane, but it may still travel
through the third dimension, which is what lets the rest of the graph untangle
around it.
"""
mutable struct Variable
    position::Pt
    velocity::Pt
    force::Pt
    mass::Float64
    point_constrained::Bool
end

Variable(position::Pt, velocity::Pt = pt_zero(); point_constrained::Bool = false) =
    Variable(position, velocity, pt_zero(), 0.0, point_constrained)

PointConstrainedVariable(position::Pt) =
    Variable(position, pt_zero(), pt_zero(), 0.0, true)

get_position(variable::Variable) = variable.position

function assign_position!(variable::Variable, position::Pt)
    variable.position = variable.point_constrained ?
        Pt(variable.position.x, variable.position.y, position.z) : position
    nothing
end

get_velocity(variable::Variable) = variable.velocity

function assign_velocity!(variable::Variable, velocity::Pt)
    variable.velocity = variable.point_constrained ?
        Pt(variable.velocity.x, variable.velocity.y, velocity.z) : velocity
    nothing
end

get_acceleration(variable::Variable) =
    variable.point_constrained ? Pt(0, 0, variable.force.z) / variable.mass :
                                 variable.force / variable.mass

function kinetic_energy(variable::Variable)
    speed = pt_length(variable.velocity)
    0.5 * variable.mass * speed * speed
end

reset_force!(variable::Variable) = (variable.force = pt_zero(); nothing)
get_mass(variable::Variable) = variable.mass
set_mass!(variable::Variable, mass::Real) = (variable.mass = Float64(mass); nothing)
get_force(variable::Variable) = variable.force

# A force with an unassigned component is dropped rather than poisoning the sum
# with NaN. A wall body's position is NaN on the axis it does not constrain, so
# this happens on every layout that has a border.
add_force!(variable::Variable, f::Pt) =
    (is_fully_specified(f) && (variable.force = variable.force + f); nothing)

subtract_force!(variable::Variable, f::Pt) =
    (is_fully_specified(f) && (variable.force = variable.force - f); nothing)

reinitialize!(::Variable) = nothing

# ── The two interfaces ───────────────────────────────────────────────────────

"""
    AbstractBody

Something with a position, a size, a mass and a charge. Its position is its
**centre**, and `body_left` and friends read the corners off that.
"""
abstract type AbstractBody end

"""
    AbstractForceProvider

Something that pushes variables around: a spring, a repulsion, a drag. The
embedding asks every one of them for its forces at every probe of every cycle.
"""
abstract type AbstractForceProvider end

"Attach `embedding`, so the body or provider can read its parameters and state."
function set_embedding! end

"Take the defaults from the embedding's parameters, now that they are known."
function reinitialize! end

"Add this provider's forces to the variables it acts on."
function apply_forces! end

"The energy stored in this provider at the current positions."
function potential_energy end

"The name the original prints in its debug output; kept so a trace reads alike."
function class_name end

"The centre of the body."
function body_position end

function body_size end
function body_mass end
function body_charge end
function body_variable end

body_left(body::AbstractBody) = body_position(body).x - body_size(body).width / 2
body_right(body::AbstractBody) = body_position(body).x + body_size(body).width / 2
body_top(body::AbstractBody) = body_position(body).y - body_size(body).height / 2
body_bottom(body::AbstractBody) = body_position(body).y + body_size(body).height / 2
body_left_top(body::AbstractBody) = Pt(body_left(body), body_top(body), body_position(body).z)

end # module
