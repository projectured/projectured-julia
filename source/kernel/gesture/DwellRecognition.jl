# Fragment of `GestureModule` — the recognition of a mouse dwell.

"""
    DwellRecognition(; delay = 0.5)

A `MouseDwell` when the pointer does not move for `delay` seconds after a
motion with no button held, at the place of that motion and at the time when the
wait ends. A motion with a button held, a down, a click, a scroll and the leave
of the window stop the wait, and one motion gives at most one dwell. A key does
not stop it: a dwell is no motion of the mouse.

A move to the point of the last move, in the same window, is no motion: it
changes nothing. The backend sends such a move after a frame that changed a
window, so a view that changes on every frame still gets its dwell, and a still
pointer gets no second dwell and none after a press.

The recognition reads the end of the wait as a `TimerExpire` at the deadline
that the motion answered, and it holds that timer. A timer of an older motion
finds a newer one in the state and gives nothing.
"""
struct DwellRecognition <: GestureRecognition
    delay::Float64
end

DwellRecognition(; delay::Real = 0.5) = DwellRecognition(Float64(delay))

# The last motion in a window, and whether a dwell can still follow it: only a
# motion with no button held that gave no dwell yet and that no press followed.
struct _Motion
    window::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
    is_waiting::Bool
end

# The motion of `motion` with no wait: a later move to its point gives no dwell.
_stop_waiting(motion::_Motion) =
    _Motion(motion.window, motion.x, motion.y, motion.modifiers, motion.time, false)
_stop_waiting(::Nothing) = nothing

_is_same_point(motion::_Motion, event::MouseMove, window) =
    motion.window === window && motion.x == event.x && motion.y == event.y
_is_same_point(::Nothing, event::MouseMove, window) = false

make_recognition_state(::DwellRecognition) = nothing

recognize(::DwellRecognition, motion, input, window) = RecognitionStep(motion)

function recognize(recognition::DwellRecognition, motion, event::MouseMove, window)
    window === nothing && return RecognitionStep(nothing)
    _is_same_point(motion, event, window) && return RecognitionStep(motion)
    now = get_event_time(event)
    moved = _Motion(window, event.x, event.y, event.modifiers, now,
                    event.buttons == MouseButtons())
    moved.is_waiting || return RecognitionStep(moved)
    RecognitionStep(moved; deadline = now + recognition.delay)
end

recognize(::DwellRecognition, motion, ::Union{MouseDown,MouseClick,MouseScroll}, window) =
    RecognitionStep(_stop_waiting(motion))

recognize(::DwellRecognition, motion, ::WindowLeave, window) = RecognitionStep(nothing)

function recognize(recognition::DwellRecognition, motion, timer::TimerExpire, window)
    now = get_event_time(timer)
    (motion === nothing || !motion.is_waiting || now < motion.time + recognition.delay) &&
        return RecognitionStep(motion; held = true)
    dwell = MouseDwell(motion.x, motion.y, motion.modifiers; time = now)
    RecognitionStep(_stop_waiting(motion); inputs = [WindowInput(motion.window, dwell)],
                    held = true)
end
