"""
    GestureRecognizerModule

The **event → gesture** transformation stage. It sits between the raw device-event
stream and whoever consumes it, and is the place where *combinations and sequences
of raw events* are recognised as a single gesture.

## Why a separate stage

An event source emits low-level, backend-agnostic input events (`KeyDown`,
`KeyPress`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseScroll`). Most of these are
already meaningful on their own and pass straight through — they *are* the
normalized gesture vocabulary. But some gestures only exist as a *combination* of
several events:

- a **click** (`MousePress`) is a `MouseDown` followed by a `MouseUp` at
  approximately the same place within a short time window;
- a **double/triple-click** is several clicks in quick succession — the recognised
  `MousePress` carries a `count`;
- a **key chord** (`KeyChord`) is a recognised *sequence* of `KeyDown`s, e.g.
  `Ctrl-C Ctrl-K`;
- (future) a **drag** (down → move… → up).

Recognising these requires state that spans several events, which a pull-based
reactive pipeline cannot hold. So recognition lives here, in a small stateful
component driven once per input event.

A gesture is *only* a combination of events — it carries no intent. The recogniser
never decides what a click or a chord *means*. Recognising here rather than inside
a backend makes it backend-agnostic and unit-testable without a display, and gives
composite gestures a single home.

## Contract

- [`recognize_gesture!`](@ref)`(recognizer, envelope)` consumes one `WindowInput`,
  updates the recogniser's state, may enqueue *synthesised* gesture envelopes (e.g. a
  `MousePress` once a click completes) on `recognizer.pending`, and returns either the
  envelope to forward now or `nothing` when the event was *absorbed* (e.g. the first
  key of a not-yet-complete chord).
- [`pop_gesture!`](@ref)`(recognizer, source)` is the consumer-facing pull: it drains
  any previously-synthesised gestures first, otherwise pulls raw envelopes from
  `source` and runs them through `recognize_gesture!`, skipping absorbed events until
  one produces a gesture (or input runs out). A buffered chord prefix is therefore
  swallowed *inside* a single `pop_gesture!` call and never surfaces as the "input
  exhausted" `nothing`.

The recogniser holds all of its state on its own instance, so one process can run
any number of them independently.
"""
module GestureRecognizerModule

using ..EventModule

export GestureRecognizer, recognize_gesture!, pop_gesture!

# Click recognition window: a MouseUp counts as a click (synthesises a
# `MousePress`) when it lands within this many pixels of the preceding MouseDown
# for the same button, within this many seconds.
const CLICK_MAX_DISPLACEMENT = 5
const CLICK_MAX_DURATION = 0.3

# Multi-click window: a freshly-recognised click counts as a continuation of the
# previous one (incrementing the `MousePress` count) when it is the same button,
# within this many pixels of the previous click, within this many seconds of it.
const MULTI_CLICK_MAX_DISPLACEMENT = 5
const MULTI_CLICK_MAX_INTERVAL = 0.3

"""
    GestureRecognizer(; clock = time, chords = Vector{Vector{KeyDown}}())

Stateful event → gesture recogniser. Holds the pending queue of synthesised gesture
envelopes (drained before new input is read), the last-MouseDown and last-click
state used to recognise clicks and multi-clicks, and the chord table plus its
in-progress buffer.

`clock` is the time source used for the click windows; it defaults to `time` and is
injectable so tests can drive recognition deterministically.

`chords` is the chord table: a list of recognised `KeyDown` sequences (each a
`Vector{KeyDown}`; only `key` + modifiers are compared, the `repeat` flag is
ignored). It defaults to **empty**, so no chords are recognised and every key passes
straight through — chord recognition is opt-in, configured per recogniser. The table
says only *which* sequences are a chord, not what they mean.
"""
mutable struct GestureRecognizer
    # Synthesised gesture envelopes awaiting delivery (e.g. a recognised click),
    # drained before the next raw event is pulled.
    pending::Vector{WindowInput}
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
    chord_buffer::Vector{WindowInput}
    # Time source (injectable for tests).
    clock::Function
