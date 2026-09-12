"""
    ForceDirectedParametersModule

The bodies and the forces, from OMNeT++'s
`src/layout/forcedirectedparameters.h`.

Three bodies:

- `Body` sits where its variable says.
- `RelativelyPositionedBody` sits at a fixed offset from its variable, so
  several of them on one variable move as one rigid group.
- `WallBody` is a border: no size on one axis and infinite size on the other,
  and a position on the axis it does constrain.

And the forces the graph layouter builds out of them: an electric repulsion
between every pair of bodies, a spring along every edge, four springs and a
choice of the least stretched one for an edge to the border, a spring pulling
the third dimension back to zero, and a drag that takes energy out of everything.

**Two deviations.** The common fields of a force provider are one `config`
value that each provider holds, rather than an inherited base — Julia has no
field inheritance, and composition says the same thing. And `HorizonalSpring` is
spelled `HorizontalSpring`; the missing `t` in the original is a typo, not an
identifier anybody depends on.

The layouter never builds `Friction`, `PointConstraint`, `LineConstraint` or
`CircleConstraint`, so they are not ported. A force nothing constructs is not
part of the picture.
"""
module ForceDirectedParametersModule

import ..LayoutGeometryModule: Pt, Rs, pt_length, pt_normalize, get_base_plane_length,
                               convert_nan_to_zero, rc_from_center_size, rc_base_plane_distance,
                               is_nil, rs_nil
import ..ForceDirectedParametersBaseModule: Variable, AbstractBody, AbstractForceProvider,
                                            reinitialize!, apply_forces!, potential_energy,
                                            class_name, set_embedding!,
                                            get_position, assign_position!,
                                            get_velocity, add_force!, subtract_force!,
                                            body_position, body_size, body_mass,
                                            body_charge, body_variable

export Body, RelativelyPositionedBody, WallBody, set_wall_position!, set_wall_variable!,
       ForceProviderConfig, AbstractElectricRepulsion, ElectricRepulsion,
       VerticalElectricRepulsion, HorizontalElectricRepulsion,
       AbstractSpring, Spring, VerticalSpring, HorizontalSpring,
       LeastExpandedSpring, BasePlaneSpring, Drag,
       get_spring_repose_length, get_spring_distance_and_vector

signum(value::Real) = value < 0 ? -1.0 : value == 0 ? 0.0 : 1.0

# ── Bodies ───────────────────────────────────────────────────────────────────

"""
    Body(variable[, size])
    Body(variable, mass, charge, size)

A freely positioned body. `-1` for mass or charge, and a nil size, mean "take
the default from the embedding's parameters at reinitialize time".
"""
mutable struct Body <: AbstractBody
    variable::Union{Nothing,Variable}
    mass::Float64
    charge::Float64
    size::Rs
    embedding::Any
end

Body(variable) = Body(variable, -1.0, -1.0, rs_nil(), nothing)
Body(variable, size::Rs) = Body(variable, -1.0, -1.0, size, nothing)
Body(variable, mass::Real, charge::Real, size::Rs) =
    Body(variable, Float64(mass), Float64(charge), size, nothing)

"""
    RelativelyPositionedBody(variable, relative_position[, size])

A body that sits `relative_position` away from its variable. Every body sharing
one variable keeps its own offset, so the group holds its shape and the variable
is the one thing the forces move. This is how a module vector is laid out.
"""
mutable struct RelativelyPositionedBody <: AbstractBody
    variable::Variable
    relative_position::Pt
    mass::Float64
    charge::Float64
    size::Rs
    embedding::Any
end

RelativelyPositionedBody(variable::Variable, relative_position::Pt) =
    RelativelyPositionedBody(variable, relative_position, -1.0, -1.0, rs_nil(), nothing)
RelativelyPositionedBody(variable::Variable, relative_position::Pt, size::Rs) =
    RelativelyPositionedBody(variable, relative_position, -1.0, -1.0, size, nothing)

