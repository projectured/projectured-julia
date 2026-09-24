# Fragment of `PerformanceModule` — the conditionally-compiled instrumentation
# counters: counts, seeded with `:reads`, `:computes`, `:invalidations` and
# `:writes`, and times in nanoseconds, kept apart.
#
# Counting is off unless `PERFORMANCE_COUNTERS_ENABLED` is set (via the
# `PROJECTURED_PERFORMANCE_COUNTERS` environment variable, read once at precompile
# time). While it is off, `@count_performance` expands to `nothing` and
# `@measure_performance_time` to a bare evaluation of its expression, so a normal
# build carries no instrumentation at all.
#
# There is no process-global counter store. The active store is a task-local
# dynamic binding (`ScopedValue`): `with_performance_counters(f)` binds a fresh
# store for the dynamic extent of `f`, and every `@count_performance` and
# `@measure_performance_time` inside that extent records into it. Outside any
# such scope the binding is `nothing`, so a bump records nothing and shares no
# state — which is what lets many editors run in one process without their
# counters colliding.

# The compile-time switch. Set PROJECTURED_PERFORMANCE_COUNTERS=true and
# recompile to compile the counters in, for example to profile an edit or to run
# the tests that count.
const PERFORMANCE_COUNTERS_ENABLED =
    get(ENV, "PROJECTURED_PERFORMANCE_COUNTERS", "false") == "true"

# The counters of one scope: the counts, and the times in nanoseconds. A time
# never goes into the counts, so a reader knows the unit of every key.
struct _PerformanceCounterStore
    counts::Dict{Symbol,Int}
    times::Dict{Symbol,Int}
end

_make_performance_counter_store() = _PerformanceCounterStore(
    Dict{Symbol,Int}(:reads => 0, :computes => 0, :invalidations => 0, :writes => 0),
    Dict{Symbol,Int}())

# The active counter store: a task-local dynamic binding, `nothing` outside any
# `with_performance_counters` scope.
const _counters = ScopedValue{Union{Nothing,_PerformanceCounterStore}}(nothing)

# Add to a count or to a time of the bound store; a no-op when none is bound.
@inline function _bump_count!(key::Symbol, n::Integer)
    store = _counters[]
    store === nothing || (store.counts[key] = get(store.counts, key, 0) + Int(n))
    nothing
end

@inline function _bump_time!(key::Symbol, nanoseconds::Integer)
    store = _counters[]
    store === nothing ||
        (store.times[key] = get(store.times, key, 0) + Int(nanoseconds))
    nothing
end

"""
    with_performance_counters(f) -> f()'s value

Bind a fresh counter store for the dynamic extent of `f`, run `f`, and return
its value. Each call gets its own store, with the seeded counts at zero and no
time, so concurrent editors never share counters. When counting is compiled
out, `f` simply runs with no binding.
"""
function with_performance_counters(f)
    # `PERFORMANCE_COUNTERS_ENABLED` is a `const`, so this branch is constant-folded
    # and the disabled build compiles down to `f()`.
    PERFORMANCE_COUNTERS_ENABLED || return f()
    with(f, _counters => _make_performance_counter_store())
end

"""
    get_performance_counters() -> (; counts, times)

Copies of the counters of the current scope. `counts` holds the seeded counts
`:reads`, `:computes`, `:invalidations` and `:writes`, and every key that
`@count_performance` added. `times` holds every key that
`@measure_performance_time` recorded, in nanoseconds. Outside a
`with_performance_counters` scope, both are empty.
"""
function get_performance_counters()
    store = _counters[]
    store === nothing && return (counts = Dict{Symbol,Int}(), times = Dict{Symbol,Int}())
    (counts = copy(store.counts), times = copy(store.times))
end

"""
    @count_performance key

Add one to the count `key` of the current scope. Expands to `nothing` when
counting is compiled out, so a count costs nothing in a normal build.
"""
macro count_performance(key)
    PERFORMANCE_COUNTERS_ENABLED ? :(_bump_count!($(esc(key)), 1)) : :(nothing)
end

"""
    @measure_performance_time key expr

Evaluate `expr`, add the elapsed nanoseconds to the time `key` of the current
scope, and return the value of `expr`. When counting is compiled out, expands to
just `expr`.
"""
macro measure_performance_time(key, expr)
    PERFORMANCE_COUNTERS_ENABLED || return esc(expr)
    quote
        local t = time_ns()
        local result = $(esc(expr))
        _bump_time!($(esc(key)), Int(time_ns() - t))
        result
    end
end
