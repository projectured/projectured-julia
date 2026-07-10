"""
    ClockModule

The animation clock, modelled as a `Clock` document with a reactive `time`
field. Every `Clock` instance is independent: writing one instance's `time`
invalidates only its own subscribers, so a process holding many concurrent
clocks never cross-invalidates them — the property that lets many editors run
side by side without their animation graphs colliding.

Two ways to read a clock, named for intent:

  • `get_reactive_time(clock)` — SUBSCRIBE. A tracked read; the calling cell
    becomes a dependent and re-runs on every tick. Use inside an animated
    thunk. The `reactive_` prefix is the loud one: calling it makes you
    reactive.

  • `get_time(clock)` — SAMPLE. An untracked read that registers no
    dependency. Use to *arm* an animation (capture a start instant) without
    the arming code itself re-running every frame.

A single wall clock — `WALL_CLOCK`, exposed by `get_wall_clock()` — tracks OS
time. It is the ambient default for one-shot renders and any context that
holds no clock of its own to subscribe against. One background task
(`start_wall_clock_heartbeat!`) writes `Base.time()` into it on an interval;
every other consumer only reads. A shared read of one real external truth is
a principled AR-45 carve-out — nothing else ever *writes* conflicting elapsed
values into it.
"""
module ClockModule

import ..DocumentModule: @document, Document

export Clock, get_reactive_time, get_time, tick!, seek!,
       WALL_CLOCK, get_wall_clock, start_wall_clock_heartbeat!

"""
    Clock(; time = 0.0) -> Clock

A `@document` with one reactive field, `time::Float64`. Reads and writes go
through the field's `Cell`: `clock.time` reads with dependency tracking,
`clock.time = t` writes and invalidates every subscriber. Use the named
helpers below rather than the raw field when intent (SUBSCRIBE vs SAMPLE, TICK
vs SEEK) matters.
"""
@document struct Clock
    time::Float64 = 0.0
end

"""
    get_reactive_time(clock) -> Float64

SUBSCRIBE: a tracked read of `clock.time`. The calling cell becomes a
dependent and re-runs on every tick.
"""
get_reactive_time(clock::Clock) = clock.time

"""
    get_time(clock) -> Float64

SAMPLE: an untracked read of `clock.time`. Registers no dependency; use to
capture a start instant that must not itself re-run every frame.
"""
get_time(clock::Clock) = peek(getfield(clock, :time))

"""
    tick!(clock, t) -> nothing

Advance `clock` to logical time `t` (in seconds). Writes `clock.time`,
invalidating every subscriber.
"""
tick!(clock::Clock, t::Real) = (clock.time = Float64(t); nothing)

"""
    seek!(clock, t) -> nothing

Set `clock` to logical time `t` deterministically. Same effect as `tick!`; the
name is used at recording / test call sites where the semantics are
"jump to this exact time", not "advance by measured wall delta".
"""
seek!(clock::Clock, t::Real) = tick!(clock, t)

"""
    WALL_CLOCK :: Clock

The one process-wide clock reflecting OS time. Advanced by
[`start_wall_clock_heartbeat!`](@ref); read via
[`get_wall_clock`](@ref). Every other clock in the process is an
independent instance carrying its own subscribers.
"""
const WALL_CLOCK = Clock()

"""
    get_wall_clock() -> Clock

The ambient wall-clock instance. Callers holding no clock of their own —
one-shot renders, contexts that can't reach an enclosing clock — subscribe
to it here.
"""
get_wall_clock() = WALL_CLOCK

# The wall-clock heartbeat: one task, started lazily by
# `start_wall_clock_heartbeat!`, writing `Base.time() - t_start` into
# `WALL_CLOCK.time` on an interval. Guarded by a lock so concurrent starts
# leave exactly one live task.
const _HEARTBEAT_TASK = Ref{Union{Nothing,Task}}(nothing)
const _HEARTBEAT_LOCK = ReentrantLock()

"""
    start_wall_clock_heartbeat!(interval = 0.01) -> nothing

Ensure the wall-clock heartbeat is running. Idempotent: a second call while
a heartbeat task is alive is a no-op. `interval` is the wake period in seconds
between ticks. The heartbeat is the one writer of `WALL_CLOCK` — every other
consumer only reads.
"""
function start_wall_clock_heartbeat!(interval::Real = 0.01)
    lock(_HEARTBEAT_LOCK) do
        current = _HEARTBEAT_TASK[]
        (current !== nothing && !istaskdone(current)) && return
        t_start = Base.time()
        _HEARTBEAT_TASK[] = @async begin
            while true
                tick!(WALL_CLOCK, Base.time() - t_start)
                sleep(interval)
            end
        end
    end
    nothing
end

end # module
