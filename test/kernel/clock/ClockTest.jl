"""
`ClockModule` — the animation clock as a per-instance `@cell_struct`.

Confirms:
- the two reads: `get_clock_time` records no dependency, and
  `get_reactive_clock_time` records one, so a write of the time invalidates the
  computation that reads it;
- the independence of two clocks: a write to one clock does not invalidate a
  reader of another, so many editors can run in one process;
- the write `set_clock_time!`, the conversion of a real time to `Float64`, a
  time that is not a real number, and `show`.
"""

using Test
using ProjecturedKernel.ClockModule
using ProjecturedKernel.CellModule: Cell, Computation, @computation, is_cell_valid

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
        @test !is_cell_valid(subscribed)
        @test subscribed[] == 3.0

        # SAMPLE: reading via get_clock_time registers nothing, so the write
        # leaves the cell valid.
        sampled = Cell(@computation get_clock_time(clock) + 10.0)
        @test sampled[] == 11.5
        set_clock_time!(clock, 2.0)
        @test is_cell_valid(sampled)
        @test sampled[] == 11.5           # still the cached value
    end

    @testset "independence: setting one clock's time leaves others alone" begin
        a, b = Clock(), Clock()
        sub_a = Cell(@computation get_reactive_clock_time(a) + 1)
        sub_b = Cell(@computation get_reactive_clock_time(b) + 100)
        @test sub_a[] == 1.0
        @test sub_b[] == 100.0

        set_clock_time!(a, 5.0)
        @test !is_cell_valid(sub_a)         # a's subscriber was invalidated
        @test is_cell_valid(sub_b)          # b's was not
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

    @testset "a real time reads as a Float64" begin
        @test get_clock_time(Clock(0)) === 0.0
        @test get_clock_time(Clock(2)) === 2.0
        @test get_clock_time(Clock(1//2)) === 0.5
        # The keyword constructor and a write of the field store the value as it is,
        # and the reads convert it.
        @test get_clock_time(Clock(time = 3)) === 3.0
        clock = Clock()
        clock.time = 4
        @test (@inferred get_reactive_clock_time(clock)) === 4.0
    end

    @testset "a time that is not a real number throws at the read" begin
        clock = Clock()
        clock.time = "text"
        @test_throws MethodError get_clock_time(clock)
        @test_throws MethodError get_reactive_clock_time(clock)
        @test repr(clock) == "Clock(time = text)"   # the display does not convert
    end

end
end # test_clock
