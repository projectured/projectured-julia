"""
    EventModule

The **input event vocabulary**: the backend-agnostic values that flow from an
input device into the editor. Four fragments share this namespace:

- [`Modifiers.jl`](Modifiers.jl) — the Ctrl/Shift/Alt/Meta state every event carries.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`,
  `MouseEnter`, `MouseLeave`, `MouseScroll`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`.
- [`EventEnvelope.jl`](EventEnvelope.jl) — an event plus the id of the window it came from.

An event is pure data: it knows neither the device that produced it nor the
document it will end up changing. Some events are produced by a backend polling
real hardware; others are *synthesised* from those by a recogniser (a click from
a down/up pair, a chord from a key sequence) or by a tracker (pointer enter/leave
from motion). Both kinds are the same vocabulary — a consumer matches an event
without caring which side of that line it came from.
"""
module EventModule

export Modifiers,
       KeyDown, KeyUp, KeyPress, KeyChord,
       is_ctrl, is_shift, is_alt, is_meta,
       MouseDown, MouseUp, MousePress, MouseMove, MouseEnter, MouseLeave, MouseScroll,
       WindowQuit,
       EventEnvelope

include("Modifiers.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("EventEnvelope.jl")

end # module
