"""
    PerformanceCounterModule

Lightweight instrumentation service. A single process-global `Dict{Symbol,Int}`
of counters that callers bump inline on the hot path; the store is seeded with
`:reads`, `:computes`, `:invalidations`, `:writes`. Externally measured
quantities (e.g. per-stage timings) can be folded into the same store under any
key via `record_performance!`, which creates a key on demand — so only the
seeded counters are listed here and the service stays ignorant of what else is
recorded.
"""
module PerformanceCounterModule

export get_performance_counters, reset_performance_counters!, record_performance!, @performance_time

# The shared counter store, seeded with four zeroed counters. Importers may
# mutate it inline for hot-path increments; other quantities are folded in via
# `record_performance!` (which creates keys on demand, so their names need not
# be listed here).
const _perf = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0)

"""
    get_performance_counters() -> Dict{Symbol,Int}

Return a copy of the performance counters dictionary. The seeded counters are
`:reads`, `:computes`, `:invalidations`, and `:writes`. Keys contributed via
`record_performance!` (e.g. per-stage timings) also appear here.
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
externally measured quantities (e.g. per-stage timings) alongside the seeded
counters.
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
