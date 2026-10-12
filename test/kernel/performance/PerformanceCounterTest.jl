"""
`PerformanceModule` — conditionally-compiled reactive instrumentation.
The active counter store is a task-local binding established by
`run_with_performance_counters`. `@count_performance` adds to its counts, and
`@measure_performance_time` adds to its times, which it keeps apart.
"""

using Test
using ProjecturedKernel.PerformanceModule
using ProjecturedKernel.CellModule: Cell, Computation, @computation

function test_performance_counter()
@testset "PerformanceCounter" begin
    # Outside any scope the store reads empty and nothing shares state.
    outside = get_performance_counters()
    @test isempty(outside.counts) && isempty(outside.times)

    # The store and the bumps, whatever the switch says: bind a store as a scope
    # does, and add to it.
    @testset "a bound store keeps what the bumps add" begin
        store = PerformanceModule._make_performance_counter_store()
        counters = Base.ScopedValues.with(PerformanceModule._counters => store) do
            PerformanceModule._bump_count!(:reads, 2)
            PerformanceModule._bump_count!(:layout_passes, 1)
            PerformanceModule._bump_time!(:print_time, 500)
            PerformanceModule._bump_time!(:print_time, 250)
            get_performance_counters()
        end
        @test counters.counts[:reads] == 2
        @test counters.counts[:layout_passes] == 1
        @test counters.counts[:computes] == 0
        @test counters.times == Dict(:print_time => 750)
        @test !haskey(counters.counts, :print_time)
        after = get_performance_counters()
        @test isempty(after.counts) && isempty(after.times)
    end

    @testset "the macros count and time only when the switch compiled them in" begin
        store = PerformanceModule._make_performance_counter_store()
        value = Base.ScopedValues.with(PerformanceModule._counters => store) do
            @count_performance :layout_passes
            @count_performance :layout_passes
            @measure_performance_time :probe_time (1 + 2)
        end
        @test value == 3
        @test get(store.counts, :layout_passes, 0) == (PERFORMANCE_COUNTERS_ENABLED ? 2 : 0)
        @test haskey(store.times, :probe_time) == PERFORMANCE_COUNTERS_ENABLED
    end

    @testset "a scope answers the value of its body" begin
        @test run_with_performance_counters(() -> 42) == 42
    end

    @testset "the counters of a scope are copies, with four seeded counts" begin
        store = PerformanceModule._make_performance_counter_store()
        Base.ScopedValues.with(PerformanceModule._counters => store) do
            counters = get_performance_counters()
            @test Set(keys(counters.counts)) == Set([:reads, :computes, :invalidations, :writes])
            counters.counts[:reads] = 99
            counters.times[:probe_time] = 99
            again = get_performance_counters()
            @test again.counts[:reads] == 0
            @test isempty(again.times)
        end
    end

    @testset "the switch is the preference that the kernel was compiled with" begin
        preferences = Base.get_preferences(Base.PkgId(Base.moduleroot(PerformanceModule)).uuid)
        @test PERFORMANCE_COUNTERS_ENABLED ==
              get(preferences, "performance_counters", false)
    end

    if !PERFORMANCE_COUNTERS_ENABLED
        # Counting is compiled out: the machinery is inert but still transparent.
        # `run_with_performance_counters` runs the body and returns its value, and
        # `@measure_performance_time` yields its expression.
        counters = run_with_performance_counters() do
            a = Cell(1); b = Cell(@computation a[] + 1)
            _ = b[]; a[] = 2; _ = b[]
            @test (@measure_performance_time :timed_expr (1 + 2)) == 3
            get_performance_counters()
        end
        @test isempty(counters.counts) && isempty(counters.times)
        return
    end

    # Counting is compiled in: a scope binds a fresh store the engine counts into.
    # We test only the *sign* of the deltas (>= 1) — the exact bump count is an
    # engine-internal detail and would over-specify the test.
    counters = run_with_performance_counters() do
        a = Cell(1)
        b = Cell(@computation a[] + 1)
        _ = b[]           # first read: 1 compute + at least 2 reads (a, b)
        a[] = 2           # write + invalidation
        _ = b[]           # recompute

        # `@measure_performance_time` returns the expression's value and
        # records the elapsed nanoseconds.
        @test (@measure_performance_time :timed_expr (1 + 2)) == 3

        get_performance_counters()
    end
    @test counters.counts[:reads]         >= 1
    @test counters.counts[:computes]      >= 2
    @test counters.counts[:writes]        >= 1
    @test counters.counts[:invalidations] >= 1
    # A time goes into the times and never into the counts.
    @test counters.times[:timed_expr]     >= 0
    @test !haskey(counters.counts, :timed_expr)

    # Each scope gets its own fresh store — counts do not leak across scopes.
    fresh = run_with_performance_counters() do
        get_performance_counters()
    end
    @test fresh.counts[:reads] == 0
    @test isempty(fresh.times)

    # And the binding is gone once the scope exits.
    outside = get_performance_counters()
    @test isempty(outside.counts) && isempty(outside.times)
end
end # test_performance_counter
