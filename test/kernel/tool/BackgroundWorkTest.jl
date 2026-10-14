# Background work — code that runs on a task of the default pool while the editor
# goes on, `tool/BackgroundWork.jl`.
#
# The work answers its value or its exception, a stop ends its waits, and its
# stop and the stop of the unit that started it are apart. The unit that started
# the work can not wait for it while the unit runs. The waits of a work for its
# editor are in `HeldFramesTest.jl`, where an editor runs units.

using Test
using ProjecturedKernel.ToolModule

function test_background_work()
@testset "background work" begin
    @testset "the work runs on another task with the editor of the evaluation" begin
        work = start_background_work(() -> (current_task(), get_evaluation_editor());
                                     description = "a probe", editor = :the_editor)
        task, editor = fetch(work)
        @test task !== current_task()
        @test editor === :the_editor
        @test is_background_work_done(work)
        @test repr(work) == "BackgroundWork(\"a probe\", done)"
    end

    @testset "fetch throws the exception of the work" begin
        work = start_background_work(() -> error("the work failed"); editor = nothing)
        @test_throws ErrorException("the work failed") fetch(work)
        @test repr(work) == "BackgroundWork(\"background work\", failed)"
    end

    @testset "a stop ends the stoppable wait of the work" begin
        started = time()
        work = start_background_work(() -> wait_in_code_unit(10); editor = nothing)
        stop_background_work!(work)
        @test_throws InterruptException fetch(work)
        @test time() - started < 5
    end

    @testset "the stop of the unit does not stop the work that it started" begin
        unit = CodeUnit(["parent"])
        work = run_as_code_unit(unit) do
            work = start_background_work(editor = nothing) do
                wait_in_code_unit(0.2)
                :slept
            end
            stop_code_unit!(unit)
            work
        end
        @test fetch(work) === :slept
    end

    @testset "the unit that started the work can not wait for it while it runs" begin
        unit = CodeUnit(["parent"])
        work, from_unit, from_task = run_as_code_unit(unit) do
            work = start_background_work(() -> 1; editor = nothing)
            from_unit = try fetch(work) catch exception exception end
            from_task = fetch(@async try fetch(work) catch exception exception end)
            (work, from_unit, from_task)
        end
        @test from_unit isa BackgroundWorkWaitException
        @test from_task isa BackgroundWorkWaitException
        @test occursin("background work", sprint(showerror, from_unit))
        @test fetch(work) == 1                       # the unit ended
    end

    @testset "work in work keeps the unit of its start, and waits for its own work" begin
        unit = CodeUnit(["parent"])
        seen = Channel{Any}(1)
        parent, value = run_as_code_unit(unit) do
            start_background_work(editor = nothing) do
                inner = start_background_work(() -> 2; editor = nothing)
                put!(seen, (inner.parent, fetch(inner)))
            end
            take!(seen)
        end
        @test parent === unit
        @test value == 2
    end
end
end

export test_background_work
