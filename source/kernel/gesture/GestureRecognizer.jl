# Fragment of `GestureRecognizerModule` — the recognizer: the state of one editor,
# and the fold of input events into gestures.

# Where and when a `MouseDown` of one button was: the start of a click.
struct _ButtonPress
    window_id::Symbol
    x::Int
    y::Int
    time::Float64
end

# The last click: the start of a double click.
struct _Click
    window_id::Symbol
    button::Symbol
    x::Int
    y::Int
    time::Float64
    count::Int
end

"""
    GestureRecognizer(; clock = time, chords = Vector{Vector{KeyDown}}(),
                        click_max_displacement = 5, click_max_duration = 0.3,
                        multi_click_max_displacement = 5, multi_click_max_interval = 0.3)

The state of the recognition of gestures for one editor: the gestures that wait
for delivery, the press of each mouse button, the last click, the chord table
and the keys of a chord that is not complete yet.

`clock` gives the time in seconds for the click windows. It is `time` by
default, and a test gives a clock of its own.

`chords` is the chord table: each entry is a sequence of `KeyDown`s. A step
matches a key on its `key` and its modifiers, and its `repeat` flag does not
count. The table is empty by default, so every key passes through. It says only
which sequences are a chord, not what they mean.

The click windows have the usual values of a desktop by default. A `MouseUp` is
a click when it is less than `click_max_displacement` pixels and
`click_max_duration` seconds away from the `MouseDown` of its button in the same
window. A click is the next click of a double or triple click when it is less
than `multi_click_max_displacement` pixels and `multi_click_max_interval` seconds
away from the click before it, with the same button in the same window.
"""
mutable struct GestureRecognizer
    # The gestures that wait for delivery, before the next input event.
    pending::Vector{WindowInput}
    # The last `MouseDown` of each button, until its `MouseUp`.
    presses::Dict{Symbol,_ButtonPress}
    # The last click, for the count of a double or triple click.
    last_click::Union{_Click,Nothing}
    # The chord table, and the keys of a chord that is not complete yet.
    chords::Vector{Vector{KeyDown}}
    chord_buffer::Vector{WindowInput}
    # The source of the time (a test gives its own).
    clock::Function
    # The click windows (see the docstring).
    click_max_displacement::Int
    click_max_duration::Float64
    multi_click_max_displacement::Int
    multi_click_max_interval::Float64
end

GestureRecognizer(; clock::Function = time,
                    chords::Vector{Vector{KeyDown}} = Vector{Vector{KeyDown}}(),
                    click_max_displacement::Integer = 5, click_max_duration::Real = 0.3,
                    multi_click_max_displacement::Integer = 5,
                    multi_click_max_interval::Real = 0.3) =
    GestureRecognizer(WindowInput[], Dict{Symbol,_ButtonPress}(), nothing,
                      chords, WindowInput[],
                      clock,
                      click_max_displacement, Float64(click_max_duration),
                      multi_click_max_displacement, Float64(multi_click_max_interval))

"""
    recognize_gesture!(recognizer::GestureRecognizer, window_input::WindowInput)
        -> WindowInput or nothing

Give one input event to the recognizer, and answer what to deliver now: the
input itself, a gesture that it completes, or `nothing` when the recognizer
keeps the input. A gesture that follows its input waits in `recognizer.pending`.

- A `MouseDown` starts a possible click of its button.
- A `MouseUp` answers itself. When it is inside the click window of the
  `MouseDown` of its button in the same window, a `MousePress` follows it in
  `pending`, at the place of the `MouseUp`, with its modifiers, its window and
  the `count` of a double or triple click.
- A `KeyDown`, when the chord table is not empty, goes to the chord in progress.
  The recognizer keeps a key that continues a sequence of the table and answers
  `nothing`. The key that completes a sequence answers a `KeyChord`. A key that
  breaks the chord in progress answers the kept keys and itself, in order, as
  ordinary keys, and it does not start a new chord.
- Any other event answers itself.
"""
function recognize_gesture!(recognizer::GestureRecognizer, window_input::WindowInput)
    event = window_input.event
    if event isa MouseDown
        recognizer.presses[event.button] =
            _ButtonPress(window_input.window_id, event.x, event.y, recognizer.clock())
        return window_input
    elseif event isa MouseUp
        press = pop!(recognizer.presses, event.button, nothing)
        now = Float64(recognizer.clock())
        if press !== nothing && press.window_id === window_input.window_id &&
           abs(event.x - press.x) < recognizer.click_max_displacement &&
           abs(event.y - press.y) < recognizer.click_max_displacement &&
           (now - press.time) < recognizer.click_max_duration
            count = _count_click!(recognizer, window_input.window_id, event, now)
            push!(recognizer.pending,
                  WindowInput(window_input.window_id,
                              MousePress(event.button, event.x, event.y, count,
                                         event.modifiers)))
        end
        return window_input
    elseif event isa KeyDown
        return _recognize_key!(recognizer, window_input, event)
    else
        return window_input
    end
