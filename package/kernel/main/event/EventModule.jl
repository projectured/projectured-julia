"""
    EventModule

The **input event vocabulary**: the backend-agnostic values that flow from an
input device into the editor. The fragments:

- [`EventInterface.jl`](EventInterface.jl) — the `Event`/`DeviceEvent`/`SyntheticEvent`
  types and the `get_modifier_keys` generic every event answers.
- [`ModifierKeys.jl`](ModifierKeys.jl) — the Ctrl/Shift/Alt/Meta state an event carries.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`,
  `MouseEnter`, `MouseLeave`, `MouseScroll`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`, `WindowClose`, `WindowResize`,
  `WindowDefocus`.
- [`WindowInput.jl`](WindowInput.jl) — an event plus the id of the window it came from.
- [`EventDefaults.jl`](EventDefaults.jl) — the `get_modifier_keys` fallback and the
  `has_ctrl_modifier_key`/`has_shift_modifier_key`/`has_alt_modifier_key`/`has_meta_modifier_key` predicates derived over it.

An event is pure data: it knows neither the device that produced it nor the
document it will end up changing.
"""
module EventModule

export Event, DeviceEvent, SyntheticEvent,
       ModifierKeys, get_modifier_keys, has_ctrl_modifier_key, has_shift_modifier_key, has_alt_modifier_key, has_meta_modifier_key,
       KeyDown, KeyUp, KeyPress, KeyChord,
       MouseDown, MouseUp, MousePress, MouseMove, MouseEnter, MouseLeave, MouseScroll,
       WindowQuit, WindowClose, WindowResize, WindowDefocus,
       WindowInput

include("EventInterface.jl")
include("ModifierKeys.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("WindowInput.jl")
include("EventDefaults.jl")

end # module
