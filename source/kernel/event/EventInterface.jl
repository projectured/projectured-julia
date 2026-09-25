# Fragment of `EventModule` — the event contract: the abstract event types and the
# one generic that every event answers. The concrete events subtype these types and
# add their own `get_modifier_keys` methods, in the fragments after this one.

"""
    Event

The supertype of every input event. An event reports what happened. It carries no
intent: the code that reads it gives it a meaning.
"""
abstract type Event end

"""
    DeviceEvent <: Event

An event that an input source reports: a key that goes down, a mouse button, a
motion, a window that the user closes. An event source translates the raw events of
its platform into these events, and it makes no other kind.
"""
abstract type DeviceEvent <: Event end

"""
    SyntheticEvent <: Event

An event that code makes from other events, not one that a device reports: a click
from a down and up pair, a chord from a sequence of keys, a crossing from the motion
of the pointer. The code that holds the state across those events makes it, and a
device never does.
"""
abstract type SyntheticEvent <: Event end

"""
    get_modifier_keys(event) -> ModifierKeys

The modifier keys that were held when `event` happened. An event without modifier
keys of its own gives `ModifierKeys()`. So does a `KeyChord`, whose modifiers are on
its `KeyDown`s.
"""
function get_modifier_keys end
