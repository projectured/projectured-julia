"""
    PerformanceCounterModule

Lightweight instrumentation for the reactive engine and the editor loop. A single
process-global `Dict{Symbol,Int}` of counters that the `Cell` engine bumps inline
on the hot path (`:reads`, `:computes`, `:invalidations`, `:writes`) and that the
editor folds per-stage timings into (`:read_time`, `:evaluate_time`,
`:print_time`). Extracted from `Reactive.jl` so the counter vocabulary is one
cohesive unit; `ReactiveModule` imports the shared `_perf` dict to keep its
increments a bare `Dict` write.
"""
module PerformanceCounterModule

export perf_counters, perf_reset!, perf_record!, @perf_time

# The shared counter store. `ReactiveModule` imports this and mutates it inline
# on the read/compute/invalidate/write paths; the editor and other callers fold
# in externally measured quantities via `perf_record!`.
const _perf = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0,
    :read_time => 0, :evaluate_time => 0, :print_time => 0)

"""
    perf_counters() -> Dict{Symbol,Int}

Return a copy of the performance counters dictionary. The counters track:
- `:reads` — number of cell reads
- `:computes` — number of cell re-computations
- `:invalidations` — number of cell invalidations
- `:writes` — number of cell writes
- `:read_time` — nanoseconds spent in the editor's read stage
- `:evaluate_time` — nanoseconds spent in the editor's evaluate stage
- `:print_time` — nanoseconds spent in the editor's print stage
"""
perf_counters() = copy(_perf)

"""
    perf_reset!()

Reset all performance counters to zero.
"""
function perf_reset!()
    for k in keys(_perf); _perf[k] = 0; end
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
