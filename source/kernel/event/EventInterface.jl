# Fragment of `EventModule` — the event contract: the abstract event types and the
# two generics that every event answers. The concrete events subtype these types and
# add their own `get_modifier_keys` methods, in the fragments after this one. The
# fallback of `get_modifier_keys` and the body of `get_event_time` are in
# `EventDefaults.jl`.

"""
    Event

The supertype of every input event. An event reports what happened, and when. It
carries no intent: the code that reads it gives it a meaning.

Every concrete event holds `time`, the time of the input in seconds on the clock
of `time()`, as its last field; an event type of another package holds it too.
The time is mandatory: each constructor takes it, the full constructor as its
last argument and the short forms as the keyword `time`. A backend gives the time
of the input from its own stamps. Code that makes an event from another event
gives the time of that event. Code that makes an event with no input before it
gives the time when it makes the event.
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

"""
    get_event_time(event) -> Float64

The time of the input that `event` reports, in seconds on the clock of `time()`.
"""
function get_event_time end
