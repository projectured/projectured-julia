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

# Waits until `condition()` holds, for at most five seconds.
function _wait_for_clock_condition(condition)
    deadline = time() + 5.0
    while !condition() && time() < deadline
        sleep(0.01)
    end
    condition()
end

# Starts a heartbeat on a clock that nothing else holds, and returns its task.
_start_and_drop_clock() = start_wall_clock!(Clock()).heartbeat

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

    @testset "start_wall_clock! moves a clock, and stop_wall_clock! ends it" begin
        clock = Clock()
        @test clock.heartbeat === nothing
        @test start_wall_clock!(clock) === clock
        task = clock.heartbeat
        @test task isa Task
        start_wall_clock!(clock)                    # a running heartbeat stays
        @test clock.heartbeat === task
        @test _wait_for_clock_condition(() -> get_clock_time(clock) > 0.0)
        @test stop_wall_clock!(clock) === nothing
        @test clock.heartbeat === nothing
        @test _wait_for_clock_condition(() -> istaskdone(task))
        stopped = get_clock_time(clock)
        sleep(0.05)
        @test get_clock_time(clock) == stopped      # no more writes
        stop_wall_clock!(clock)                     # a second stop does nothing
        @test clock.heartbeat === nothing
    end

    @testset "a stopped clock starts again" begin
        clock = start_wall_clock!(Clock())
        first = clock.heartbeat
        stop_wall_clock!(clock)
        @test _wait_for_clock_condition(() -> istaskdone(first))
        start_wall_clock!(clock)
        @test clock.heartbeat !== first
        @test !istaskdone(clock.heartbeat)
        stop_wall_clock!(clock)
    end

    @testset "a heartbeat ends when its unstopped clock is freed" begin
        task = _start_and_drop_clock()
        @test _wait_for_clock_condition(() -> (GC.gc(); istaskdone(task)))
    end

    @testset "the heartbeat runs on the thread of the task that starts it" begin
        threads = fetch(Threads.@spawn begin
            clock = start_wall_clock!(Clock())
            result = (Threads.threadid(), Threads.threadid(clock.heartbeat),
                      current_task().sticky)
            stop_wall_clock!(clock)
            result
        end)
        @test threads[1] == threads[2]
        @test threads[3]                            # the starter stays on its thread
    end

end
end # test_clock
