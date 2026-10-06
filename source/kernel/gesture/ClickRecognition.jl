# Fragment of `GestureModule` — the recognition of a click with its count.

"""
    ClickRecognition(; click_max_displacement = 5, click_max_duration = 0.3,
                       multi_click_max_displacement = 5, multi_click_max_interval = 0.3)

A `MouseClick` after a `MouseUp` less than `click_max_displacement` pixels away
from the `MouseDown` of its button, in the same window, at the place and the
time of the up. No check reads `click_max_duration`; the comment on `_is_click`
says why. A click is the next click of a double or a triple click when it is
less than `multi_click_max_displacement` pixels and `multi_click_max_interval`
seconds away from the click before it, with the same button in the same window. The defaults are the usual values of a
desktop. The recognition holds no input.

Each limit is a number, or a cell that the recognition reads at each input, so
a setting changes it while the editor runs.
"""
struct ClickRecognition <: GestureRecognition
    click_max_displacement::Union{Int, AbstractCell}
    click_max_duration::Union{Float64, AbstractCell}
    multi_click_max_displacement::Union{Int, AbstractCell}
    multi_click_max_interval::Union{Float64, AbstractCell}
end

ClickRecognition(; click_max_displacement::Union{Integer, AbstractCell} = 5,
                   click_max_duration::Union{Real, AbstractCell} = 0.3,
                   multi_click_max_displacement::Union{Integer, AbstractCell} = 5,
                   multi_click_max_interval::Union{Real, AbstractCell} = 0.3) =
    ClickRecognition(_make_limit(Int, click_max_displacement),
                     _make_limit(Float64, click_max_duration),
                     _make_limit(Int, multi_click_max_displacement),
                     _make_limit(Float64, multi_click_max_interval))

_make_limit(::Type{T}, limit::Real) where {T} = T(limit)
_make_limit(::Type, limit::AbstractCell) = limit

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
    press = _ButtonPress(event.button, window, event.x, event.y, get_event_time(event))
    RecognitionStep(_ClickState((_remove_press(state.presses, event.button)..., press),
                                state.last_click))
end

function recognize(recognition::ClickRecognition, state::_ClickState, event::MouseUp,
                   window)
    press = _find_press(state.presses, event.button)
    press === nothing && return RecognitionStep(state)
    presses = _remove_press(state.presses, event.button)
    _is_click(recognition, press, event, window) ||
        return RecognitionStep(_ClickState(presses, state.last_click))
    count = _count_click(recognition, state.last_click, event, window)
    now = get_event_time(event)
    click = MouseClick(event.button, event.x, event.y, count, event.modifiers; time = now)
    last_click = _Click(event.button, window, event.x, event.y, now, count)
    RecognitionStep(_ClickState(presses, last_click); inputs = [WindowInput(window, click)])
end

# Whether an up in `window` is inside the click window of `press`.
#
# THE TIME OF THE PRESS IS NOT CHECKED. SDL2 stamps a button event with the time
# at which `SDL_PumpEvents` takes it from the queue of the window system, not the
# time at which the hand moved. A frame that runs between the down and the up
# makes the up late by the length of that frame. The first press of a new process
# compiles the path of a press, which makes the up about 400 ms late, and the
# check then drops the first click in the Files pane or the toolbar. SDL3 on X11
# stamps an event the same way.
#
# Put the check back when the backend stamps a button event with the time of the
# device, for example `xbutton.time` of the X11 event, so that a frame between
# the down and the up does not move that time. Even then, with the check a held
# press is no click, and toolkits such as GTK and Qt have no such limit.
_is_click(recognition::ClickRecognition, press::_ButtonPress, event::MouseUp, window) =
    press.window === window &&
    abs(event.x - press.x) < _get_limit(recognition.click_max_displacement) &&
    abs(event.y - press.y) < _get_limit(recognition.click_max_displacement)
    # && (get_event_time(event) - press.time) < _get_limit(recognition.click_max_duration)

# The count of the click that `event` completes: one higher than the last click
# when it has the same button and window and is inside the window of a double
# click after it, else 1.
function _count_click(recognition::ClickRecognition, last, event::MouseUp, window)
    last === nothing && return 1
    last.window === window && last.button === event.button &&
        abs(event.x - last.x) < _get_limit(recognition.multi_click_max_displacement) &&
        abs(event.y - last.y) < _get_limit(recognition.multi_click_max_displacement) &&
        (get_event_time(event) - last.time) <
            _get_limit(recognition.multi_click_max_interval) ||
        return 1
    last.count + 1
end
