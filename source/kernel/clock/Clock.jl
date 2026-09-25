# Fragment of `ClockModule` — the `Clock`, its two reads and its write, and the wall
# clock with the task that writes it.

"""
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

`Clock` is a `@cell_struct` with one field, `time`. `clock.time` is the read that
records a dependency, and `clock.time = t` is the write, but the field takes a
value of any type. Write with `set_clock_time!`, which converts the time to
`Float64`.

See also `get_clock_time`, the read that records nothing, and `get_wall_clock`.
"""
@cell_struct struct Clock
    time::Float64 = 0.0
end

"""
    get_reactive_clock_time(clock) -> Float64

The time of `clock`. The read makes the computation that reads it depend on the
clock, so the computation computes again after the next write.

Use it in a computation that animates, so that each write of the time moves the
animation.

# Example

    x = Cell(@computation 100 * get_reactive_clock_time(clock))

A time that is not a `Float64` throws a `TypeError`.

See also `get_clock_time`, the read that records nothing.
"""
get_reactive_clock_time(clock::Clock) = clock.time::Float64

"""
    get_clock_time(clock) -> Float64

The time of `clock`. The read records no dependency, so a computation that reads
it does not compute again after a write.

Use it to take the start time of an animation, so that the code that starts the
animation does not run again on each write of the time.

# Example

    start = get_clock_time(clock)
    elapsed = Cell(@computation get_reactive_clock_time(clock) - start)

A time that is not a `Float64` throws a `TypeError`.

See also `get_reactive_clock_time`.
"""
get_clock_time(clock::Clock) = peek(getfield(clock, :time))::Float64

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

# The wall clock that `get_wall_clock` returns. The heartbeat task is its only writer.
const _WALL_CLOCK = Clock()

"""
    get_wall_clock() -> Clock

The clock that the whole process shares. Its time is the number of seconds since
the first call of `get_wall_clock`.

Use it when a computation needs the time and has no clock of its own.

# Example

    wall = get_wall_clock()
    blink = Cell(@computation isodd(floor(Int, 2 * get_reactive_clock_time(wall))))

A heartbeat task writes the time every 10 milliseconds. The first call starts the
task, so a process that never calls `get_wall_clock` runs no task, and a trimmed
binary that never calls it does not compile the task. Do not write the wall clock
with `set_clock_time!`, because the heartbeat is its only writer.
"""
function get_wall_clock()
    _start_wall_clock_heartbeat!()
    _WALL_CLOCK
end

# The heartbeat writes `Base.time() - start` into the wall clock every
# `_HEARTBEAT_INTERVAL` seconds. The lock makes the start idempotent: two first
# callers at the same time, or a call after the task ended, leave exactly one live
# task.
const _HEARTBEAT_INTERVAL = 0.01
const _HEARTBEAT_TASK = Ref{Union{Nothing,Task}}(nothing)
const _HEARTBEAT_LOCK = ReentrantLock()

function _start_wall_clock_heartbeat!()
    # No heartbeat while a package precompiles: a task that never ends keeps the
    # precompile process alive, and the build does not finish.
    ccall(:jl_generating_output, Cint, ()) == 0 || return nothing
    lock(_HEARTBEAT_LOCK) do
        current = _HEARTBEAT_TASK[]
        (current !== nothing && !istaskdone(current)) && return
        start = Base.time()
        _HEARTBEAT_TASK[] = @async begin
            while true
                set_clock_time!(_WALL_CLOCK, Base.time() - start)
                sleep(_HEARTBEAT_INTERVAL)
            end
        end
    end
    nothing
end
