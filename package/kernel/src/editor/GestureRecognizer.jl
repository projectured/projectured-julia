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
- a **double/triple-click** is several clicks in quick succession — the
  recognised `MousePress` carries a `count`;
- a **key chord** (`KeyChord`) is a recognised *sequence* of `KeyDown`s, e.g.
  `Ctrl-C Ctrl-K`;
- (future) a **drag** (down → move… → up).

Recognising these requires state that spans multiple events, which the pull-based
reactive projection pipeline cannot hold. So recognition lives here, in a small
stateful component the editor owns and drives once per input event.

A gesture is *only* a combination of events — it carries no intent. The
recogniser never decides what a click or a chord *means*; that is each projection
reader's job. This used to be done (for clicks) inside the SDL backend; moving it
here makes recognition backend-agnostic and unit-testable without SDL, and gives
composite gestures a single home.

## Contract

- [`recognize!`](@ref)`(rec, env)` consumes one `EventEnvelope`, updates the
  recogniser's state, may enqueue *synthesised* gesture envelopes (e.g. a
  `MousePress` once a click completes) on `rec.pending`, and returns either the
  envelope to forward now or `nothing` when the event was *absorbed* (e.g. the
  first key of a not-yet-complete chord).
- [`next_gesture!`](@ref)`(rec, source)` is the editor-facing pull: it drains any
  previously-synthesised gestures first, otherwise pulls raw envelopes from
  `source` and runs them through `recognize!`, skipping absorbed events until one
  produces a gesture (or input runs out). A buffered chord prefix is therefore
  swallowed *inside* a single `next_gesture!` call and never surfaces to the
  editor as the "input exhausted" `nothing`.
"""
module GestureRecognizerModule

import ..MouseModule: MouseDown, MouseUp, MousePress
import ..KeyboardModule: KeyDown, KeyChord
import ..ScreenDocumentModule: EventEnvelope

export GestureRecognizer, recognize!, next_gesture!

# Click recognition window: a MouseUp counts as a click (synthesises a
# `MousePress`) when it lands within this many pixels of the preceding MouseDown
# for the same button, within this many seconds. These mirror the thresholds the
# SDL backend previously used.
const CLICK_MAX_DISPLACEMENT = 5
const CLICK_MAX_DURATION = 0.3

# Multi-click window: a freshly-recognised click counts as a continuation of the
# previous one (incrementing the `MousePress` count) when it is the same button,
# within this many pixels of the previous click, within this many seconds of it.
const MULTI_CLICK_MAX_DISPLACEMENT = 5
const MULTI_CLICK_MAX_INTERVAL = 0.3

"""
    GestureRecognizer(; clock = time, chords = Vector{Vector{KeyDown}}())

Stateful event → gesture recogniser. Holds the pending queue of synthesised
gesture envelopes (drained before new input is read), the last-MouseDown and
last-click state used to recognise clicks and multi-clicks, and the chord table
plus its in-progress buffer.

`clock` is the time source used for the click windows; it defaults to `time` and
is injectable so tests can drive recognition deterministically.

`chords` is the chord table: a list of recognised `KeyDown` sequences (each a
`Vector{KeyDown}`; only `key` + modifiers are compared, the `repeat` flag is
ignored). It defaults to **empty**, so no chords are recognised and every key
passes straight through — chord recognition is opt-in, configured per editor.
The table says only *which* sequences are a chord, not what they mean.
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
    # Last recognised click, for multi-click counting.
    last_click_button::Symbol
    last_click_x::Int
    last_click_y::Int
    last_click_time::Float64
    last_click_count::Int
    # Chord recognition: the table of recognised sequences and the keys buffered
    # so far towards a (still incomplete) chord.
    chords::Vector{Vector{KeyDown}}
    chord_buffer::Vector{EventEnvelope}
    # Time source (injectable for tests).
    clock::Function
end

GestureRecognizer(; clock::Function = time,
                    chords::Vector{Vector{KeyDown}} = Vector{Vector{KeyDown}}()) =
    GestureRecognizer(EventEnvelope[],
                      :none, 0, 0, 0.0,
                      :none, 0, 0, 0.0, 0,
                      chords, EventEnvelope[],
                      clock)

"""
    recognize!(rec::GestureRecognizer, env::EventEnvelope) -> EventEnvelope or nothing

Feed one raw input envelope through the recogniser. Updates recognition state
and, when an event *completes* a composite gesture, either enqueues the
synthesised gesture on `rec.pending` for later delivery (clicks) or returns it
directly (chords). Returns the envelope to forward for this event now, or
`nothing` when the event is *absorbed* (the first key of a not-yet-complete
chord) — `next_gesture!` skips over such absorbed events.

Recognised today:

- `MouseDown` — records the press position/time as the start of a potential click.
- `MouseUp` — if it lands within [`CLICK_MAX_DISPLACEMENT`] px and
  [`CLICK_MAX_DURATION`] s of the matching-button `MouseDown`, enqueues a
  `MousePress` carrying the up position, modifiers, originating window id, and a
  multi-click `count` (2/3/… when within [`MULTI_CLICK_MAX_INTERVAL`] s /
  [`MULTI_CLICK_MAX_DISPLACEMENT`] px of the previous click).
- `KeyDown` — if the chord table is non-empty, advances chord recognition:
  buffers a key that is a prefix of some configured sequence (absorbed → returns
  `nothing`), emits a `KeyChord` when a sequence completes, or flushes the
  buffered keys back as raw events when a key breaks the in-progress chord.
"""
function recognize!(rec::GestureRecognizer, env::EventEnvelope)
    evt = env.event
    if evt isa MouseDown
        rec.last_down_button = evt.button
        rec.last_down_x = evt.x
        rec.last_down_y = evt.y
        rec.last_down_time = rec.clock()
        return env
    elseif evt isa MouseUp
        now = rec.clock()
        if evt.button == rec.last_down_button &&
           abs(evt.x - rec.last_down_x) < CLICK_MAX_DISPLACEMENT &&
           abs(evt.y - rec.last_down_y) < CLICK_MAX_DISPLACEMENT &&
           (now - rec.last_down_time) < CLICK_MAX_DURATION
            count = _click_count!(rec, evt, now)
            push!(rec.pending,
                  EventEnvelope(env.window_id,
                                MousePress(evt.button, evt.x, evt.y, count, evt.modifiers)))
        end
        return env
    elseif evt isa KeyDown
        return _recognize_key!(rec, env, evt)
    else
        return env
    end
