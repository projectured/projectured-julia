# Fragment of `GestureModule` — the contract of a gesture: its abstract type, and
# the methods of the two generics of the event layer that every gesture answers.

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

# A gesture with no modifier state of its own carries none, as a `KeyChord`, whose
# modifiers are on its `KeyDown`s.
get_modifier_keys(::Gesture) = ModifierKeys()

# Every concrete gesture holds its time as its field `time`: the time of the event
# that completes its pattern.
get_event_time(input::Gesture) = input.time::Float64
