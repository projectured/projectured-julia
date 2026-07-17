"""
    EventModule

The **input event vocabulary**: the backend-agnostic values that flow from an
input device into the editor. The fragments:

- [`EventInterface.jl`](EventInterface.jl) — the `Event`/`DeviceEvent`/`SyntheticEvent`
  types and the `get_modifiers` generic every event answers.
- [`Modifiers.jl`](Modifiers.jl) — the Ctrl/Shift/Alt/Meta state an event carries.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`,
  `MouseEnter`, `MouseLeave`, `MouseScroll`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`, `WindowClose`, `WindowResize`,
  `WindowDefocus`.
- [`EventEnvelope.jl`](EventEnvelope.jl) — an event plus the id of the window it came from.
- [`EventDefaults.jl`](EventDefaults.jl) — the `get_modifiers` fallback and the
  `is_ctrl`/`is_shift`/`is_alt`/`is_meta` predicates derived over it.

An event is pure data: it knows neither the device that produced it nor the
document it will end up changing.

The type says where an event can come from. A `DeviceEvent` is what an event
source reports from real hardware; a `SyntheticEvent` is *derived* from those —
a click from a down/up pair, a chord from a key sequence, a pointer crossing
from motion — and no event source may emit one. Both are `Event`s, and a
consumer matching one need not care which side of that line it came from.
"""
module EventModule

export Event, DeviceEvent, SyntheticEvent,
       Modifiers, get_modifiers, is_ctrl, is_shift, is_alt, is_meta,
       KeyDown, KeyUp, KeyPress, KeyChord,
       MouseDown, MouseUp, MousePress, MouseMove, MouseEnter, MouseLeave, MouseScroll,
       WindowQuit, WindowClose, WindowResize, WindowDefocus,
       EventEnvelope

include("EventInterface.jl")
include("Modifiers.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("EventEnvelope.jl")
include("EventDefaults.jl")

end # module
