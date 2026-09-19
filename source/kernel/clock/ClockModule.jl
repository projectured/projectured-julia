"""
    ClockModule

The animation clock, modelled as a `Clock` (a `@cell_struct`) with a reactive
`time` field. Every `Clock` instance is independent: writing one instance's `time`
invalidates only its own subscribers, so a process holding many concurrent
clocks never cross-invalidates them — the property that lets many editors run
side by side without their animation graphs colliding.

Two ways to read a clock, named for intent:

  • `get_reactive_clock_time(clock)` — SUBSCRIBE. A tracked read; the calling
    cell becomes a dependent and re-runs on every tick. Use inside an animated
    thunk. The `reactive_` prefix is the loud one: calling it makes you
    reactive.

  • `get_clock_time(clock)` — SAMPLE. An untracked read that registers no
    dependency. Use to *arm* an animation (capture a start instant) without
    the arming code itself re-running every frame.

A single wall clock — exposed by `get_wall_clock()` — tracks OS time. It is
the ambient default for one-shot renders and any context that holds no clock
of its own to subscribe against. One background task started at module load
writes `Base.time()` into it on an interval; every other consumer only
reads. A shared read of one real external truth is a principled
PAR-PER-EDITOR-STATE carve-out — nothing else ever *writes* conflicting
elapsed values into it.
"""
module ClockModule

using ..CellModule
using ..CellStructModule

export Clock, get_reactive_clock_time, get_clock_time, set_clock_time!, get_wall_clock

include("Clock.jl")

end # module
