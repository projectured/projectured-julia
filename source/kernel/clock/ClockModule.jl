"""
    ClockModule

The animation clock. A `Clock` holds a time in seconds in a reactive cell, and a
computation that reads the time computes again after each write of a new time.
Each `Clock` is independent: a write invalidates only the cells that read that
clock, so one process can hold many clocks, each with readers of its own.

A clock has two reads:

- `get_reactive_clock_time(clock)` records the read, so the computation that
  reads the time computes again after the next write. Use it in a computation
  that animates.
- `get_clock_time(clock)` records nothing. Use it to take the start time of an
  animation, so the code that takes it does not run again on each write.

A clock has one writer, the task that owns the cells that read it. The writer
writes the time with `set_clock_time!` before it reads those cells, and
`has_clock_readers` tells it whether a cell reads the clock.

The module lives in one fragment, [`Clock.jl`](Clock.jl).
"""
module ClockModule

using ..CellModule
using ..CellStructModule

export Clock, get_reactive_clock_time, get_clock_time, set_clock_time!, has_clock_readers

include("Clock.jl")

end # module
