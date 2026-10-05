"""
    EventModule

The events: the records of what an input source or the editor reported, for any
backend. An event is plain data. Its fields hold symbols, numbers, characters,
modifier keys and the time of the input, and it holds no reference to the source
that made it. An event has no meaning, and this layer names no gesture: the
gesture layer above finds the gestures in the events and holds the pattern
language that matches both.

The module lives in ten fragments that share this namespace:

- [`EventInterface.jl`](EventInterface.jl) — `Event`, and `get_modifier_keys` and
  `get_event_time`, the generics that every input answers.
- [`ModifierKeys.jl`](ModifierKeys.jl) — the Ctrl, Shift, Alt and Meta keys that an
  event holds.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — the key events `KeyDown`, `KeyUp` and
  `KeyPress`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseButtons`, the mouse events
  `MouseDown`, `MouseUp`, `MouseMove` and `MouseScroll`, and the predicate
  `is_move_without_button`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`, `WindowClose`, `WindowResize`,
  `WindowDefocus` and `WindowLeave`.
- [`TimerEvent.jl`](TimerEvent.jl) — `TimerExpire`, the event of a timer that a
  reader set.
- [`DisplayEvent.jl`](DisplayEvent.jl) — `DisplayUpdate`, the event of a display that
  shows a new frame of a window.
- [`SystemEvent.jl`](SystemEvent.jl) — `SystemColors`, the colour settings of the
  operating system, and `SystemColorsChange`, the event of their change.
- [`WindowInput.jl`](WindowInput.jl) — an input and the id of the window that it
  came from.
- [`EventDefaults.jl`](EventDefaults.jl) — the fallback of `get_modifier_keys`,
  `get_event_time`, and the predicates `has_ctrl_modifier_key`,
  `has_shift_modifier_key`, `has_alt_modifier_key` and `has_meta_modifier_key`.
"""
module EventModule

export Event, get_modifier_keys, get_event_time
export ModifierKeys
export KeyDown, KeyUp, KeyPress
export MouseButtons, MouseDown, MouseUp, MouseMove, is_move_without_button, MouseScroll
export WindowQuit, WindowClose, WindowResize, WindowDefocus, WindowLeave
export TimerExpire
export DisplayUpdate
export SystemColors, SystemColorsChange
export WindowInput
export has_ctrl_modifier_key, has_shift_modifier_key, has_alt_modifier_key,
       has_meta_modifier_key

include("EventInterface.jl")
include("ModifierKeys.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("TimerEvent.jl")
include("DisplayEvent.jl")
include("SystemEvent.jl")
include("WindowInput.jl")
include("EventDefaults.jl")

end # module