end

# Compute and record the multi-click count for a click that just completed at
# `evt` (time `now`). A click continues the previous one — same button, within
# the multi-click window/displacement — incrementing the count; otherwise it
# resets to 1.
function _click_count!(rec::GestureRecognizer, evt::MouseUp, now::Float64)
    if evt.button == rec.last_click_button &&
       abs(evt.x - rec.last_click_x) < MULTI_CLICK_MAX_DISPLACEMENT &&
       abs(evt.y - rec.last_click_y) < MULTI_CLICK_MAX_DISPLACEMENT &&
       (now - rec.last_click_time) < MULTI_CLICK_MAX_INTERVAL
        count = rec.last_click_count + 1
    else
        count = 1
    end
    rec.last_click_button = evt.button
    rec.last_click_x = evt.x
    rec.last_click_y = evt.y
    rec.last_click_time = now
    rec.last_click_count = count
    return count
end

# Advance chord recognition for one KeyDown. Returns the envelope to forward now,
# or `nothing` when the key is absorbed into an in-progress chord.
function _recognize_key!(rec::GestureRecognizer, env::EventEnvelope, evt::KeyDown)
    # Chords disabled (the common case): every key passes straight through.
    isempty(rec.chords) && return env
    # Auto-repeat never starts or extends a chord; ignore it while buffering.
    if evt.repeat
        return isempty(rec.chord_buffer) ? env : nothing
    end
    push!(rec.chord_buffer, env)
    if any(c -> _chord_is_prefix(rec.chord_buffer, c), rec.chords)
        if any(c -> _chord_is_complete(rec.chord_buffer, c), rec.chords)
            keys = KeyDown[b.event for b in rec.chord_buffer]
            wid = rec.chord_buffer[1].window_id
            empty!(rec.chord_buffer)
            return EventEnvelope(wid, KeyChord(keys))
        end
        return nothing                       # valid prefix, still waiting
    end
    # This key breaks the in-progress chord. Flush the buffered prefix and this
    # key as ordinary events, in order (the breaking key is emitted raw and does
    # not itself start a new chord — a deliberate simplification).
    pop!(rec.chord_buffer)                    # remove the just-added breaking key
    flushed = rec.chord_buffer
    rec.chord_buffer = EventEnvelope[]
    isempty(flushed) && return env            # no prefix was pending
    append!(rec.pending, flushed[2:end])
    push!(rec.pending, env)
    return flushed[1]
end

# Does `buffer` match the first `length(buffer)` steps of chord `chord`?
function _chord_is_prefix(buffer::Vector{EventEnvelope}, chord::Vector{KeyDown})
    length(buffer) <= length(chord) || return false
    for i in eachindex(buffer)
        _keydown_matches(chord[i], buffer[i].event) || return false
    end
    return true
end

_chord_is_complete(buffer::Vector{EventEnvelope}, chord::Vector{KeyDown}) =
    length(buffer) == length(chord) && _chord_is_prefix(buffer, chord)

# A chord step matches a key on `key` + modifiers; the `repeat` flag is ignored.
_keydown_matches(spec::KeyDown, e::KeyDown) =
    spec.key == e.key &&
    spec.modifiers.ctrl  == e.modifiers.ctrl  &&
    spec.modifiers.shift == e.modifiers.shift &&
    spec.modifiers.alt   == e.modifiers.alt   &&
    spec.modifiers.meta  == e.modifiers.meta

"""
    next_gesture!(rec::GestureRecognizer, source) -> EventEnvelope or nothing

Pull the next gesture envelope to feed the reader pipeline. `source` is a 0-arg
callable returning the next raw `EventEnvelope` (or `nothing` when the input
queue is empty) — the editor passes a closure over the backend's
`read_from_devices`, tests pass a scripted source.

Previously-synthesised gestures (in `rec.pending`) are delivered first, ahead of
new raw input — matching the backend's old "deliver pending before polling"
behaviour, so the order readers observe (e.g. `MouseUp` then the synthesised
`MousePress`) is preserved. New raw input is then run through `recognize!`; an
*absorbed* event (a buffered chord prefix, for which `recognize!` returns
`nothing`) is skipped and the next event pulled, so a partial chord never
surfaces as the "input exhausted" `nothing`. A `nothing` from `source` (genuine
exhaustion) is propagated. Non-envelope payloads, should any arise, pass through
untouched.
"""
function next_gesture!(rec::GestureRecognizer, source)
    while true
        isempty(rec.pending) || return popfirst!(rec.pending)
        env = source()
        env === nothing && return nothing
        env isa EventEnvelope || return env
        gesture = recognize!(rec, env)
        gesture === nothing && continue       # absorbed (e.g. chord prefix)
        return gesture
    end
end

end # module
