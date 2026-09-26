"""
    EventModule

The input: the events that an input source makes, for any backend, the gestures
that code finds in them, and a pattern language that matches both. An event and a
gesture are plain data. Their fields hold symbols, numbers, characters, modifier
keys and the time of the input, and they hold no reference to the source that
made them.

The module lives in eight fragments that share this namespace:

- [`EventInterface.jl`](EventInterface.jl) — `Event` and `Gesture`, and
  `get_modifier_keys` and `get_event_time`, the generics that every event and
  every gesture answer.
- [`ModifierKeys.jl`](ModifierKeys.jl) — the Ctrl, Shift, Alt and Meta keys that an
  event holds.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — the key events `KeyDown`, `KeyUp` and
  `KeyPress`, and the gesture `KeyChord`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseButtons`, the mouse events `MouseDown`,
  `MouseUp`, `MouseMove` and `MouseScroll`, and the gestures `MouseClick`,
  `MouseEnter` and `MouseLeave`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`, `WindowClose`, `WindowResize`,
  `WindowDefocus` and `WindowLeave`.
- [`WindowInput.jl`](WindowInput.jl) — an event or a gesture and the id of the
  window that it came from.
- [`EventDefaults.jl`](EventDefaults.jl) — the fallback of `get_modifier_keys`,
  `get_event_time`, and the predicates `has_ctrl_modifier_key`,
  `has_shift_modifier_key`, `has_alt_modifier_key` and `has_meta_modifier_key`.
- [`EventPattern.jl`](EventPattern.jl) — the pattern language: `EventPattern`, its
  parser, and `@event_case`, whose docstring documents the syntax.
"""
module EventModule

export Event, Gesture, get_modifier_keys, get_event_time
export ModifierKeys
export KeyDown, KeyUp, KeyPress, KeyChord
export MouseButtons, MouseDown, MouseUp, MouseClick, MouseMove, MouseEnter, MouseLeave,
       MouseScroll
export WindowQuit, WindowClose, WindowResize, WindowDefocus, WindowLeave
export WindowInput
export has_ctrl_modifier_key, has_shift_modifier_key, has_alt_modifier_key,
       has_meta_modifier_key
export EventPattern, matches_event_pattern,
       KeyPressPattern, KeyDownPattern, KeyUpPattern,
       MouseDownPattern, MouseUpPattern, MouseClickPattern,
       MouseMovePattern, MouseEnterPattern, MouseLeavePattern, MouseScrollPattern,
       describe_event_pattern, EventPatternRule, parse_event_pattern_rule,
       build_event_pattern_expr, build_event_field_bindings, @event_case

include("EventInterface.jl")
include("ModifierKeys.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("WindowInput.jl")
include("EventDefaults.jl")
include("EventPattern.jl")

end # module
