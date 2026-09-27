# Fragment of `EventModule` — an input and the window that it belongs to.

"""
    WindowInput(window_id::Symbol, event)

An input and the id of the window that it came from. An event source makes it
with an event, the recognition of gestures makes it with a gesture, and every step
after the read of the raw events passes it on. The field is named `event` for
both kinds, and the type is generic over it, so this layer names no gesture. The
window is an opaque `Symbol`, so an input names no window type.
"""
struct WindowInput{E}
    window_id::Symbol
    event::E
end
