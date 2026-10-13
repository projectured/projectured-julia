# Fragment of `ClockModule` — the `Clock`, its two reads and its write.

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
convert any real number.

A clock has one writer: the editor that owns it writes the time at the start of
each frame. To animate a document in an editor, give the document and the editor
the same clock, with the keyword `clock` of `run_editor!`, `build_editor` or
`make_editor`.

See also `get_clock_time`, the read that records nothing.
"""
@cell_struct struct Clock
    time::Float64 = 0.0
end

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
