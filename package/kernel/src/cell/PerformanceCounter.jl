"""
    PerformanceCounterModule

Lightweight instrumentation for the reactive engine. A single process-global
`Dict{Symbol,Int}` of counters that the `Cell` engine bumps inline on the hot
path (`:reads`, `:computes`, `:invalidations`, `:writes`). Callers above the
engine can fold their own externally measured quantities (e.g. per-stage timings)
into the same store under keys of their choosing via `record_performance!`, which
creates a key on demand — so the engine seeds only its own counters and stays
ignorant of who else records here. Extracted from `Reactive.jl` so the counter
vocabulary is one cohesive unit; `ReactiveModule` imports the shared `_perf` dict
to keep its increments a bare `Dict` write.
"""
module PerformanceCounterModule

export get_performance_counters, reset_performance_counters!, record_performance!, @performance_time

# The shared counter store, seeded with the engine's own counters. `ReactiveModule`
# imports this and mutates it inline on the read/compute/invalidate/write paths;
# other callers fold in externally measured quantities via `record_performance!` (which
# creates keys on demand, so their names need not be listed here).
const _perf = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0)

"""
    get_performance_counters() -> Dict{Symbol,Int}

Return a copy of the performance counters dictionary. The reactive engine's own
counters are:
- `:reads` — number of cell reads
- `:computes` — number of cell re-computations
- `:invalidations` — number of cell invalidations
- `:writes` — number of cell writes

Callers that use `record_performance!` (e.g. to fold in per-stage timings) contribute
further keys of their own, which also appear here.
"""
get_performance_counters() = copy(_perf)

"""
    reset_performance_counters!()

Reset all performance counters to zero.
"""
function reset_performance_counters!()
    for k in keys(_perf)
        _perf[k] = 0
    end
end

"""
    record_performance!(key::Symbol, value::Integer)

Add `value` to the counter at `key`, creating it if absent. Used to fold in
externally measured quantities (e.g. per-stage timings) alongside the
reactive engine's own counters.
"""
function record_performance!(key::Symbol, value::Integer)
    _perf[key] = get(_perf, key, 0) + Int(value)
end

"""
    @performance_time key expr

Evaluate `expr`, record the elapsed nanoseconds under `key` via
`record_performance!`, and return the value of `expr`.
"""
macro performance_time(key, expr)
    quote
        local t = time_ns()
        local result = $(esc(expr))
        record_performance!($(esc(key)), time_ns() - t)
        result
    end
end

end # module
