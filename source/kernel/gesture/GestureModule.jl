"""
    GestureModule

The gestures: the patterns that code finds in a sequence of events, and the
pattern language that a reader uses to match an input. A gesture is plain data,
as an event is. An event is the gesture of one event, so the pattern language
matches both kinds, and it lives here, where both kinds are known.

The module lives in four fragments that share this namespace:

- [`GestureInterface.jl`](GestureInterface.jl) — `Gesture`, and the methods of
  `get_modifier_keys` and `get_event_time` for a gesture.
- [`MouseGesture.jl`](MouseGesture.jl) — `MouseClick`, `MouseEnter`, `MouseLeave`
  and `MouseDwell`.
- [`KeyboardGesture.jl`](KeyboardGesture.jl) — `KeyChord`.
- [`GesturePattern.jl`](GesturePattern.jl) — the pattern language:
  `GesturePattern`, its parser, and `@gesture_case`, whose docstring documents
  the syntax.
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

include("GestureInterface.jl")
include("MouseGesture.jl")
include("KeyboardGesture.jl")
include("GesturePattern.jl")

end # module
