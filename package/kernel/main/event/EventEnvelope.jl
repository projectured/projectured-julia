# Fragment of `EventModule` — the event envelope.

"""
    EventEnvelope(window_id::Symbol, event)

Wraps an input event with the id of the window it came from. This is the protocol
type that flows between an event source, a recogniser, and whatever consumes the
recognised event — everything downstream of raw polling. It carries the window id
as an opaque `Symbol`, so naming an event's origin requires no window type.
"""
struct EventEnvelope
    window_id::Symbol
    event
end