"""
    WallBody(horizontal)

A border: infinite along one axis, nothing along the other. A horizontal wall is
the top or the bottom edge and constrains y; a vertical one constrains x. Its
variable arrives later, because whether it is free or pinned depends on what
else the layout has.
"""
mutable struct WallBody <: AbstractBody
    variable::Union{Nothing,Variable}
    horizontal::Bool
    mass::Float64
    charge::Float64
    size::Rs
    embedding::Any
end

WallBody(horizontal::Bool) =
    WallBody(nothing, horizontal, -1.0, -1.0,
             horizontal ? Rs(Inf, 0.0) : Rs(0.0, Inf), nothing)

"Put the wall at `position` on the axis it constrains."
set_wall_position!(wall::WallBody, position::Real) =
    assign_position!(wall.variable,
                     Pt(wall.horizontal ? NaN : position,
                        wall.horizontal ? position : NaN, NaN))

function set_wall_variable!(wall::WallBody, variable::Variable)
    wall.variable === nothing || throw(ArgumentError("WallBody: the variable is already set."))
    wall.variable = variable
    nothing
end

const AnyBody = Union{Body,RelativelyPositionedBody,WallBody}

set_embedding!(body::AnyBody, embedding) = (body.embedding = embedding; nothing)

function reinitialize!(body::AnyBody)
    parameters = body.embedding.parameters
    body.mass == -1 && (body.mass = parameters.default_body_mass)
    body.charge == -1 && (body.charge = parameters.default_body_charge)
    is_nil(body.size) && (body.size = parameters.default_body_size)
    nothing
end

body_position(body::Body) = get_position(body.variable)
body_position(body::WallBody) = get_position(body.variable)
body_position(body::RelativelyPositionedBody) =
    get_position(body.variable) + body.relative_position

body_variable(body::AnyBody) = body.variable
body_size(body::AnyBody) = body.size
body_mass(body::AnyBody) = body.mass
body_charge(body::AnyBody) = body.charge

class_name(::Body) = "Body"
class_name(::RelativelyPositionedBody) = "RelativelyPositionedBody"
class_name(::WallBody) = "WallBody"

# ── What every force provider carries ────────────────────────────────────────

"""
    ForceProviderConfig(; max_force = -1, slippery = -1, point_like_distance = -1)

The three settings every force provider has. `-1` means "take the default from
the embedding's parameters", which is only known once the embedding exists.
"""
mutable struct ForceProviderConfig
    max_force::Float64
    slippery::Int
    point_like_distance::Int
    embedding::Any
end

ForceProviderConfig(; max_force::Real = -1, slippery::Integer = -1,
                    point_like_distance::Integer = -1) =
    ForceProviderConfig(Float64(max_force), Int(slippery), Int(point_like_distance), nothing)

function reinitialize_config!(config::ForceProviderConfig)
    parameters = config.embedding.parameters
    config.max_force == -1 && (config.max_force = parameters.default_max_force)
    config.slippery == -1 && (config.slippery = parameters.default_slippery ? 1 : 0)
    config.point_like_distance == -1 &&
        (config.point_like_distance = parameters.default_point_like_distance ? 1 : 0)
    nothing
end

valid_force(config::ForceProviderConfig, force::Real) = min(config.max_force, force)
valid_signed_force(config::ForceProviderConfig, force::Real) =
    force < 0 ? -valid_force(config, abs(force)) : valid_force(config, abs(force))

"""
    distance_and_vector(config, body1, body2) -> (Pt, Float64)

The unit vector from `body2` to `body1`, and how far apart they are.

Three ways to measure, and the choice changes the whole picture:

- point-like: centre to centre, sizes ignored;
- not point-like: centre to centre less the part of each body that lies along
  the line, so two big boxes are "close" when their edges are close;
- slippery: the shortest distance between the two rectangles, which lets a body
  slide along another's edge instead of being pushed through its corner.
"""
function distance_and_vector(config::ForceProviderConfig, body1::AbstractBody, body2::AbstractBody)
    config.slippery != 0 ? slippery_distance_and_vector(config, body1, body2) :
                           standard_distance_and_vector(config, body1, body2)