end

GestureRecognizer(; clock::Function = time,
                    chords::Vector{Vector{KeyDown}} = Vector{Vector{KeyDown}}()) =
    GestureRecognizer(WindowInput[],
                      :none, 0, 0, 0.0,
                      :none, 0, 0, 0.0, 0,
                      chords, WindowInput[],
                      clock)

"""
    recognize_gesture!(recognizer::GestureRecognizer, envelope::WindowInput) -> WindowInput or nothing

Feed one raw input envelope through the recogniser. Updates recognition state and,
when an event *completes* a composite gesture, either enqueues the synthesised
gesture on `recognizer.pending` for later delivery (clicks) or returns it directly
(chords). Returns the envelope to forward for this event now, or `nothing` when the
event is *absorbed* (the first key of a not-yet-complete chord) — `pop_gesture!`
skips over such absorbed events.

Recognised today:

- `MouseDown` — records the press position/time as the start of a potential click.
- `MouseUp` — if it lands within [`CLICK_MAX_DISPLACEMENT`] px and
  [`CLICK_MAX_DURATION`] s of the matching-button `MouseDown`, enqueues a
  `MousePress` carrying the up position, modifiers, originating window id, and a
  multi-click `count` (2/3/… when within [`MULTI_CLICK_MAX_INTERVAL`] s /
  [`MULTI_CLICK_MAX_DISPLACEMENT`] px of the previous click).
- `KeyDown` — if the chord table is non-empty, advances chord recognition: buffers a
  key that is a prefix of some configured sequence (absorbed → returns `nothing`),
  emits a `KeyChord` when a sequence completes, or flushes the buffered keys back as
  ordinary events when a key breaks the in-progress chord.
"""
function recognize_gesture!(recognizer::GestureRecognizer, envelope::WindowInput)
    event = envelope.event
    if event isa MouseDown
        recognizer.last_down_button = event.button
        recognizer.last_down_x = event.x
        recognizer.last_down_y = event.y
        recognizer.last_down_time = recognizer.clock()
        return envelope
    elseif event isa MouseUp
        now = recognizer.clock()
        if event.button == recognizer.last_down_button &&
           abs(event.x - recognizer.last_down_x) < CLICK_MAX_DISPLACEMENT &&
           abs(event.y - recognizer.last_down_y) < CLICK_MAX_DISPLACEMENT &&
           (now - recognizer.last_down_time) < CLICK_MAX_DURATION
            count = _click_count!(recognizer, event, now)
            push!(recognizer.pending,
                  WindowInput(envelope.window_id,
                                MousePress(event.button, event.x, event.y, count, event.modifiers)))
        end
        return envelope
    elseif event isa KeyDown
        return _recognize_key!(recognizer, envelope, event)
    else
        return envelope
    end
end

# Compute and record the multi-click count for a click that just completed at
# `event` (time `now`). A click continues the previous one — same button, within the
# multi-click window/displacement — incrementing the count; otherwise it resets to 1.
function _click_count!(recognizer::GestureRecognizer, event::MouseUp, now::Float64)
    if event.button == recognizer.last_click_button &&
       abs(event.x - recognizer.last_click_x) < MULTI_CLICK_MAX_DISPLACEMENT &&
       abs(event.y - recognizer.last_click_y) < MULTI_CLICK_MAX_DISPLACEMENT &&
       (now - recognizer.last_click_time) < MULTI_CLICK_MAX_INTERVAL
        count = recognizer.last_click_count + 1
    else
        count = 1
    end
    recognizer.last_click_button = event.button
    recognizer.last_click_x = event.x
    recognizer.last_click_y = event.y
    recognizer.last_click_time = now
    recognizer.last_click_count = count
    return count
end

