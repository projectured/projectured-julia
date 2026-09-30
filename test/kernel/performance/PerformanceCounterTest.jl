"""
`PerformanceModule` — conditionally-compiled reactive instrumentation.
The active counter store is a task-local binding established by
`with_performance_counters`. `@count_performance` adds to its counts, and
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

    if !PERFORMANCE_COUNTERS_ENABLED
        # Counting is compiled out: the machinery is inert but still transparent.
        # `with_performance_counters` runs the body and returns its value, and
        # `@measure_performance_time` yields its expression.
        counters = with_performance_counters() do
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
    counters = with_performance_counters() do
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
    fresh = with_performance_counters() do
        get_performance_counters()
    end
    @test fresh.counts[:reads] == 0
    @test isempty(fresh.times)

    # And the binding is gone once the scope exits.
    outside = get_performance_counters()
    @test isempty(outside.counts) && isempty(outside.times)
end
end # test_performance_counter
