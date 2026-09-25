# Fragment of `EventModule` — an event and the window that it belongs to.

"""
    WindowInput(window_id::Symbol, event::Event)

An input event and the id of the window that it came from. An event source makes
it, and every step after the read of the raw events passes it on. The window is an
opaque `Symbol`, so an event names no window type.
"""
struct WindowInput
    window_id::Symbol
    event::Event
end
