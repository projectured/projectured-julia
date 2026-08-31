# Fragment of `EventModule` — the behaviour the event contract supplies itself:
# the modifier-free fallback for `get_modifier_keys`, and the per-flag predicates
# derived over it.

# An event with no modifier state of its own carries none.
get_modifier_keys(::Event) = ModifierKeys()

"""
    has_ctrl_modifier_key(event)  -> Bool
    has_shift_modifier_key(event) -> Bool
    has_alt_modifier_key(event)   -> Bool
    has_meta_modifier_key(event)  -> Bool

Whether the given modifier was held when `event` occurred. Defined once over
[`get_modifier_keys`](@ref), so they work for every event, mouse ones included.
"""
has_ctrl_modifier_key(event::Event)  = get_modifier_keys(event).ctrl
has_shift_modifier_key(event::Event) = get_modifier_keys(event).shift
has_alt_modifier_key(event::Event)   = get_modifier_keys(event).alt
has_meta_modifier_key(event::Event)  = get_modifier_keys(event).meta