end

function standard_distance_and_vector(config::ForceProviderConfig, body1::AbstractBody, body2::AbstractBody)
    pt1 = body_position(body1)
    pt2 = body_position(body2)
    vector = pt1 - pt2
    distance = pt_length(vector)
    vector = vector / distance

    if config.point_like_distance == 0
        rs1 = body_size(body1)
        rs2 = body_size(body2)
        dx = abs(pt1.x - pt2.x)
        dy = abs(pt1.y - pt2.y)
        half = get_base_plane_length(vector) / 2
        d1 = half * min(rs1.width / dx, rs1.height / dy)
        d2 = half * min(rs2.width / dx, rs2.height / dy)
        distance = max(0.0, distance - d1 - d2)
    end

    (vector, distance)
end

function standard_horizontal_distance_and_vector(config::ForceProviderConfig,
                                                 body1::AbstractBody, body2::AbstractBody)
    distance = body_position(body1).x - body_position(body2).x
    vector = Pt(signum(distance), 0, 0)
    distance = abs(distance)
    if config.point_like_distance == 0
        distance = max(0.0, distance - body_size(body1).width - body_size(body2).width)
    end
    (vector, distance)
end

function standard_vertical_distance_and_vector(config::ForceProviderConfig,
                                               body1::AbstractBody, body2::AbstractBody)
    distance = body_position(body1).y - body_position(body2).y
    vector = Pt(0, signum(distance), 0)
    distance = abs(distance)
    if config.point_like_distance == 0
        distance = max(0.0, distance - body_size(body1).height - body_size(body2).height)
    end
    (vector, distance)
end

function slippery_distance_and_vector(::ForceProviderConfig, body1::AbstractBody, body2::AbstractBody)
    rc1 = rc_from_center_size(body_position(body1), body_size(body1))
    rc2 = rc_from_center_size(body_position(body2), body_size(body2))
    segment, distance = rc_base_plane_distance(rc1, rc2)
    vector = pt_normalize(convert_nan_to_zero(segment.begin_pt - segment.end_pt))
    (vector, distance)
end

# ── Electric repulsion ───────────────────────────────────────────────────────

"""
    AbstractElectricRepulsion

A push apart that falls off with the square of the distance. Beyond
`linearity_distance` it is faded out linearly and reaches nothing at
`max_distance`, which is how the layouter stops two unconnected parts of a graph
from pushing each other to infinity.
"""
abstract type AbstractElectricRepulsion <: AbstractForceProvider end

for T in (:ElectricRepulsion, :VerticalElectricRepulsion, :HorizontalElectricRepulsion)
    @eval begin
        mutable struct $T <: AbstractElectricRepulsion
            config::ForceProviderConfig
            charge1::AbstractBody
            charge2::AbstractBody
            linearity_distance::Float64
            max_distance::Float64
        end
        class_name(::$T) = $(string(T))
    end
end

ElectricRepulsion(charge1::AbstractBody, charge2::AbstractBody,
                  linearity_distance::Real = -1, max_distance::Real = -1) =
    ElectricRepulsion(ForceProviderConfig(), charge1, charge2,
                      Float64(linearity_distance), Float64(max_distance))

VerticalElectricRepulsion(charge1::AbstractBody, charge2::AbstractBody) =
    VerticalElectricRepulsion(ForceProviderConfig(), charge1, charge2, -1.0, -1.0)

HorizontalElectricRepulsion(charge1::AbstractBody, charge2::AbstractBody) =
    HorizontalElectricRepulsion(ForceProviderConfig(), charge1, charge2, -1.0, -1.0)

set_embedding!(provider::AbstractElectricRepulsion, embedding) =
    (provider.config.embedding = embedding; nothing)

function reinitialize!(provider::AbstractElectricRepulsion)
    reinitialize_config!(provider.config)
    parameters = provider.config.embedding.parameters
    provider.linearity_distance == -1 &&
        (provider.linearity_distance = parameters.default_electric_repulsion_linearity_distance)
    provider.max_distance == -1 &&
        (provider.max_distance = parameters.default_electric_repulsion_max_distance)
    nothing
