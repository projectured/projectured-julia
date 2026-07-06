"""
`PerformanceCounterModule` — the process-global counter store the reactive
engine bumps inline (CellModule mutates it on the hot path).
"""

using Test
using ProjecturedKernel.PerformanceCounterModule
using ProjecturedKernel.CellModule: Cell

@testset "PerformanceCounter" begin
    reset_performance_counters!()
    perf0 = get_performance_counters()
    @test perf0[:reads] == 0
    @test perf0[:computes] == 0
    @test perf0[:invalidations] == 0
    @test perf0[:writes] == 0

    # A single reactive read/compute/write cycle bumps the engine counters. We
    # test only the *sign* of the deltas (>= 1) — the exact bump count is an
    # engine-internal detail and would over-specify the test.
    a = Cell(1)
    b = Cell(() -> a[] + 1)
    _ = b[]           # first read: 1 compute + at least 2 reads (a, b)
    a[] = 2           # write + invalidation
    _ = b[]           # recompute

    p = get_performance_counters()
    @test p[:reads]         >= 1
    @test p[:computes]      >= 2
    @test p[:writes]        >= 1
    @test p[:invalidations] >= 1

    # `record_performance!` creates keys on demand and accumulates.
    record_performance!(:my_stage_ns, 100)
    record_performance!(:my_stage_ns, 250)
    @test get_performance_counters()[:my_stage_ns] == 350

    # `@performance_time` returns the expression's value and records elapsed ns.
    reset_performance_counters!()
    v = @performance_time :timed_expr (1 + 2)
    @test v == 3
    @test get_performance_counters()[:timed_expr] >= 0

    # Reset clears both engine and user-registered counters.
    reset_performance_counters!()
    p2 = get_performance_counters()
    @test all(v -> v == 0, values(p2))
    @test haskey(p2, :my_stage_ns)      # keys survive, values zero'd
end
