"""
    GestureModule

The gestures: the patterns that code finds in a sequence of events, and the
pattern language that a reader uses to match an input. A gesture is plain data,
as an event is. An event is the gesture of one event, so the pattern language
matches both kinds, and it lives here, where both kinds are known.

It also holds the recognition of gestures: a `GestureRecognition` is a pure rule
that reads one input and its own state and answers what it finds, and a
projection runs a list of them. The click, the chord and the dwell are the
standard recognitions, and a package adds its own.

The module lives in eight fragments that share this namespace:

- [`GestureInterface.jl`](GestureInterface.jl) — `Gesture`, and the methods of
  `get_modifier_keys` and `get_event_time` for a gesture.
- [`MouseGesture.jl`](MouseGesture.jl) — `MouseClick`, `MouseEnter`, `MouseLeave`
  and `MouseDwell`.
- [`KeyboardGesture.jl`](KeyboardGesture.jl) — `KeyChord`.
- [`GesturePattern.jl`](GesturePattern.jl) — the pattern language:
  `GesturePattern`, its parser, and `@gesture_case`, whose docstring documents
  the syntax.
- [`GestureRecognition.jl`](GestureRecognition.jl) — `GestureRecognition`,
  `make_recognition_state`, `recognize`, `RecognitionStep`, and
  `make_standard_recognitions`.
- [`ClickRecognition.jl`](ClickRecognition.jl), [`ChordRecognition.jl`](ChordRecognition.jl)
  and [`DwellRecognition.jl`](DwellRecognition.jl) — the standard recognitions.
"""
module GestureModule

using ..EventModule

import ..EventModule: get_modifier_keys, get_event_time

export Gesture
export KeyChord
export MouseClick, MouseEnter, MouseLeave, MouseDwell
export GesturePattern, matches_gesture_pattern,
       KeyPressPattern, KeyDownPattern, KeyUpPattern,
       MouseDownPattern, MouseUpPattern, MouseClickPattern,
       MouseMovePattern, MouseEnterPattern, MouseLeavePattern, MouseDwellPattern,
       MouseScrollPattern,
       describe_gesture_pattern, GesturePatternRule, parse_gesture_pattern_rule,
       build_gesture_pattern_expr, build_gesture_field_bindings, @gesture_case
export GestureRecognition, make_recognition_state, recognize, RecognitionStep,
       ClickRecognition, ChordRecognition, DwellRecognition, make_standard_recognitions

include("GestureInterface.jl")
include("MouseGesture.jl")
include("KeyboardGesture.jl")
include("GesturePattern.jl")
include("GestureRecognition.jl")
include("ClickRecognition.jl")
include("ChordRecognition.jl")
include("DwellRecognition.jl")

end # module
