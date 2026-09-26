# Fragment of `EventModule` — the behaviour the contract of the input supplies
# itself: the modifier-free fallback for `get_modifier_keys`, the time that every
# event and gesture holds, and the per-flag predicates derived over the modifiers.

# An input with no modifier state of its own carries none.
get_modifier_keys(::Union{Event,Gesture}) = ModifierKeys()

# Every concrete event and gesture holds its time as its field `time`.
get_event_time(input::Union{Event,Gesture}) = input.time::Float64

"""
    has_ctrl_modifier_key(input)  -> Bool
    has_shift_modifier_key(input) -> Bool
    has_alt_modifier_key(input)   -> Bool
    has_meta_modifier_key(input)  -> Bool

Whether the given modifier was held when `input`, an event or a gesture, occurred.
Defined once over [`get_modifier_keys`](@ref), so they work for every event and
every gesture.
"""
has_ctrl_modifier_key(input::Union{Event,Gesture})  = get_modifier_keys(input).ctrl
has_shift_modifier_key(input::Union{Event,Gesture}) = get_modifier_keys(input).shift
has_alt_modifier_key(input::Union{Event,Gesture})   = get_modifier_keys(input).alt
has_meta_modifier_key(input::Union{Event,Gesture})  = get_modifier_keys(input).meta
