# Fragment of `GestureModule` — the recognition of a mouse dwell.

"""
    DwellRecognition(; delay = 0.5)

A `MouseDwell` when the pointer does not move for `delay` seconds after a
motion with no button held, at the place of that motion and at the time when the
wait ends. A motion with a button held, a down, a click, a scroll and the leave
of the window stop the wait, and one motion gives at most one dwell. A key does
not stop it: a dwell is no motion of the mouse.

The recognition reads the end of the wait as a `TimerExpire` at the deadline
that the motion answered, and it holds that timer. A timer of an older motion
finds a newer one in the state and gives nothing.
"""
struct DwellRecognition <: GestureRecognition
    delay::Float64
end

DwellRecognition(; delay::Real = 0.5) = DwellRecognition(Float64(delay))

# The last motion with no button held, while a dwell can still follow it.
struct _Motion
    window::Symbol
    x::Int
    y::Int
    modifiers::ModifierKeys
    time::Float64
end

make_recognition_state(::DwellRecognition) = nothing

recognize(::DwellRecognition, motion, input, window) = RecognitionStep(motion)

function recognize(recognition::DwellRecognition, motion, event::MouseMove, window)
    (window === nothing || event.buttons != MouseButtons()) && return RecognitionStep(nothing)
    RecognitionStep(_Motion(window, event.x, event.y, event.modifiers, event.time);
                    deadline = event.time + recognition.delay)
end

recognize(::DwellRecognition, motion, ::Union{MouseDown,MouseClick,MouseScroll,WindowLeave},
          window) = RecognitionStep(nothing)

function recognize(recognition::DwellRecognition, motion, timer::TimerExpire, window)
    (motion === nothing || timer.time < motion.time + recognition.delay) &&
        return RecognitionStep(motion; held = true)
    dwell = MouseDwell(motion.x, motion.y, motion.modifiers; time = timer.time)
    RecognitionStep(nothing; inputs = [WindowInput(motion.window, dwell)], held = true)
end
