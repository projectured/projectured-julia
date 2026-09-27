# Fragment of `GestureTrackingModule` — the projection that recognizes the
# gestures of the devices.

"""
    GestureTrackingProjection(; inner, chords = Vector{Vector{KeyDown}}(),
                                click_max_displacement = 5, click_max_duration = 0.3,
                                multi_click_max_displacement = 5,
                                multi_click_max_interval = 0.3, dwell_delay = 0.5)

Show the content of a [`GestureTrackingState`](@ref) through `inner`, and give
the content each event of the devices and the gestures that the events make:

- **A click.** A `MouseUp` less than `click_max_displacement` pixels and
  `click_max_duration` seconds away from the `MouseDown` of its button, in the
  same window, is followed by a `MouseClick` at its place and time. A click is
  the next click of a double or a triple click when it is less than
  `multi_click_max_displacement` pixels and `multi_click_max_interval` seconds
  away from the click before it, with the same button in the same window.
- **A key chord.** `chords` is the chord table, and each entry is a sequence of
  `KeyDown`s that match on the key and the modifiers. The projection keeps a key
  that continues a sequence, and gives a `KeyChord` in place of the key that
  completes it. A key that breaks the chord gives out the kept keys and itself,
  in order, as ordinary keys. The table is empty by default, so every key goes to
  the content.
- **A mouse dwell.** A `MouseDwell` follows a motion with no button held when
  the pointer does not move for `dwell_delay` seconds. A motion with a button
  held, a down, a click, a scroll and the leave of the window stop the wait. One
  motion gives at most one dwell.

The times are the times of the events, so a slow frame does not lengthen a
click, and a replay gives the same gestures. A gesture reaches the content after
the operation of the event that completes it: the state keeps it, and a timer of
the editor brings it in at the time of that event.
"""
struct GestureTrackingProjection <: Projection
    inner::Projection
    chords::Vector{Vector{KeyDown}}
    click_max_displacement::Int
    click_max_duration::Float64
    multi_click_max_displacement::Int
    multi_click_max_interval::Float64
    dwell_delay::Float64
end

GestureTrackingProjection(; inner::Projection,
                            chords::Vector{Vector{KeyDown}} = Vector{Vector{KeyDown}}(),
                            click_max_displacement::Integer = 5,
                            click_max_duration::Real = 0.3,
                            multi_click_max_displacement::Integer = 5,
                            multi_click_max_interval::Real = 0.3,
                            dwell_delay::Real = 0.5) =
    GestureTrackingProjection(inner, chords, click_max_displacement,
                              Float64(click_max_duration), multi_click_max_displacement,
                              Float64(multi_click_max_interval), Float64(dwell_delay))

# The timers of the editor that bring in a waiting gesture and a dwell.
const _WAITING_TIMER = :gesture_tracking_waiting
const _DWELL_TIMER = :gesture_tracking_dwell

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct GestureTrackingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::GestureTrackingIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::GestureTrackingProjection, recursion, input::GestureTrackingState,
                        ctx)
    child = reconcile_child_iomap(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    GestureTrackingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::GestureTrackingProjection, recursion, change::Intent,
                     iomap::GestureTrackingIoMap)
    change.route === nothing || return read_routed_child(recursion, change, iomap)
    input = change.gesture
    input isa WindowInput && return _read_window_input(p, recursion, change, iomap, input)
    input isa TimerExpire && return _read_timer(p, recursion, change, iomap, input)
    Intent(input, _read_content(p, recursion, change, iomap))
end

read_intent(p::GestureTrackingProjection, iomap::GestureTrackingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::GestureTrackingProjection, recursion, change::Intent,
                       iomap::GestureTrackingIoMap)
    child = iomap.child_iomap
    answer = read_intent(p.inner, recursion, change, child)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

_read_content(p::GestureTrackingProjection, recursion, input::WindowInput,
              iomap::GestureTrackingIoMap) =
    _read_content(p, recursion, Intent(input, nothing), iomap)

# A write of one field of the state, which a history does not record.
_write_state(state::GestureTrackingState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# Keep `input` for the content after the operation of this read: a timer at `time`
# brings it in.
_wait_for_content(state::GestureTrackingState, inputs, time::Float64) =
    (_write_state(state, "waiting", (state.waiting..., inputs...)),
     SetTimerOperation(_WAITING_TIMER, time))

# The wait for a dwell stops, when one is on.
_stop_dwell(state::GestureTrackingState) =
    state.motion === nothing ? nothing : _write_state(state, "motion", nothing)

function _read_window_input(p::GestureTrackingProjection, recursion, change::Intent,
                            iomap::GestureTrackingIoMap, window_input::WindowInput)
    state = iomap.input
    event = window_input.event
    if event isa MouseDown
        press = _ButtonPress(event.button, window_input.window_id, event.x, event.y, event.time)
        presses = (_remove_press(state.presses, event.button)..., press)
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, change, iomap),
                                       _write_state(state, "presses", presses),
                                       _stop_dwell(state)))
    elseif event isa MouseUp
        return Intent(change.gesture, _read_mouse_up(p, recursion, change, iomap, window_input))
    elseif event isa KeyDown && !isempty(p.chords)
        return _read_chord_key(p, recursion, change, iomap, window_input)
    elseif event isa MouseMove
        motion = event.buttons == MouseButtons() ?
            (_write_state(state, "motion",
                          _Motion(window_input.window_id, event.x, event.y, event.modifiers,
                                  event.time)),
             SetTimerOperation(_DWELL_TIMER, event.time + p.dwell_delay)) :
            (_stop_dwell(state),)
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, change, iomap), motion...))
    elseif event isa Union{MouseScroll,MouseClick,WindowLeave}
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, change, iomap),
                                       _stop_dwell(state)))
    end
    Intent(change.gesture, _read_content(p, recursion, change, iomap))
