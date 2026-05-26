"""
    ModifiersModule

Shared modifier-key state used by both keyboard and mouse events.
"""
module ModifiersModule

export Modifiers

"""
    Modifiers(ctrl, shift, alt)

Immutable struct carrying the state of the three common modifier keys.
`Modifiers()` (no-arg constructor) returns all-false, representing no
modifier held.
"""
struct Modifiers
    ctrl::Bool
    shift::Bool
    alt::Bool
end

Modifiers() = Modifiers(false, false, false)

end # module
