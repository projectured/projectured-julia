"""
`ClockModule` — the animation clock as a per-instance `@cell_struct`.

Confirms:
- the sample/subscribe split: `get_clock_time` reads without registering a
  dependency, `get_reactive_clock_time` registers and re-runs when the
  clock's time is set;
- clock independence: writing one clock does not invalidate subscribers of
  another (the property that lets many editors run in one process without
  their animation clocks cross-invalidating).
"""

using Test
using ProjecturedKernel.ClockModule
using ProjecturedKernel.CellModule: Cell, ComputedCell, is_cell_up_to_date

function test_clock()
@testset "Clock" begin

    @testset "sample vs subscribe" begin
        clock = Clock()
        set_clock_time!(clock, 0.0)
        @test get_clock_time(clock) == 0.0
        @test get_reactive_clock_time(clock) == 0.0

        # SUBSCRIBE: reading via get_reactive_clock_time makes the calling cell
        # a dependent, so the write invalidates it.
        subscribed = ComputedCell(() -> get_reactive_clock_time(clock) * 2)
        @test subscribed[] == 0.0
        set_clock_time!(clock, 1.5)
        @test !is_cell_up_to_date(subscribed)
        @test subscribed[] == 3.0

        # SAMPLE: reading via get_clock_time registers nothing, so the write
        # leaves the cell valid.
        sampled = ComputedCell(() -> get_clock_time(clock) + 10.0)
        @test sampled[] == 11.5
        set_clock_time!(clock, 2.0)
        @test is_cell_up_to_date(sampled)
        @test sampled[] == 11.5           # still the cached value
    end

    @testset "independence: setting one clock's time leaves others alone" begin
        a, b = Clock(), Clock()
        sub_a = ComputedCell(() -> get_reactive_clock_time(a) + 1)
        sub_b = ComputedCell(() -> get_reactive_clock_time(b) + 100)
        @test sub_a[] == 1.0
        @test sub_b[] == 100.0

        set_clock_time!(a, 5.0)
        @test !is_cell_up_to_date(sub_a)         # a's subscriber was invalidated
        @test is_cell_up_to_date(sub_b)          # b's was not
        @test sub_a[] == 6.0
        @test sub_b[] == 100.0
    end

    @testset "set_clock_time! sets absolute logical time" begin
        clock = Clock()
        set_clock_time!(clock, 3.14)
        @test get_clock_time(clock) == 3.14
    end

    @testset "a clock shows as its constructor makes it" begin
        clock = Clock()
        set_clock_time!(clock, 12.5)
        @test repr(clock) == "Clock(time = 12.5)"
    end

end
end # test_clock
