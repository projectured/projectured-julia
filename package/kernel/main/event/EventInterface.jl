# Fragment of `EventModule` — the event **contract**: the abstract event types
# and the one generic every event answers. Included before the concrete event
# structs, which subtype these and add their own `get_modifiers` methods.

"""
    Event

Abstract supertype of every input event. An event reports *what happened* — it
carries no intent, and what it means is decided by whoever reads it.
"""
abstract type Event end

"""
    DeviceEvent <: Event

An event an input source reports: a key going down, a button, motion, a window
the user closed. This is the vocabulary an event source translates its platform's
raw events into, and the only kind it may produce.
"""
abstract type DeviceEvent <: Event end

"""
    SyntheticEvent <: Event

An event *derived* from other events rather than reported by a device — a click
(a down/up pair), a chord (a key sequence), a pointer crossing (motion across a
boundary). Whoever holds the state that spans the constituent events synthesises
it; a device never does.
"""
abstract type SyntheticEvent <: Event end

"""
    get_modifiers(event) -> Modifiers

The modifier keys held when `event` occurred. Events that carry no modifier state
of their own answer `Modifiers()` — including `KeyChord`, whose modifiers live on
its constituent `KeyDown`s.
"""
function get_modifiers end
