# Fragment of `BackendModule` — `HeldFrameState`, what one held frame of a backend
# shows while a code unit runs.

"""
    HeldFrameState(seconds, current, is_stop_pending, is_quit_asked)

What one held frame shows while a code unit runs: the time since the unit
started, in seconds; the index of the description of `prepare_held_frames!` that
names the work that runs now; whether a stop that the person asked for has had no
effect for 3 seconds, so the bar says that the code does not stop; and whether
the frame asks to quit without a save.
"""
struct HeldFrameState
    seconds::Float64
    current::Int
    is_stop_pending::Bool
    is_quit_asked::Bool
end