end

repulsion_distance_and_vector(provider::ElectricRepulsion) =
    distance_and_vector(provider.config, provider.charge1, provider.charge2)
repulsion_distance_and_vector(provider::VerticalElectricRepulsion) =
    standard_vertical_distance_and_vector(provider.config, provider.charge1, provider.charge2)
repulsion_distance_and_vector(provider::HorizontalElectricRepulsion) =
    standard_horizontal_distance_and_vector(provider.config, provider.charge1, provider.charge2)

function apply_forces!(provider::AbstractElectricRepulsion)
    vector, distance = repulsion_distance_and_vector(provider)
    parameters = provider.config.embedding.parameters

    power = if distance == 0
        provider.config.max_force
    else
        valid_force(provider.config,
                    parameters.electric_repulsion_coefficient *
                    body_charge(provider.charge1) * body_charge(provider.charge2) /
                    distance / distance)
    end

    if provider.linearity_distance != -1 && distance > provider.linearity_distance
        power *= 1 - min(1.0, (distance - provider.linearity_distance) /
                              (provider.max_distance - provider.linearity_distance))
    end

    force = vector * power
    add_force!(body_variable(provider.charge1), force)
    subtract_force!(body_variable(provider.charge2), force)
    nothing
end

function potential_energy(provider::AbstractElectricRepulsion)
    _, distance = repulsion_distance_and_vector(provider)
    provider.config.embedding.parameters.electric_repulsion_coefficient *
        body_charge(provider.charge1) * body_charge(provider.charge2) / distance
end

# ── Springs ──────────────────────────────────────────────────────────────────

"""
    AbstractSpring

A pull towards a repose length, linear in how far the current distance is from
it. Push when too close, pull when too far.
"""
abstract type AbstractSpring <: AbstractForceProvider end

for T in (:Spring, :VerticalSpring, :HorizontalSpring, :BasePlaneSpring)
    @eval begin
        mutable struct $T <: AbstractSpring
            config::ForceProviderConfig
            body1::Union{Nothing,AbstractBody}
            body2::Union{Nothing,AbstractBody}
            spring_coefficient::Float64
            repose_length::Float64
        end
        class_name(::$T) = $(string(T))
    end
end

Spring(body1, body2, spring_coefficient::Real = -1, repose_length::Real = -1) =
    Spring(ForceProviderConfig(), body1, body2,
           Float64(spring_coefficient), Float64(repose_length))

VerticalSpring(body1, body2, spring_coefficient::Real = -1, repose_length::Real = -1) =
    VerticalSpring(ForceProviderConfig(), body1, body2,
                   Float64(spring_coefficient), Float64(repose_length))

HorizontalSpring(body1, body2, spring_coefficient::Real = -1, repose_length::Real = -1) =
    HorizontalSpring(ForceProviderConfig(), body1, body2,
                     Float64(spring_coefficient), Float64(repose_length))

"""
    BasePlaneSpring(body, spring_coefficient, repose_length)

A spring between a body and the base plane. Its pull grows with the embedding's
relax factor, so a body may wander through the third dimension early on — which
is how the layout unties knots the plane cannot — and is drawn flat by the end.
"""
BasePlaneSpring(body, spring_coefficient::Real = -1, repose_length::Real = -1) =
    BasePlaneSpring(ForceProviderConfig(), body, nothing,
                    Float64(spring_coefficient), Float64(repose_length))

set_embedding!(provider::AbstractSpring, embedding) =
    (provider.config.embedding = embedding; nothing)

function reinitialize!(provider::AbstractSpring)
    reinitialize_config!(provider.config)
    parameters = provider.config.embedding.parameters
    provider.spring_coefficient == -1 &&
        (provider.spring_coefficient = parameters.default_spring_coefficient)
    provider.repose_length == -1 &&
        (provider.repose_length = parameters.default_spring_repose_length)
    nothing