end

# The count of the click that `event` completes at the time `now`, which the
# recognizer records as its last click. A click continues the last click, with a
# count one higher, when it has the same button and window and is inside the
# double-click window of it; otherwise its count is 1.
function _count_click!(recognizer::GestureRecognizer, window_id::Symbol, event::MouseUp,
                       now::Float64)
    last = recognizer.last_click
    count = if last !== nothing && last.window_id === window_id &&
               last.button === event.button &&
               abs(event.x - last.x) < recognizer.multi_click_max_displacement &&
               abs(event.y - last.y) < recognizer.multi_click_max_displacement &&
               (now - last.time) < recognizer.multi_click_max_interval
        last.count + 1
    else
        1
    end
    recognizer.last_click = _Click(window_id, event.button, event.x, event.y, now, count)
    count
end

# One `KeyDown` of the chord in progress: answers the input to deliver now, or
# `nothing` when the recognizer keeps the key.
function _recognize_key!(recognizer::GestureRecognizer, window_input::WindowInput,
                         event::KeyDown)
    # With no chord table, every key passes through.
    isempty(recognizer.chords) && return window_input
    # A repeated key neither starts nor continues a chord, and the recognizer
    # drops it while it keeps the keys of a chord.
    if event.repeat
        return isempty(recognizer.chord_buffer) ? window_input : nothing
    end
    push!(recognizer.chord_buffer, window_input)
    if any(chord -> _is_chord_prefix(recognizer.chord_buffer, chord), recognizer.chords)
        if any(chord -> _is_chord_complete(recognizer.chord_buffer, chord),
               recognizer.chords)
            keys = KeyDown[kept.event for kept in recognizer.chord_buffer]
            window_id = recognizer.chord_buffer[1].window_id
            empty!(recognizer.chord_buffer)
            return WindowInput(window_id, KeyChord(keys))
        end
        return nothing
    end
    # The key breaks the chord in progress: the kept keys and this key go out as
    # ordinary keys, in order, and this key does not start a new chord.
    pop!(recognizer.chord_buffer)
    kept = recognizer.chord_buffer
    recognizer.chord_buffer = WindowInput[]
    isempty(kept) && return window_input
    append!(recognizer.pending, kept[2:end])
    push!(recognizer.pending, window_input)
    return kept[1]
end

# Whether the keys of `buffer` are the first steps of `chord`.
function _is_chord_prefix(buffer::Vector{WindowInput}, chord::Vector{KeyDown})
    length(buffer) <= length(chord) || return false
    for i in eachindex(buffer)
        _is_chord_step(chord[i], buffer[i].event) || return false
    end
    return true
end

_is_chord_complete(buffer::Vector{WindowInput}, chord::Vector{KeyDown}) =
    length(buffer) == length(chord) && _is_chord_prefix(buffer, chord)

# Whether `event` is the step `step` of a chord: the same key and modifiers. The
# `repeat` flag does not count.
_is_chord_step(step::KeyDown, event::KeyDown) =
    step.key == event.key && step.modifiers == event.modifiers

"""
    pop_gesture!(recognizer::GestureRecognizer, source) -> WindowInput or nothing

The next gesture for the reader. `source` is a function with no argument that
answers the next input of a backend, a `WindowInput`, or `nothing` when no input
waits. The editor gives a function over `read_from_devices`, and a test gives a
scripted source.

The gestures that wait in `recognizer.pending` come first, before a new input,
so the reader sees the order of the input: a `MouseUp`, then its `MousePress`.
A new input then goes through `recognize_gesture!`. An input that the recognizer
keeps, such as the first key of a chord, does not end the pull: the next input
follows, so a chord in progress never looks like the end of the input. A
`nothing` from `source` is the end of the input, and the answer is `nothing`.

A value from `source` that is not a `WindowInput` passes through unchanged.
The tests of the frame loop push such values through the editor.
"""
function pop_gesture!(recognizer::GestureRecognizer, source)
    while true
        isempty(recognizer.pending) || return popfirst!(recognizer.pending)
        window_input = source()
        window_input === nothing && return nothing
        window_input isa WindowInput || return window_input
        gesture = recognize_gesture!(recognizer, window_input)
        gesture === nothing && continue
        return gesture
    end
end
