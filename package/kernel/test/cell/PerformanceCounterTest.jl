"""
`PerformanceCounterModule` — conditionally-compiled reactive instrumentation.
The active counter store is a task-local binding established by
`with_performance_counters`; the reactive engine bumps it via `@count_performance`.
"""

using Test
using ProjecturedKernel.PerformanceCounterModule
using ProjecturedKernel.CellModule: Cell, ComputedCell

function test_performance_counter()
@testset "PerformanceCounter" begin
    # Outside any scope the store reads empty and nothing shares state.
    @test isempty(get_performance_counters())

    if !PERFORMANCE_COUNTERS_ENABLED
        # Counting is compiled out: the machinery is inert but still transparent.
        # `with_performance_counters` runs the body and returns its value, the
        # recording verbs are no-ops, and `@performance_time` yields its expression.
        counts = with_performance_counters() do
            a = Cell(1); b = ComputedCell(() -> a[] + 1)
            _ = b[]; a[] = 2; _ = b[]
            record_performance!(:my_stage_ns, 100)
            @test (@performance_time :timed_expr (1 + 2)) == 3
            get_performance_counters()
        end
        @test isempty(counts)
        return
    end

    # Counting is compiled in: a scope binds a fresh store the engine counts into.
    # We test only the *sign* of the deltas (>= 1) — the exact bump count is an
    # engine-internal detail and would over-specify the test.
    counts = with_performance_counters() do
        a = Cell(1)
        b = ComputedCell(() -> a[] + 1)
        _ = b[]           # first read: 1 compute + at least 2 reads (a, b)
        a[] = 2           # write + invalidation
        _ = b[]           # recompute

        # `record_performance!` creates keys on demand and accumulates.
        record_performance!(:my_stage_ns, 100)
        record_performance!(:my_stage_ns, 250)

        # `@performance_time` returns the expression's value and records elapsed ns.
        @test (@performance_time :timed_expr (1 + 2)) == 3

        get_performance_counters()
    end
    @test counts[:reads]         >= 1
    @test counts[:computes]      >= 2
    @test counts[:writes]        >= 1
    @test counts[:invalidations] >= 1
    @test counts[:my_stage_ns]   == 350
    @test counts[:timed_expr]    >= 0

    # Each scope gets its own fresh store — counts do not leak across scopes.
    fresh = with_performance_counters() do
        get_performance_counters()
    end
    @test fresh[:reads] == 0

    # And the binding is gone once the scope exits.
    @test isempty(get_performance_counters())
end
end # test_performance_counter
