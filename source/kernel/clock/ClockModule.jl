"""
    ClockModule

The animation clock. A `Clock` holds a time in seconds in a reactive cell, and a
computation that reads the time computes again after each write of it. Each
`Clock` is independent: a write invalidates only the cells that read that clock,
so one process can run many editors at once.

A clock has two reads:

- `get_reactive_clock_time(clock)` records the read, so the computation that
  reads the time computes again after the next write. Use it in a computation
  that animates.
- `get_clock_time(clock)` records nothing. Use it to take the start time of an
  animation, so the code that takes it does not run again on each write.

`get_wall_clock()` returns one clock that the whole process shares. Its time is
the number of seconds since the first call of `get_wall_clock()`. A heartbeat
task that the first call starts writes it every 10 milliseconds, and no other
code writes it. The time is the same for every editor, so PAR-PER-EDITOR-STATE
accepts the shared clock as an exception.

The module lives in one fragment, [`Clock.jl`](Clock.jl).
"""
module ClockModule

using ..CellModule
using ..CellStructModule

export Clock, get_reactive_clock_time, get_clock_time, set_clock_time!, get_wall_clock

include("Clock.jl")

end # module
