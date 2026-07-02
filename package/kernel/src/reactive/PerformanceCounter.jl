"""
    PerformanceCounterModule

Lightweight instrumentation for the reactive engine. A single process-global
`Dict{Symbol,Int}` of counters that the `Cell` engine bumps inline on the hot
path (`:reads`, `:computes`, `:invalidations`, `:writes`). Callers above the
engine can fold their own externally measured quantities (e.g. per-stage timings)
into the same store under keys of their choosing via `perf_record!`, which
creates a key on demand — so the engine seeds only its own counters and stays
ignorant of who else records here. Extracted from `Reactive.jl` so the counter
vocabulary is one cohesive unit; `ReactiveModule` imports the shared `_perf` dict
to keep its increments a bare `Dict` write.
"""
module PerformanceCounterModule

export perf_counters, perf_reset!, perf_record!, @perf_time

# The shared counter store, seeded with the engine's own counters. `ReactiveModule`
# imports this and mutates it inline on the read/compute/invalidate/write paths;
# other callers fold in externally measured quantities via `perf_record!` (which
# creates keys on demand, so their names need not be listed here).
const _perf = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0)

"""
    perf_counters() -> Dict{Symbol,Int}

Return a copy of the performance counters dictionary. The reactive engine's own
counters are:
- `:reads` — number of cell reads
- `:computes` — number of cell re-computations
- `:invalidations` — number of cell invalidations
- `:writes` — number of cell writes

Callers that use `perf_record!` (e.g. to fold in per-stage timings) contribute
further keys of their own, which also appear here.
"""
perf_counters() = copy(_perf)

"""
    perf_reset!()

Reset all performance counters to zero.
"""
function perf_reset!()
    for k in keys(_perf)
        _perf[k] = 0
    end
end

"""
    perf_record!(key::Symbol, value::Integer)

Add `value` to the counter at `key`, creating it if absent. Used to fold in
externally measured quantities (e.g. per-stage timings) alongside the
reactive engine's own counters.
"""
function perf_record!(key::Symbol, value::Integer)
    _perf[key] = get(_perf, key, 0) + Int(value)
end

"""
    @perf_time key expr

Evaluate `expr`, record the elapsed nanoseconds under `key` via
`perf_record!`, and return the value of `expr`.
"""
macro perf_time(key, expr)
    quote
        local t = time_ns()
        local result = $(esc(expr))
        perf_record!($(esc(key)), time_ns() - t)
        result
    end
end

end # module
