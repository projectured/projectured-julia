# Fragment of `ClockModule` — the `Clock`, its two reads and its write, and the
# heartbeat that writes real time into a clock.

"""
    Clock(time = 0.0) -> Clock
    Clock(; time = 0.0) -> Clock

A time in seconds, held in a reactive cell.

Use it to drive an animation: a computation that reads the time with
`get_reactive_clock_time` computes again after each write, and the code that
moves the animation writes the time with `set_clock_time!`.

# Example

    clock = Clock()
    angle = Cell(@computation 2π * get_reactive_clock_time(clock))
    set_clock_time!(clock, 0.25)
    angle[]                                         # π / 2

`Clock` is a `@cell_struct`. `clock.time` is the read that records a dependency,
and `clock.time = t` is the write, but the field takes a value of any type. Write
with `set_clock_time!`, which converts the time to `Float64`. The two reads
convert any real number. The field `heartbeat` holds the task of
`start_wall_clock!`, or `nothing`; leave it to `start_wall_clock!` and
`stop_wall_clock!`.

See also `get_clock_time`, the read that records nothing, and `start_wall_clock!`.
"""
@cell_struct struct Clock
    time::Float64 = 0.0
    heartbeat::MutableCell{Union{Nothing,Task}} = nothing
end

Clock(time::Real) = Clock(Float64(time), nothing)

# The time as a `Float64`. The field takes any value, so a read converts a real
# number, and the common `Float64` needs no call.
_get_clock_seconds(time) = time isa Float64 ? time : convert(Float64, time)::Float64

"""
    get_reactive_clock_time(clock) -> Float64

The time of `clock`. The read makes the computation that reads it depend on the
clock, so the computation computes again after the next write.

Use it in a computation that animates, so that each write of the time moves the
animation.

# Example

    x = Cell(@computation 100 * get_reactive_clock_time(clock))

A time that is not a real number throws a `MethodError`.

See also `get_clock_time`, the read that records nothing.
"""
get_reactive_clock_time(clock::Clock) = _get_clock_seconds(clock.time)

"""
    get_clock_time(clock) -> Float64

The time of `clock`. The read records no dependency, so a computation that reads
it does not compute again after a write.

Use it to take the start time of an animation, so that the code that starts the
animation does not run again on each write of the time.

# Example

    start = get_clock_time(clock)
    elapsed = Cell(@computation get_reactive_clock_time(clock) - start)

A time that is not a real number throws a `MethodError`.

See also `get_reactive_clock_time`.
"""
get_clock_time(clock::Clock) = _get_clock_seconds(peek(getfield(clock, :time)))

"""
    set_clock_time!(clock, t) -> nothing

Write the time `t`, in seconds, into `clock` as a `Float64`. The write invalidates
every computation that reads the clock with `get_reactive_clock_time`.

Use it to move a clock forward on each frame, or to move it to an exact time. Both
are the same write of an absolute time.

# Example

    set_clock_time!(clock, time() - start)

See also `get_clock_time`.
"""
set_clock_time!(clock::Clock, t::Real) = (clock.time = Float64(t); nothing)

# A clock shows as its constructor makes it, `Clock(time = 12.3)`, and not as the
# cell that holds its time. The read records nothing, so a display depends on no
# clock, and it does not narrow, so a clock that holds another type still shows.
Base.show(io::IO, clock::Clock) =
    print(io, "Clock(time = ", peek(getfield(clock, :time)), ")")

"""
    start_wall_clock!(clock) -> clock

Start a heartbeat that moves `clock` forward with real time, from the time that
it holds, every 10 milliseconds, and return `clock`. The time never goes back, so
a stop and a later start act as a pause and a resume. A clock whose heartbeat runs
keeps it, so a second call starts nothing.

Use it to animate with real time where no frame loop writes the clock. An owner
with a frame loop writes its clock once per frame with `set_clock_time!` instead.

# Example

    clock = start_wall_clock!(Clock())
    blink = Cell(@computation isodd(floor(Int, 2 * get_reactive_clock_time(clock))))
    stop_wall_clock!(clock)

Call it on the task that reads the clock. The heartbeat is a task on the thread of
the caller, and Julia keeps the caller on that thread too, so the two never run at
the same moment. A read of the clock on another thread races with the heartbeat.
The heartbeat writes at the points where the tasks of its thread yield, so a frame
that yields can see two times. Do not start a heartbeat on a clock that other
code writes.

The heartbeat holds the clock through a `WeakRef`, so it ends when the collector
frees a clock that nobody stopped. It does not start while a package precompiles,
because a task that never ends keeps the precompile process alive.

See also `stop_wall_clock!`.
"""
function start_wall_clock!(clock::Clock)
    ccall(:jl_generating_output, Cint, ()) == 0 || return clock
    current = clock.heartbeat
    (current !== nothing && !istaskdone(current)) && return clock
    reference = WeakRef(clock)
    start = Base.time() - get_clock_time(clock)
    clock.heartbeat = @async _run_wall_clock_heartbeat(reference, start)
    clock
end

"""
    stop_wall_clock!(clock) -> nothing

End the heartbeat of `clock`. The heartbeat task ends at its next wake, within 10
milliseconds, and the clock keeps its last time. A clock without a heartbeat stays
as it is. Call it on the task that started the heartbeat, which is the condition
of `start_wall_clock!` too.

Use it when the owner of a clock no longer needs real time, so that its task ends.

# Example

    stop_wall_clock!(clock)

See also `start_wall_clock!`.
"""
function stop_wall_clock!(clock::Clock)
    clock.heartbeat = nothing
    nothing
end

const _HEARTBEAT_INTERVAL = 0.01

# The loop of a heartbeat. It writes `Base.time() - start`, where `start` is the
# real time at which the clock would have been at zero. It holds its clock only
# between a read of `reference` and the write, so the collector can free a clock
# that nobody stopped. It ends when the clock is gone, or when the clock holds
# another heartbeat or none.
function _run_wall_clock_heartbeat(reference::WeakRef, start::Float64)
    while true
        clock = reference.value
        clock === nothing && return
        clock.heartbeat === current_task() || return
        set_clock_time!(clock, Base.time() - start)
        clock = nothing
        sleep(_HEARTBEAT_INTERVAL)
    end
end
