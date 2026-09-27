# Fragment of `GestureModule` — the recognition of a click with its count.

"""
    ClickRecognition(; click_max_displacement = 5, click_max_duration = 0.3,
                       multi_click_max_displacement = 5, multi_click_max_interval = 0.3)

A `MouseClick` after a `MouseUp` less than `click_max_displacement` pixels and
`click_max_duration` seconds away from the `MouseDown` of its button, in the
same window, at the place and the time of the up. A click is the next click of a
double or a triple click when it is less than `multi_click_max_displacement`
pixels and `multi_click_max_interval` seconds away from the click before it,
with the same button in the same window. The defaults are the usual values of a
desktop. The recognition holds no input.
"""
struct ClickRecognition <: GestureRecognition
    click_max_displacement::Int
    click_max_duration::Float64
    multi_click_max_displacement::Int
    multi_click_max_interval::Float64
end

ClickRecognition(; click_max_displacement::Integer = 5, click_max_duration::Real = 0.3,
                   multi_click_max_displacement::Integer = 5,
                   multi_click_max_interval::Real = 0.3) =
    ClickRecognition(click_max_displacement, Float64(click_max_duration),
                     multi_click_max_displacement, Float64(multi_click_max_interval))

# A button that went down, and where and when: the start of a click.
struct _ButtonPress
    button::Symbol
    window::Symbol
    x::Int
    y::Int
    time::Float64
end

# The last click: the start of a double click.
struct _Click
    button::Symbol
    window::Symbol
    x::Int
    y::Int
    time::Float64
    count::Int
end

# The buttons that are down, and the last click.
struct _ClickState
    presses::Tuple
    last_click::Union{_Click,Nothing}
end

make_recognition_state(::ClickRecognition) = _ClickState((), nothing)

_remove_press(presses, button::Symbol) =
    Tuple(press for press in presses if press.button !== button)

function _find_press(presses, button::Symbol)
    for press in presses
        press.button === button && return press
    end
    nothing
end

recognize(::ClickRecognition, state::_ClickState, input, window) = RecognitionStep(state)

function recognize(::ClickRecognition, state::_ClickState, event::MouseDown, window)
    window === nothing && return RecognitionStep(state)
    press = _ButtonPress(event.button, window, event.x, event.y, event.time)
    RecognitionStep(_ClickState((_remove_press(state.presses, event.button)..., press),
                                state.last_click))
end

function recognize(recognition::ClickRecognition, state::_ClickState, event::MouseUp, window)
    press = _find_press(state.presses, event.button)
    press === nothing && return RecognitionStep(state)
    presses = _remove_press(state.presses, event.button)
    _is_click(recognition, press, event, window) ||
        return RecognitionStep(_ClickState(presses, state.last_click))
    count = _count_click(recognition, state.last_click, event, window)
    click = MouseClick(event.button, event.x, event.y, count, event.modifiers; time = event.time)
    RecognitionStep(_ClickState(presses,
                                _Click(event.button, window, event.x, event.y, event.time, count));
                    inputs = [WindowInput(window, click)])
end

# Whether an up in `window` is inside the click window of `press`.
_is_click(recognition::ClickRecognition, press::_ButtonPress, event::MouseUp, window) =
    press.window === window &&
    abs(event.x - press.x) < recognition.click_max_displacement &&
    abs(event.y - press.y) < recognition.click_max_displacement &&
    (event.time - press.time) < recognition.click_max_duration

# The count of the click that `event` completes: one higher than the last click
# when it has the same button and window and is inside the window of a double
# click after it, else 1.
function _count_click(recognition::ClickRecognition, last, event::MouseUp, window)
    last === nothing && return 1
    last.window === window && last.button === event.button &&
        abs(event.x - last.x) < recognition.multi_click_max_displacement &&
        abs(event.y - last.y) < recognition.multi_click_max_displacement &&
        (event.time - last.time) < recognition.multi_click_max_interval || return 1
    last.count + 1
end
