"""
    PerformanceCounterModule

Conditionally-compiled instrumentation for the reactive engine's hot path.

Counting is off unless `PERFORMANCE_COUNTERS_ENABLED` is set (via the
`PROJECTURED_PERFORMANCE_COUNTERS` environment variable, read once at precompile
time). While it is off, `@count_performance`, `record_performance!`, and
`@performance_time` expand to `nothing` (or a bare evaluation of their
expression), so a normal build carries no instrumentation at all.

There is no process-global counter store. The active store is a task-local
dynamic binding (`ScopedValue`): `with_performance_counters(f)` binds a fresh
`Dict{Symbol,Int}` for the dynamic extent of `f`, and the cell operations that
run inside that extent count into it. Outside any such scope the binding is
`nothing`, so an unscoped cell operation counts nothing and shares no state —
which is what lets many editors run in one process without their counters
colliding.
"""
module PerformanceCounterModule

using Base.ScopedValues: ScopedValue, with

export with_performance_counters, get_performance_counters, record_performance!,
    @performance_time, @count_performance, PERFORMANCE_COUNTERS_ENABLED

# Compile-time switch, seeded from the environment at precompile time. Set
# PROJECTURED_PERFORMANCE_COUNTERS=false and recompile to compile the counters
# out; the counter macros below then expand to `nothing`, so the reactive hot
# path carries no instrumentation at all.
const PERFORMANCE_COUNTERS_ENABLED =
    get(ENV, "PROJECTURED_PERFORMANCE_COUNTERS", "true") == "true"

# The active counter store: a task-local dynamic binding, `nothing` outside any
# `with_performance_counters` scope.
const _counters = ScopedValue{Union{Nothing,Dict{Symbol,Int}}}(nothing)

# Add `n` to `key` in the currently-bound store; a no-op when none is bound.
@inline function _bump!(key::Symbol, n::Integer)
    store = _counters[]
    store === nothing || (store[key] = get(store, key, 0) + Int(n))
    nothing
end

_fresh_counters() = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0)

"""
    with_performance_counters(f, store=<fresh>) -> f()'s value

Bind `store` as the active counter store for the dynamic extent of `f`, run `f`,
and return its value. Each call gets its own store (a fresh zeroed set of the
reactive counters by default), so concurrent editors never share counters. When
counting is compiled out, `f` simply runs with no binding.
"""
function with_performance_counters(f, store::Union{Dict{Symbol,Int},Nothing}=nothing)
    # `PERFORMANCE_COUNTERS_ENABLED` is a `const`, so this branch is constant-folded
    # and the disabled build compiles down to `f()`.
    PERFORMANCE_COUNTERS_ENABLED || return f()
    with(f, _counters => (store === nothing ? _fresh_counters() : store))
end

"""
    get_performance_counters() -> Dict{Symbol,Int}

Return a copy of the currently-bound counter store — the seeded counters
`:reads`, `:computes`, `:invalidations`, `:writes` plus any keys folded in via
`record_performance!` — or an empty dict when called outside a
`with_performance_counters` scope.
"""
function get_performance_counters()
    store = _counters[]
    store === nothing ? Dict{Symbol,Int}() : copy(store)
end

"""
    record_performance!(key::Symbol, value::Integer)

Add `value` to the counter at `key` in the active store, creating it on demand.
Used to fold in externally measured quantities (e.g. per-stage timings) alongside
the seeded counters. A no-op when counting is compiled out or no scope is active.
"""
function record_performance!(key::Symbol, value::Integer)
    PERFORMANCE_COUNTERS_ENABLED && _bump!(key, value)
    nothing
end

"""
    @count_performance key

Bump the counter `key` by one. Used by the reactive engine on its hot path.
Expands to `nothing` when counting is compiled out, so instrumentation adds no
cost to a normal build.
"""
macro count_performance(key)
    PERFORMANCE_COUNTERS_ENABLED ? :(_bump!($(esc(key)), 1)) : :(nothing)
end

"""
    @performance_time key expr

Evaluate `expr`, record the elapsed nanoseconds under `key`, and return the value
of `expr`. When counting is compiled out, expands to just `expr`.
"""
macro performance_time(key, expr)
    PERFORMANCE_COUNTERS_ENABLED || return esc(expr)
    quote
        local t = time_ns()
        local result = $(esc(expr))
        _bump!($(esc(key)), Int(time_ns() - t))
        result
    end
end

end # module
