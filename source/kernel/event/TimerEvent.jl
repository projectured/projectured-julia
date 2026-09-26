# Fragment of `EventModule` — the event of a timer.

"""
    TimerExpire(name::Symbol; time)
    TimerExpire(name, time)

A timer expired. A reader set it with `SetTimerOperation`, and `name` is the name
that the reader gave it. `time` is the time that the timer was set for, in seconds
on the clock of `time()`. The loop of the editor reports it from its clock when
that time comes; it belongs to no window.

A timer lets a reader find a pattern that ends when no event arrives, such as a
pointer that does not move for a while. A timer set again under the same name
replaces the one before, so a reader that sets it on each motion gets one event,
after the last motion. The reader checks its own state when the event comes, so an
event that a newer motion made stale matches nothing.
"""
struct TimerExpire <: Event
    name::Symbol
    time::Float64
end

TimerExpire(name::Symbol; time::Real) = TimerExpire(name, Float64(time))
