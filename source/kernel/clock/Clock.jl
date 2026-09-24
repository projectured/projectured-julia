# Fragment of `ClockModule` — the clock itself: the cell-struct, its readers and writer, and the ambient wall clock with its heartbeat.

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
    get_reactive_clock_time(clock) -> Float64

SUBSCRIBE: a tracked read of `clock.time`. The calling cell becomes a
dependent and re-runs on every tick.
"""
get_reactive_clock_time(clock::Clock) = clock.time

"""
    get_clock_time(clock) -> Float64

SAMPLE: an untracked read of `clock.time`. Registers no dependency; use to
capture a start instant that must not itself re-run every frame.
"""
get_clock_time(clock::Clock) = peek(getfield(clock, :time))

"""
    set_clock_time!(clock, t) -> nothing

Set `clock` to logical time `t` (in seconds, absolute). Writes `clock.time`,
invalidating every subscriber. The only clock mutator: a live frame advancing by
measured wall delta and a deterministic seek to an exact instant are the same
absolute write.
"""
set_clock_time!(clock::Clock, t::Real) = (clock.time = Float64(t); nothing)

# A clock shows as its constructor makes it, `Clock(time = 12.3)`, and not as the
# cell that holds its time. The read is a sample: a display subscribes to nothing.
Base.show(io::IO, clock::Clock) = print(io, "Clock(time = ", get_clock_time(clock), ")")

# The one process-wide clock reflecting OS time — the singleton `get_wall_clock`
# returns. Not exported; the accessor is the public entry point.
const _WALL_CLOCK = Clock()

"""
    get_wall_clock() -> Clock

The ambient wall-clock instance. Callers holding no clock of their own —
one-shot renders, contexts that can't reach an enclosing clock — subscribe
to it here.
"""
function get_wall_clock()
    # Started HERE, at first use, and not at module load. A process that never
    # asks for the ambient clock never runs the heartbeat — and a trimmed
    # binary that never asks never even compiles it, which is what keeps the
    # reactive cell write out of a run-only build. The start is idempotent
    # (the lock and the task check below), so every later call is a no-op.
    _start_wall_clock_heartbeat!()
    _WALL_CLOCK
end

# The wall-clock heartbeat: one task, started at first `get_wall_clock`, writing
# `Base.time() - t_start` into `_WALL_CLOCK.time` on an interval. Guarded by a
# lock so concurrent first callers, or a re-entry after a process fork or a
# manual reload, leave exactly one live task.
const _HEARTBEAT_INTERVAL = 0.01
const _HEARTBEAT_TASK = Ref{Union{Nothing,Task}}(nothing)
const _HEARTBEAT_LOCK = ReentrantLock()

function _start_wall_clock_heartbeat!()
    ccall(:jl_generating_output, Cint, ()) == 0 || return nothing
    lock(_HEARTBEAT_LOCK) do
        current = _HEARTBEAT_TASK[]
        (current !== nothing && !istaskdone(current)) && return
        t_start = Base.time()
        _HEARTBEAT_TASK[] = @async begin
            while true
                set_clock_time!(_WALL_CLOCK, Base.time() - t_start)
                sleep(_HEARTBEAT_INTERVAL)
            end
        end
    end
    nothing
end

# The `jl_generating_output` guard skips the heartbeat during precompile: an
# @async that never terminates would keep the precompile child alive past its
# work and hang the build. It lives on the START function now that the start is
# lazy, so a precompile-time `get_wall_clock` is safe too.