# Advance chord recognition for one KeyDown. Returns the envelope to forward now, or
# `nothing` when the key is absorbed into an in-progress chord.
function _recognize_key!(recognizer::GestureRecognizer, envelope::WindowInput, event::KeyDown)
    # Chords disabled (the common case): every key passes straight through.
    isempty(recognizer.chords) && return envelope
    # Auto-repeat never starts or extends a chord; ignore it while buffering.
    if event.repeat
        return isempty(recognizer.chord_buffer) ? envelope : nothing
    end
    push!(recognizer.chord_buffer, envelope)
    if any(c -> _chord_is_prefix(recognizer.chord_buffer, c), recognizer.chords)
        if any(c -> _chord_is_complete(recognizer.chord_buffer, c), recognizer.chords)
            keys = KeyDown[b.event for b in recognizer.chord_buffer]
            window_id = recognizer.chord_buffer[1].window_id
            empty!(recognizer.chord_buffer)
            return WindowInput(window_id, KeyChord(keys))
        end
        return nothing                       # valid prefix, still waiting
    end
    # This key breaks the in-progress chord. Flush the buffered prefix and this key as
    # ordinary events, in order (the breaking key is emitted raw and does not itself
    # start a new chord — a deliberate simplification).
    pop!(recognizer.chord_buffer)             # remove the just-added breaking key
    flushed = recognizer.chord_buffer
    recognizer.chord_buffer = WindowInput[]
    isempty(flushed) && return envelope       # no prefix was pending
    append!(recognizer.pending, flushed[2:end])
    push!(recognizer.pending, envelope)
    return flushed[1]
end

# Does `buffer` match the first `length(buffer)` steps of chord `chord`?
function _chord_is_prefix(buffer::Vector{WindowInput}, chord::Vector{KeyDown})
    length(buffer) <= length(chord) || return false
    for i in eachindex(buffer)
        _keydown_matches(chord[i], buffer[i].event) || return false
    end
    return true
end

_chord_is_complete(buffer::Vector{WindowInput}, chord::Vector{KeyDown}) =
    length(buffer) == length(chord) && _chord_is_prefix(buffer, chord)

# A chord step matches a key on `key` + modifiers; the `repeat` flag is ignored.
_keydown_matches(spec::KeyDown, e::KeyDown) =
    spec.key == e.key &&
    spec.modifiers.ctrl  == e.modifiers.ctrl  &&
    spec.modifiers.shift == e.modifiers.shift &&
    spec.modifiers.alt   == e.modifiers.alt   &&
    spec.modifiers.meta  == e.modifiers.meta

"""
    pop_gesture!(recognizer::GestureRecognizer, source) -> WindowInput or nothing

Pull the next gesture envelope to feed the consumer. `source` is a 0-arg callable
returning the next raw `WindowInput` (or `nothing` when the input queue is empty)
— a caller polling devices passes a closure over that poll, a test passes a scripted
source.

Previously-synthesised gestures (in `recognizer.pending`) are delivered first, ahead
of new raw input, so the order a consumer observes (e.g. `MouseUp` then the
synthesised `MousePress`) is preserved. New raw input is then run through
`recognize_gesture!`; an *absorbed* event (a buffered chord prefix, for which
`recognize_gesture!` returns `nothing`) is skipped and the next event pulled, so a
partial chord never surfaces as the "input exhausted" `nothing`. A `nothing` from
`source` (genuine exhaustion) is propagated. Non-envelope payloads, should any arise,
pass through untouched.
"""
function pop_gesture!(recognizer::GestureRecognizer, source)
    while true
        isempty(recognizer.pending) || return popfirst!(recognizer.pending)
        envelope = source()
        envelope === nothing && return nothing
        envelope isa WindowInput || return envelope
        gesture = recognize_gesture!(recognizer, envelope)
        gesture === nothing && continue       # absorbed (e.g. chord prefix)
        return gesture
    end
end

end # module
