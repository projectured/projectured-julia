# Fragment of `PerformanceModule` — the counters of one scope: counts, and times.

# The compile-time switch. Set PROJECTURED_PERFORMANCE_COUNTERS=true and
# recompile to compile the counters in, for example to profile an edit or to run
# the tests that count. The variable is read once, at precompile time. While the
# switch is off, `@count_performance` expands to `nothing` and
# `@measure_performance_time` to its expression, so a normal build carries no
# instrumentation.
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

Use it to profile a piece of work: count the cell reads, the computations, the
invalidations and the writes that one edit or one frame causes, and time its
stages. The counters exist only when the switch compiled them in.

# Example

    counters = with_performance_counters() do
        run_frame!(editor)
        get_performance_counters()
    end

See also [`get_performance_counters`](@ref), which reads the store of the scope.
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

Use it inside a scope to read how much work the scope did so far: how many cells
it read, computed, invalidated and wrote, and how long each timed stage took.

# Example

    reads = with_performance_counters() do
        run_frame!(editor)
        get_performance_counters().counts[:reads]
    end

See also [`with_performance_counters`](@ref), which binds the store.
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

Use it to count an event of your own in a profile, for example each call of a
function that runs more often than you expect.

# Example

    @count_performance :layout_passes

See also [`@measure_performance_time`](@ref), which adds a time and not a count.
"""
macro count_performance(key)
    PERFORMANCE_COUNTERS_ENABLED ? :(_bump_count!($(esc(key)), 1)) : :(nothing)
end

"""
    @measure_performance_time key expr

Evaluate `expr`, add the elapsed nanoseconds to the time `key` of the current
scope, and return the value of `expr`. When counting is compiled out, expands to
just `expr`.

Use it to time one stage of work in a profile, for example the print or the
paint of a frame.

# Example

    @measure_performance_time :print_time run_print_stage!(editor)

See also [`@count_performance`](@ref), which adds a count and not a time.
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
