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
using ProjecturedKernel.CellModule: Cell, Computation, @computation, is_cell_up_to_date

function test_clock()
@testset "Clock" begin

    @testset "sample vs subscribe" begin
        clock = Clock()
        set_clock_time!(clock, 0.0)
        @test get_clock_time(clock) == 0.0
        @test get_reactive_clock_time(clock) == 0.0

        # SUBSCRIBE: reading via get_reactive_clock_time makes the calling cell
        # a dependent, so the write invalidates it.
        subscribed = Cell(@computation get_reactive_clock_time(clock) * 2)
        @test subscribed[] == 0.0
        set_clock_time!(clock, 1.5)
        @test !is_cell_up_to_date(subscribed)
        @test subscribed[] == 3.0

        # SAMPLE: reading via get_clock_time registers nothing, so the write
        # leaves the cell valid.
        sampled = Cell(@computation get_clock_time(clock) + 10.0)
        @test sampled[] == 11.5
        set_clock_time!(clock, 2.0)
        @test is_cell_up_to_date(sampled)
        @test sampled[] == 11.5           # still the cached value
    end

    @testset "independence: setting one clock's time leaves others alone" begin
        a, b = Clock(), Clock()
        sub_a = Cell(@computation get_reactive_clock_time(a) + 1)
        sub_b = Cell(@computation get_reactive_clock_time(b) + 100)
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

    @testset "set_clock_time! writes a Float64 and returns nothing" begin
        clock = Clock()
        @test set_clock_time!(clock, 2) === nothing
        @test get_clock_time(clock) === 2.0
        @test (@inferred get_clock_time(clock)) === 2.0
        @test (@inferred get_reactive_clock_time(clock)) === 2.0
    end

    @testset "a time that is not a Float64 throws at the read" begin
        # The field of a `@cell_struct` takes any value, so the reads narrow.
        clock = Clock()
        clock.time = "text"
        @test_throws TypeError get_clock_time(clock)
        @test_throws TypeError get_reactive_clock_time(clock)
        @test repr(clock) == "Clock(time = text)"   # the display does not narrow
    end

    @testset "the wall clock is one clock, and its heartbeat moves it" begin
        wall = get_wall_clock()
        @test get_wall_clock() === wall
        before = get_clock_time(wall)
        deadline = time() + 5.0
        while get_clock_time(wall) == before && time() < deadline
            sleep(0.01)
        end
        @test get_clock_time(wall) > before
    end

    @testset "the heartbeat starts again after its task ends" begin
        get_wall_clock()
        old = ClockModule._HEARTBEAT_TASK[]
        schedule(old, InterruptException(); error = true)
        deadline = time() + 5.0
        while !istaskdone(old) && time() < deadline
            sleep(0.01)
        end
        @test istaskdone(old)
        get_wall_clock()
        new = ClockModule._HEARTBEAT_TASK[]
        @test new !== old
        @test !istaskdone(new)
    end

end
end # test_clock
