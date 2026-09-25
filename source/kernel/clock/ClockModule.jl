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

A clock must have one writer. An owner with a frame loop writes its clock once
per frame with `set_clock_time!`. `start_wall_clock!(clock)` starts a heartbeat that
writes real time into a clock where no frame loop exists, and
`stop_wall_clock!(clock)` ends it. The heartbeat runs on the thread of the task
that starts it, so the owner starts it on the task that reads the clock.

The module lives in one fragment, [`Clock.jl`](Clock.jl).
"""
module ClockModule

using ..CellModule
using ..CellStructModule

export Clock, get_reactive_clock_time, get_clock_time, set_clock_time!,
       start_wall_clock!, stop_wall_clock!

include("Clock.jl")

end # module
