# Fragment of `EventModule` — the behaviour the event contract supplies itself:
# the modifier-free fallback for `get_modifiers`, and the per-flag predicates
# derived over it.

# An event with no modifier state of its own carries none.
get_modifiers(::Event) = Modifiers()

"""
    is_ctrl(event)  -> Bool
    is_shift(event) -> Bool
    is_alt(event)   -> Bool
    is_meta(event)  -> Bool

Whether the given modifier was held when `event` occurred. Defined once over
[`get_modifiers`](@ref), so they work for every event, mouse ones included.
"""
is_ctrl(event::Event)  = get_modifiers(event).ctrl
is_shift(event::Event) = get_modifiers(event).shift
is_alt(event::Event)   = get_modifiers(event).alt
is_meta(event::Event)  = get_modifiers(event).meta
