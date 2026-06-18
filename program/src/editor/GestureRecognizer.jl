"""
    GestureRecognizerModule

The **event → gesture** transformation stage. It sits between the backend's raw
device-event stream and the projection reader pipeline, and is the place where
*combinations and sequences of raw events* are recognised as a single gesture.

## Why a separate stage

The backend emits low-level, backend-agnostic input events (`KeyDown`,
`KeyPress`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseScroll`). Most of these
are already meaningful on their own and pass straight through — they *are* the
normalized gesture vocabulary the readers match. But some gestures only exist as
a *combination* of several events:

- a **click** (`MousePress`) is a `MouseDown` followed by a `MouseUp` at
  approximately the same place within a short time window;
- (future) a **double/triple-click**, a **drag** (down → move… → up), a
  **chord** (a recognised key sequence).

Recognising these requires state that spans multiple events, which the pull-based
reactive projection pipeline cannot hold. So recognition lives here, in a small
stateful component the editor owns and drives once per input event.

This used to be done inside the SDL backend (it synthesised `MousePress`
itself). Moving it here makes recognition backend-agnostic and unit-testable
without SDL, and gives composite gestures (drag, chords, multi-click) a single
home for later.

## Contract

- [`recognize!`](@ref)`(rec, env)` consumes one `EventEnvelope`, updates the
  recogniser's state, may enqueue *synthesised* gesture envelopes (e.g. a
  `MousePress` once a click completes), and returns the envelope to forward now
  (the original event, unchanged, in this stage).
- [`next_gesture!`](@ref)`(rec, source)` is the editor-facing pull: it drains any
  previously-synthesised gestures first, otherwise pulls the next raw envelope
  from `source` and runs it through `recognize!`. This mirrors how the backend
  used to deliver its pending synthesised events before polling — the ordering
  the readers observe is unchanged.
"""
module GestureRecognizerModule

import ..MouseModule: MouseDown, MouseUp, MousePress
import ..ScreenDocumentModule: EventEnvelope

export GestureRecognizer, recognize!, next_gesture!

# Click recognition window: a MouseUp counts as a click (synthesises a
# `MousePress`) when it lands within this many pixels of the preceding MouseDown
# for the same button, within this many seconds. These mirror the thresholds the
# SDL backend previously used.
const CLICK_MAX_DISPLACEMENT = 5
const CLICK_MAX_DURATION = 0.3

"""
    GestureRecognizer(; clock = time)

Stateful event → gesture recogniser. Holds the pending queue of synthesised
gesture envelopes (drained before new input is read) plus the last-MouseDown
state used to recognise clicks.

`clock` is the time source used for the click duration window; it defaults to
`time` and is injectable so tests can drive recognition deterministically.
"""
mutable struct GestureRecognizer
    # Synthesised gesture envelopes awaiting delivery (e.g. a recognised click),
    # drained before the next raw event is pulled.
    pending::Vector{EventEnvelope}
    # Last MouseDown, for click recognition.
    last_down_button::Symbol
    last_down_x::Int
    last_down_y::Int
    last_down_time::Float64
    # Time source (injectable for tests).
    clock::Function
end

GestureRecognizer(; clock::Function = time) =
    GestureRecognizer(EventEnvelope[], :none, 0, 0, 0.0, clock)

"""
    recognize!(rec::GestureRecognizer, env::EventEnvelope) -> EventEnvelope

Feed one raw input envelope through the recogniser. Updates recognition state
and, when an event *completes* a composite gesture, enqueues the synthesised
gesture on `rec.pending` for later delivery. Returns the envelope to forward for
this event now — currently the original event unchanged (the recogniser augments
the stream with composites rather than rewriting individual events).

Recognised today:

- `MouseDown` — records the press position/time as the start of a potential click.
- `MouseUp` — if it lands within [`CLICK_MAX_DISPLACEMENT`] px and
  [`CLICK_MAX_DURATION`] s of the matching-button `MouseDown`, enqueues a
  `MousePress` (the click gesture) carrying the up position, modifiers, and the
  originating window id.
"""
function recognize!(rec::GestureRecognizer, env::EventEnvelope)
    evt = env.event
    if evt isa MouseDown
        rec.last_down_button = evt.button
        rec.last_down_x = evt.x
        rec.last_down_y = evt.y
        rec.last_down_time = rec.clock()
    elseif evt isa MouseUp
        if evt.button == rec.last_down_button &&
           abs(evt.x - rec.last_down_x) < CLICK_MAX_DISPLACEMENT &&
           abs(evt.y - rec.last_down_y) < CLICK_MAX_DISPLACEMENT &&
           (rec.clock() - rec.last_down_time) < CLICK_MAX_DURATION
            push!(rec.pending,
                  EventEnvelope(env.window_id,
                                MousePress(evt.button, evt.x, evt.y, evt.modifiers)))
        end
    end
    return env
end

"""
    next_gesture!(rec::GestureRecognizer, source) -> EventEnvelope or nothing

Pull the next gesture envelope to feed the reader pipeline. `source` is a 0-arg
callable returning the next raw `EventEnvelope` (or `nothing` when the input
queue is empty) — the editor passes a closure over the backend's
`read_from_devices`, tests pass a scripted source.

Previously-synthesised gestures (in `rec.pending`) are delivered first, ahead of
new raw input — matching the backend's old "deliver pending before polling"
behaviour, so the order readers observe (e.g. `MouseUp` then the synthesised
`MousePress`) is preserved. A `nothing` from `source` is propagated. Non-envelope
payloads, should any arise, pass through untouched.
"""
function next_gesture!(rec::GestureRecognizer, source)
    isempty(rec.pending) || return popfirst!(rec.pending)
    env = source()
    env === nothing && return nothing
    env isa EventEnvelope || return env
    return recognize!(rec, env)
end

end # module