end

get_spring_repose_length(provider::AbstractSpring) = provider.repose_length

spring_coefficient(provider::AbstractSpring) = provider.spring_coefficient
spring_coefficient(provider::BasePlaneSpring) =
    provider.spring_coefficient * provider.config.embedding.relax_factor

get_spring_distance_and_vector(provider::Spring) =
    distance_and_vector(provider.config, provider.body1, provider.body2)
get_spring_distance_and_vector(provider::VerticalSpring) =
    standard_vertical_distance_and_vector(provider.config, provider.body1, provider.body2)
get_spring_distance_and_vector(provider::HorizontalSpring) =
    standard_horizontal_distance_and_vector(provider.config, provider.body1, provider.body2)
function get_spring_distance_and_vector(provider::BasePlaneSpring)
    vector = Pt(0, 0, body_position(provider.body1).z)
    (vector, abs(vector.z))
end

function apply_forces!(provider::AbstractSpring)
    vector, distance = get_spring_distance_and_vector(provider)
    expansion = distance - provider.repose_length
    power = valid_signed_force(provider.config, spring_coefficient(provider) * expansion)
    force = vector * power

    provider.body1 === nothing || subtract_force!(body_variable(provider.body1), force)
    provider.body2 === nothing || add_force!(body_variable(provider.body2), force)
    nothing
end

function potential_energy(provider::AbstractSpring)
    _, distance = get_spring_distance_and_vector(provider)
    expansion = distance - provider.repose_length
    spring_coefficient(provider) * expansion * expansion / 2
end

"""
    LeastExpandedSpring(springs)

Several springs, of which only the least stretched one pulls. An edge to the
enclosing module's border is four springs, one per wall, and this makes the node
answer to the nearest wall rather than to all four at once.
"""
mutable struct LeastExpandedSpring <: AbstractForceProvider
    config::ForceProviderConfig
    springs::Vector{AbstractSpring}
end

LeastExpandedSpring(springs::Vector{<:AbstractSpring}) =
    LeastExpandedSpring(ForceProviderConfig(), collect(AbstractSpring, springs))

class_name(::LeastExpandedSpring) = "LeastExpandedSpring"

function set_embedding!(provider::LeastExpandedSpring, embedding)
    provider.config.embedding = embedding
    for spring in provider.springs
        set_embedding!(spring, embedding)
    end
    nothing
end

function reinitialize!(provider::LeastExpandedSpring)
    reinitialize_config!(provider.config)
    for spring in provider.springs
        reinitialize!(spring)
    end
    nothing
end

function least_expanded_spring(provider::LeastExpandedSpring)
    best = provider.springs[1]
    least = Inf
    for spring in provider.springs
        _, distance = get_spring_distance_and_vector(spring)
        expansion = abs(distance - get_spring_repose_length(spring))
        if expansion < least
            least = expansion
            best = spring
        end
    end
    best
end

apply_forces!(provider::LeastExpandedSpring) = apply_forces!(least_expanded_spring(provider))
potential_energy(provider::LeastExpandedSpring) =
    potential_energy(least_expanded_spring(provider))

# ── Drag ─────────────────────────────────────────────────────────────────────

"""
    Drag()

Takes kinetic energy out of every variable, against its velocity and in
proportion to its speed. Without it the simulation never settles.
"""
mutable struct Drag <: AbstractForceProvider
    config::ForceProviderConfig
end

Drag() = Drag(ForceProviderConfig())

class_name(::Drag) = "Drag"
set_embedding!(provider::Drag, embedding) = (provider.config.embedding = embedding; nothing)
reinitialize!(provider::Drag) = reinitialize_config!(provider.config)

function apply_forces!(provider::Drag)
    embedding = provider.config.embedding
    coefficient = embedding.parameters.friction_coefficient
    for variable in embedding.variables
        velocity = get_velocity(variable)
        add_force!(variable, velocity * (-coefficient * pt_length(velocity)))
    end
    nothing
end

potential_energy(::Drag) = 0.0

end # module
