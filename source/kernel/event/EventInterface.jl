# Fragment of `EventModule` — the contract of the input: the abstract types of an
# event and of a gesture, and the two generics that both answer. The concrete events
# and gestures subtype these types and add their own `get_modifier_keys` methods, in
# the fragments after this one.

"""
    Event

The supertype of every input event. An event is a record of what the platform
reported: a key that goes down, a mouse button, a motion, a character that the
user typed, a window that the user closes. An event source translates the raw
events of its platform into these events, and it makes no other kind. An event
carries no intent: the code that reads it gives it a meaning.

Every concrete event holds `time`, the time of the input in seconds on the clock
of `time()`, as its last field; an event type of another package holds it too.
The time is mandatory: each constructor takes it, the full constructor as its
last argument and the short forms as the keyword `time`. A backend gives the time
of the input from its own stamps. Code that makes an event from another event
gives the time of that event. Code that makes an event with no input before it
gives the time when it makes the event.

See also [`Gesture`](@ref), which is not an event.
"""
abstract type Event end

"""
    Gesture

The supertype of every gesture. A gesture is a pattern that code finds in a
sequence of events, and the pattern can leave out events: a click is a down and an
up of one button, near in place and in time; a chord is a sequence of keys. The
code that holds the state across those events makes the gesture, and an event
source never does. A gesture is not an event, and it carries no intent either: the
code that reads it gives it a meaning.

A gesture holds `time` as its last field, as an event does: the time of the event
that completes its pattern. A place that takes an input of either kind takes
`Union{Event,Gesture}`.
"""
abstract type Gesture end

"""
    get_modifier_keys(input) -> ModifierKeys

The modifier keys that were held when `input`, an event or a gesture, happened. An
input without modifier keys of its own gives `ModifierKeys()`. So does a
`KeyChord`, whose modifiers are on its `KeyDown`s.
"""
function get_modifier_keys end

"""
    get_event_time(input) -> Float64

The time of `input`, an event or a gesture, in seconds on the clock of `time()`.
For a gesture, it is the time of the event that completes its pattern.
"""
function get_event_time end
