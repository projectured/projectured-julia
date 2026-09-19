# Fragment of `GestureRecognizerModule` — the recognizer itself: the per-editor state and the event → gesture folding.

"""
    GestureRecognizer(; clock = time, chords = Vector{Vector{KeyDown}}(),
                        click_max_displacement = 5, click_max_duration = 0.3,
                        multi_click_max_displacement = 5, multi_click_max_interval = 0.3)

Stateful event → gesture recogniser. Holds the pending queue of synthesised gesture
window inputs (drained before new input is read), the last-MouseDown and last-click
state used to recognise clicks and multi-clicks, and the chord table plus its
in-progress buffer.

`clock` is the time source used for the click windows; it defaults to `time` and is
injectable so tests can drive recognition deterministically.

`chords` is the chord table: a list of recognised `KeyDown` sequences (each a
`Vector{KeyDown}`; only `key` + modifiers are compared, the `repeat` flag is
ignored). It defaults to **empty**, so no chords are recognised and every key passes
straight through — chord recognition is opt-in, configured per recogniser. The table
says only *which* sequences are a chord, not what they mean.

The click windows tune recognition, defaulting to the usual desktop values: a
`MouseUp` is a click when within `click_max_displacement` px and `click_max_duration`
s of its `MouseDown`, and a following click becomes a multi-click (higher `count`)
when within `multi_click_max_displacement` px and `multi_click_max_interval` s of the
previous one.
"""
mutable struct GestureRecognizer
    # Synthesised gesture window inputs awaiting delivery (e.g. a recognised click),
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
    # Recognition windows (see the constructor).
    click_max_displacement::Int
    click_max_duration::Float64
    multi_click_max_displacement::Int
    multi_click_max_interval::Float64
end

GestureRecognizer(; clock::Function = time,
                    chords::Vector{Vector{KeyDown}} = Vector{Vector{KeyDown}}(),
                    click_max_displacement::Int = 5, click_max_duration::Real = 0.3,
                    multi_click_max_displacement::Int = 5, multi_click_max_interval::Real = 0.3) =
    GestureRecognizer(WindowInput[],
                      :none, 0, 0, 0.0,
                      :none, 0, 0, 0.0, 0,
                      chords, WindowInput[],
                      clock,
                      click_max_displacement, Float64(click_max_duration),
                      multi_click_max_displacement, Float64(multi_click_max_interval))

"""
    recognize_gesture!(recognizer::GestureRecognizer, window_input::WindowInput) -> WindowInput or nothing

Feed one raw input window input through the recogniser. Updates recognition state and,
when an event *completes* a composite gesture, either enqueues the synthesised
gesture on `recognizer.pending` for later delivery (clicks) or returns it directly
(chords). Returns the window input to forward for this event now, or `nothing` when the
event is *absorbed* (the first key of a not-yet-complete chord) — `pop_gesture!`
skips over such absorbed events.

Recognised today:

- `MouseDown` — records the press position/time as the start of a potential click.
- `MouseUp` — if it lands within the recogniser's click window
  (`click_max_displacement` px, `click_max_duration` s) of the matching-button
  `MouseDown`, enqueues a `MousePress` carrying the up position, modifiers,
  originating window id, and a multi-click `count` (2/3/… within the multi-click
  window `multi_click_max_displacement` px / `multi_click_max_interval` s of the
  previous click).
- `KeyDown` — if the chord table is non-empty, advances chord recognition: buffers a
  key that is a prefix of some configured sequence (absorbed → returns `nothing`),
  emits a `KeyChord` when a sequence completes, or flushes the buffered keys back as
  ordinary events when a key breaks the in-progress chord.
"""
function recognize_gesture!(recognizer::GestureRecognizer, window_input::WindowInput)
    event = window_input.event
    if event isa MouseDown
        recognizer.last_down_button = event.button
        recognizer.last_down_x = event.x
        recognizer.last_down_y = event.y
        recognizer.last_down_time = recognizer.clock()
        return window_input
    elseif event isa MouseUp
        now = recognizer.clock()
        if event.button == recognizer.last_down_button &&
           abs(event.x - recognizer.last_down_x) < recognizer.click_max_displacement &&
           abs(event.y - recognizer.last_down_y) < recognizer.click_max_displacement &&
           (now - recognizer.last_down_time) < recognizer.click_max_duration
            count = _click_count!(recognizer, event, now)
            push!(recognizer.pending,
                  WindowInput(window_input.window_id,
                                MousePress(event.button, event.x, event.y, count, event.modifiers)))
        end
        return window_input
    elseif event isa KeyDown
        return _recognize_key!(recognizer, window_input, event)
    else
        return window_input
    end
end

# Compute and record the multi-click count for a click that just completed at
# `event` (time `now`). A click continues the previous one — same button, within the
# multi-click window/displacement — incrementing the count; otherwise it resets to 1.
function _click_count!(recognizer::GestureRecognizer, event::MouseUp, now::Float64)
    if event.button == recognizer.last_click_button &&
       abs(event.x - recognizer.last_click_x) < recognizer.multi_click_max_displacement &&
       abs(event.y - recognizer.last_click_y) < recognizer.multi_click_max_displacement &&
       (now - recognizer.last_click_time) < recognizer.multi_click_max_interval
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

# Advance chord recognition for one KeyDown. Returns the window input to forward now, or
# `nothing` when the key is absorbed into an in-progress chord.
function _recognize_key!(recognizer::GestureRecognizer, window_input::WindowInput, event::KeyDown)
    # Chords disabled (the common case): every key passes straight through.
    isempty(recognizer.chords) && return window_input
    # Auto-repeat never starts or extends a chord; ignore it while buffering.
    if event.repeat
        return isempty(recognizer.chord_buffer) ? window_input : nothing
    end
    push!(recognizer.chord_buffer, window_input)
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
    isempty(flushed) && return window_input   # no prefix was pending
    append!(recognizer.pending, flushed[2:end])
    push!(recognizer.pending, window_input)
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

Pull the next gesture window input to feed the consumer. `source` is a 0-arg callable
returning the next raw `WindowInput` (or `nothing` when the input queue is empty)
— a caller polling devices passes a closure over that poll, a test passes a scripted
source.

Previously-synthesised gestures (in `recognizer.pending`) are delivered first, ahead
of new raw input, so the order a consumer observes (e.g. `MouseUp` then the
synthesised `MousePress`) is preserved. New raw input is then run through
`recognize_gesture!`; an *absorbed* event (a buffered chord prefix, for which
`recognize_gesture!` returns `nothing`) is skipped and the next event pulled, so a
partial chord never surfaces as the "input exhausted" `nothing`. A `nothing` from
`source` (genuine exhaustion) is propagated. Non-window-input payloads, should any arise,
pass through untouched.
"""
function pop_gesture!(recognizer::GestureRecognizer, source)
    while true
        isempty(recognizer.pending) || return popfirst!(recognizer.pending)
        window_input = source()
        window_input === nothing && return nothing
        window_input isa WindowInput || return window_input
        gesture = recognize_gesture!(recognizer, window_input)
        gesture === nothing && continue       # absorbed (e.g. chord prefix)
        return gesture
    end
end