end

# ── The click ─────────────────────────────────────────────────────────────

_remove_press(presses, button::Symbol) = Tuple(press for press in presses if press.button !== button)

function _find_press(presses, button::Symbol)
    for press in presses
        press.button === button && return press
    end
    nothing
end

# The content reads the up now, and the click after the operation of the up.
function _read_mouse_up(p::GestureTrackingProjection, recursion, change::Intent,
                        iomap::GestureTrackingIoMap, window_input::WindowInput)
    state = iomap.input
    event = window_input.event
    press = _find_press(state.presses, event.button)
    content = _read_content(p, recursion, change, iomap)
    press === nothing && return content
    release = _write_state(state, "presses", _remove_press(state.presses, event.button))
    _is_click(p, press, window_input) || return _join_operations(content, release)
    count = _count_click(p, state.last_click, window_input)
    click = WindowInput(window_input.window_id,
                        MouseClick(event.button, event.x, event.y, count, event.modifiers;
                                   time = event.time))
    last_click = _Click(event.button, window_input.window_id, event.x, event.y, event.time,
                        count)
    _join_operations(content, release, _write_state(state, "last_click", last_click),
                     _wait_for_content(state, (click,), event.time)...)
end

# Whether the up of `window_input` is inside the click window of `press`.
function _is_click(p::GestureTrackingProjection, press::_ButtonPress, window_input::WindowInput)
    event = window_input.event
    press.window_id === window_input.window_id &&
        abs(event.x - press.x) < p.click_max_displacement &&
        abs(event.y - press.y) < p.click_max_displacement &&
        (event.time - press.time) < p.click_max_duration
end

# The count of the click that the up of `window_input` completes: one higher than
# the last click when it has the same button and window and is inside the window
# of a double click after it, else 1.
function _count_click(p::GestureTrackingProjection, last, window_input::WindowInput)
    event = window_input.event
    last === nothing && return 1
    last.window_id === window_input.window_id && last.button === event.button &&
        abs(event.x - last.x) < p.multi_click_max_displacement &&
        abs(event.y - last.y) < p.multi_click_max_displacement &&
        (event.time - last.time) < p.multi_click_max_interval || return 1
    last.count + 1
end

# ── The chord ─────────────────────────────────────────────────────────────

function _read_chord_key(p::GestureTrackingProjection, recursion, change::Intent,
                         iomap::GestureTrackingIoMap, window_input::WindowInput)
    state = iomap.input
    event = window_input.event
    kept = state.chord_keys
    # A repeated key neither starts nor continues a chord, and it is dropped while
    # the keys of a chord are kept.
    if event.repeat
        isempty(kept) || return Intent(change.gesture, nothing)
        return Intent(change.gesture, _read_content(p, recursion, change, iomap))
    end
    keys = (kept..., window_input)
    if any(chord -> _is_chord_prefix(keys, chord), p.chords)
        any(chord -> length(chord) == length(keys) && _is_chord_prefix(keys, chord),
            p.chords) || return Intent(change.gesture, _write_state(state, "chord_keys", keys))
        chord = WindowInput(first(keys).window_id,
                            KeyChord(KeyDown[key.event for key in keys]; time = event.time))
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, chord, iomap),
                                       _write_state(state, "chord_keys", ())))
    end
    # The key breaks the chord: the kept keys and this key go to the content as
    # ordinary keys, in order, and this key does not start a new chord.
    isempty(kept) && return Intent(change.gesture, _read_content(p, recursion, change, iomap))
    Intent(change.gesture,
           _join_operations(_read_content(p, recursion, first(kept), iomap),
                            _write_state(state, "chord_keys", ()),
                            _wait_for_content(state, (kept[2:end]..., window_input),
                                              event.time)...))
end

# Whether the keys of `keys` are the first steps of `chord`: the same key and
# modifiers, whatever the `repeat` flag.
function _is_chord_prefix(keys, chord::Vector{KeyDown})
    length(keys) <= length(chord) || return false
    all(i -> chord[i].key == keys[i].event.key && chord[i].modifiers == keys[i].event.modifiers,
        eachindex(keys))
end

# ── The timers ────────────────────────────────────────────────────────────

function _read_timer(p::GestureTrackingProjection, recursion, change::Intent,
                     iomap::GestureTrackingIoMap, timer::TimerExpire)
    state = iomap.input
    if timer.name === _WAITING_TIMER
        isempty(state.waiting) && return Intent(change.gesture, nothing)
        next, rest = first(state.waiting), Base.tail(state.waiting)
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, next, iomap),
                                       _write_state(state, "waiting", rest),
                                       isempty(rest) ? nothing :
                                           SetTimerOperation(_WAITING_TIMER, timer.time)))
    elseif timer.name === _DWELL_TIMER
        motion = state.motion
        (motion === nothing || timer.time < motion.time + p.dwell_delay) &&
            return Intent(change.gesture, nothing)
        dwell = WindowInput(motion.window_id,
                            MouseDwell(motion.x, motion.y, motion.modifiers; time = timer.time))
        return Intent(change.gesture,
                      _join_operations(_read_content(p, recursion, dwell, iomap),
                                       _write_state(state, "motion", nothing)))
    end
    Intent(change.gesture, _read_content(p, recursion, change, iomap))
end

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::GestureTrackingProjection, iomap::GestureTrackingIoMap,
                               reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::GestureTrackingProjection, iomap::GestureTrackingIoMap,
                                reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
