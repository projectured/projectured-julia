# Fragment of `EventModule` — a window input: an event paired with the window it belongs to.

"""
    WindowInput(window_id::Symbol, event::Event)

Wraps an input event with the id of the window it came from. This is the protocol
type that flows between an event source, a recogniser, and whatever consumes the
recognised event — everything downstream of raw polling. The window is named by an
opaque `Symbol`, so an event never has to name a window type.
"""
struct WindowInput
    window_id::Symbol
    event::Event
end
