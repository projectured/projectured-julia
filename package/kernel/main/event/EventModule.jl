"""
    EventModule

The **input event vocabulary**: the backend-agnostic values that flow from an
input device into the editor. Five fragments share this namespace:

- [`Modifiers.jl`](Modifiers.jl) — the Ctrl/Shift/Alt/Meta state an event carries.
- [`KeyboardEvent.jl`](KeyboardEvent.jl) — `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord`.
- [`MouseEvent.jl`](MouseEvent.jl) — `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`,
  `MouseEnter`, `MouseLeave`, `MouseScroll`.
- [`WindowEvent.jl`](WindowEvent.jl) — `WindowQuit`, `WindowClose`, `WindowResize`,
  `WindowDefocus`.
- [`EventEnvelope.jl`](EventEnvelope.jl) — an event plus the id of the window it came from.

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

"""
    Event

Abstract supertype of every input event. An event reports *what happened* — it
carries no intent, and what it means is decided by whoever reads it.
"""
abstract type Event end

"""
    DeviceEvent <: Event

An event an input device reports: a key going down, a button, motion, a window
the user closed. This is the vocabulary a backend translates its platform's raw
events into, and the only kind it may produce.
"""
abstract type DeviceEvent <: Event end

"""
    SyntheticEvent <: Event

An event *derived* from other events rather than reported by a device — a click
(a down/up pair), a chord (a key sequence), a pointer crossing (motion across a
boundary). Whoever holds the state that spans the constituent events synthesises
it; a device never does.
"""
abstract type SyntheticEvent <: Event end

include("Modifiers.jl")
include("KeyboardEvent.jl")
include("MouseEvent.jl")
include("WindowEvent.jl")
include("EventEnvelope.jl")

"""
    get_modifiers(event) -> Modifiers

The modifier keys held when `event` occurred. Events that carry no modifier state
of their own answer `Modifiers()` — including `KeyChord`, whose modifiers live on
its constituent `KeyDown`s.
"""
get_modifiers(::Event) = Modifiers()

"""
    is_ctrl(event)  -> Bool
    is_shift(event) -> Bool
    is_alt(event)   -> Bool
    is_meta(event)  -> Bool

Whether the given modifier was held when `event` occurred. Defined once over
[`get_modifiers`](@ref), so they work for every event, mouse ones included.
"""
is_ctrl(event::Event)  = get_modifiers(event).ctrl
is_shift(event::Event) = get_modifiers(event).shift
is_alt(event::Event)   = get_modifiers(event).alt
is_meta(event::Event)  = get_modifiers(event).meta

end # module
