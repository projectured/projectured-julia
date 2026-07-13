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

A single wall clock — exposed by `get_wall_clock()` — tracks OS time. It is
the ambient default for one-shot renders and any context that holds no clock
of its own to subscribe against. One background task started at module load
writes `Base.time()` into it on an interval; every other consumer only
reads. A shared read of one real external truth is a principled AR-45
carve-out — nothing else ever *writes* conflicting elapsed values into it.
"""
module ClockModule

using ..CellModule

export Clock, get_reactive_time, get_time, tick!, seek!, get_wall_clock

"""
    Clock(; time = 0.0) -> Clock

A `@cell_struct` with one reactive field, `time::Float64`. Reads and writes go
through the field's `Cell`: `clock.time` reads with dependency tracking,
`clock.time = t` writes and invalidates every subscriber. Use the named
helpers below rather than the raw field when intent (SUBSCRIBE vs SAMPLE, TICK
vs SEEK) matters.

A clock is **not** a `Document`: it is editor infrastructure, not addressable
content — nothing navigates into it, selects inside it, or projects it. It
wants only the transparent-cell codegen, which is exactly what `@cell_struct`
provides.
"""
@cell_struct struct Clock
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

# The one process-wide clock reflecting OS time — the singleton `get_wall_clock`
# returns. Not exported; the accessor is the public entry point.
const _WALL_CLOCK = Clock()

"""
    get_wall_clock() -> Clock

The ambient wall-clock instance. Callers holding no clock of their own —
one-shot renders, contexts that can't reach an enclosing clock — subscribe
to it here.
"""
get_wall_clock() = _WALL_CLOCK

# The wall-clock heartbeat: one task, started once at module load, writing
# `Base.time() - t_start` into `_WALL_CLOCK.time` on an interval. Guarded by a
# lock so re-entering `__init__` after a process fork or manual reload leaves
# exactly one live task.
const _HEARTBEAT_INTERVAL = 0.01
const _HEARTBEAT_TASK = Ref{Union{Nothing,Task}}(nothing)
const _HEARTBEAT_LOCK = ReentrantLock()

function _start_wall_clock_heartbeat!()
    lock(_HEARTBEAT_LOCK) do
        current = _HEARTBEAT_TASK[]
        (current !== nothing && !istaskdone(current)) && return
        t_start = Base.time()
        _HEARTBEAT_TASK[] = @async begin
            while true
                tick!(_WALL_CLOCK, Base.time() - t_start)
                sleep(_HEARTBEAT_INTERVAL)
            end
        end
    end
    nothing
end

# Runs at first `using ClockModule` in every process (including precompile-child
# processes that load us as a dependency). The `jl_generating_output` guard
# skips the heartbeat during precompile: an @async that never terminates
# would keep the precompile child alive past its work and hang the build.
function __init__()
    ccall(:jl_generating_output, Cint, ()) == 0 || return
    _start_wall_clock_heartbeat!()
end

end # module
