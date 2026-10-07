# A group of tasks with plain shell commands as the work: the pool holds the job
# count, a result keeps the place of its task, a run again touches only what it
# names, and a stop ends every task.

struct _TaskGroupProbeTask <: AbstractTask
    name::String
    script::String
end
TaskModule.get_result_codes(::_TaskGroupProbeTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::_TaskGroupProbeTask) = task.name

struct _TaskGroupProbeResult <: TaskResult
    task::_TaskGroupProbeTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

function TaskModule.start_task(task::_TaskGroupProbeTask; on_finish = nothing)
    execution = TaskExecution(task)
    finish = function (process, cancelled, elapsed)
        code = cancelled ? "CANCEL" : process.exitcode == 0 ? "DONE" : "ERROR"
        reason = code == "ERROR" ? "Non-zero exit code: " * string(process.exitcode) : nothing
        finish_task_execution!(execution,
            _TaskGroupProbeResult(task, code, "DONE", reason, elapsed); finish = on_finish)
    end
    start_process_task!(execution, `sh -c $(task.script)`; finish)
end

# A kind of task whose start throws.
struct _TaskGroupStartFailureProbe <: AbstractTask end
TaskModule.get_result_codes(::_TaskGroupStartFailureProbe) = RUN_RESULT_CODES
TaskModule.start_task(::_TaskGroupStartFailureProbe; on_finish = nothing) = error("no start")

# Five tasks that sleep, and one of them fails. The shell waits for its sleep in
# the background, so an interrupt stops the sleep and ends the shell at once.
_make_task_group_probe_tasks(seconds = 0.3) =
    [_TaskGroupProbeTask(name, "trap 'kill \$!; exit 130' INT; sleep $seconds & wait \$!; " *
                               "exit $(name == "fail" ? 1 : 0)")
     for name in ("a", "b", "fail", "c", "d")]

function test_task_group()
    @testset "task group" begin
        @testset "the pool holds the job count" begin
            group = TaskGroup(_make_task_group_probe_tasks(); jobs = 2)
            @test length(group) == 5
            @test measure_task_group_progress(group) == 0.0
            observed = Int[]
            start_task_group!(group)
            sampler = @async while group.scheduler === nothing || !istaskdone(group.scheduler)
                push!(observed, build_task_group_summary(group).running)
                sleep(0.02)
            end
            wait_task_group(group)
            wait(sampler)
            @test maximum(observed) == 2
            @test all(<=(2), observed)
            summary = build_task_group_summary(group)
            @test summary.total == 5 && summary.finished == 5
            @test summary.running == 0 && summary.pending == 0
            @test summary.counts["DONE"] == 4 && summary.counts["ERROR"] == 1
            @test summary.overall == "ERROR"
            @test measure_task_group_progress(group) == 1.0
        end

        @testset "a result keeps the place of its task" begin
            group = run_task_group(TaskGroup(_make_task_group_probe_tasks(0.0); name = "probe",
                                             action = "Running", jobs = 4))
            results = collect_task_group_results(group)
            @test all(((task, result),) -> result.task === task, zip(group.tasks, results))
            failed = compute_task_group_indices(group, :failed)
            @test group.tasks[only(failed)].name == "fail"
            @test isempty(compute_task_group_indices(group, :unfinished))
            @test compute_task_group_indices(group, :unexpected) == failed
            result = compute_task_group_result(group)
            @test startswith(format_task_group_summary(result), "5 TOTAL, 4 DONE, 1 ERROR (unexpected)")
            @test format_task_group_reason(result) == "1/5 unexpected: 1x Non-zero exit code: 1"
            @test format_task_group_close_description(group) == "Ran probe (5 concurrent)"
            @test occursin("\n  fail ERROR (unexpected)", repr(result))
        end

        @testset "a run again touches only what it names" begin
            group = run_task_group(TaskGroup(_make_task_group_probe_tasks(0.0); jobs = 4))
            failed = only(compute_task_group_indices(group, :failed))
            kept = first(i for i in eachindex(group.tasks) if i != failed)
            before = group.runs[kept]
            rerun_task_group!(group, :failed)
            wait_task_group(group)
            @test group.runs[kept] === before
            @test group.runs[failed].result.result == "ERROR"
            @test build_task_group_summary(group).finished == 5
        end

        @testset "a group of groups counts the tasks of its inner groups" begin
            phases = [TaskGroup(_make_task_group_probe_tasks(0.2); name = "phase $i", jobs = 2)
                      for i in 1:2]
            outer = TaskGroup(phases; name = "build", action = "Building", jobs = 1)
            @test !is_concurrent(outer) && get_result_codes(outer) === RUN_RESULT_CODES
            agree = Bool[]
            start_task_group!(outer)
            sampler = @async while outer.scheduler === nothing || !istaskdone(outer.scheduler)
                summary = build_task_group_summary(outer)
                inner = [build_task_group_summary(phase) for phase in phases]
                push!(agree, summary.total == sum(s.total for s in inner) &&
                             summary.finished == sum(s.finished for s in inner) &&
                             summary.running == sum(s.running for s in inner))
                sleep(0.02)
            end
            wait_task_group(outer)
            wait(sampler)
            @test !isempty(agree) && all(agree)
            summary = build_task_group_summary(outer)
            @test summary.total == 10 && summary.finished == 10
            @test summary.counts["DONE"] == 8 && summary.counts["ERROR"] == 2
            # A sequential group runs its phases one after the other.
            @test phases[2].start_time >= phases[1].end_time
            @test startswith(format_task_group_summary(compute_task_group_result(outer)),
                             "10 TOTAL, 8 DONE, 2 ERROR (unexpected)")
            first_phase = outer.runs[1].result
            @test first_phase isa TaskGroupResult && first_phase.task === phases[1]
            @test first_phase.result == "ERROR" && !is_expected(first_phase)
            @test outer.runs[1].position == "5/5" && outer.runs[1].progress == 1.0
        end

        @testset "a stop of a group stops its inner groups" begin
            phases = [TaskGroup(_make_task_group_probe_tasks(30); name = "phase $i", jobs = 5)
                      for i in 1:2]
            outer = TaskGroup(phases; jobs = 1)
            start_task_group!(outer)
            deadline = time() + 10
            while build_task_group_summary(outer).running < 5 && time() < deadline
                sleep(0.02)
            end
            stopped_at = time()
            stop_task_group!(outer)
            wait_task_group(outer)
            @test time() - stopped_at < 10
            @test build_task_group_summary(outer).running == 0
            @test outer.runs[1].result.result == "CANCEL"
            @test outer.runs[2] === nothing
        end

        @testset "a start that throws ends its task as an error, and the group goes on" begin
            tasks = AbstractTask[_TaskGroupProbeTask("a", "exit 0"), _TaskGroupStartFailureProbe(),
                                 _TaskGroupProbeTask("c", "exit 0")]
            group = run_task_group(TaskGroup(tasks; jobs = 1))
            results = collect_task_group_results(group)
            @test [r.result for r in results] == ["DONE", "ERROR", "DONE"]
            @test results[2] isa TaskStartFailure && startswith(results[2].reason, "The start failed: ")
            @test build_task_group_summary(group).finished == 3
        end

        @testset "a preparation runs first, and its failure keeps every task from starting" begin
            folder = mktempdir()
            marker = joinpath(folder, "prepared")
            tasks = AbstractTask[_TaskGroupProbeTask("a", "test -f $marker"),
                                 TaskGroup([_TaskGroupProbeTask("b", "test -f $marker")]; name = "inner")]
            group = TaskGroup(tasks; jobs = 1,
                              preparation = _TaskGroupProbeTask("prepare", "touch $marker"))
            started = Any[]
            group.on_preparation = execution -> push!(started, execution)
            run_task_group(group)
            @test only(started) === group.preparation_run
            @test group.preparation_run.result.result == "DONE"
            # The tasks found what the preparation made, and only they are counted.
            summary = build_task_group_summary(group)
            @test summary.total == 2 && summary.counts == Dict("DONE" => 2)
            @test length(group) == 2

            failing = TaskGroup(tasks; jobs = 1,
                                preparation = TaskGroup([_TaskGroupProbeTask("compile", "exit 2")];
                                                        name = "stub", action = "Building"))
            run_task_group(failing)
            @test failing.preparation_run.result.result == "ERROR"
            results = collect_task_group_results(failing)
            @test results[1] isa TaskNotStarted && results[1].result == "CANCEL"
            @test results[1].reason == "Not started: building stub ended ERROR"
            # An inner group ends each of its tasks so.
            inner = only(collect_task_group_results(failing.tasks[2]))
            @test inner isa TaskNotStarted && inner.result == "CANCEL"
            @test build_task_group_summary(failing).counts == Dict("CANCEL" => 2)
            @test !is_expected(compute_task_group_result(failing))

            # A run again runs the preparation again.
            rm(marker)
            rerun_task_group!(group, :all)
            wait_task_group(group)
            @test length(started) == 2 && isfile(marker)
        end

        @testset "a stop of a group stops its preparation" begin
            group = TaskGroup([_TaskGroupProbeTask("a", "exit 0")];
                              preparation = _TaskGroupProbeTask("prepare", "trap 'kill \$!; exit 130' INT; sleep 30 & wait \$!"))
            start_task_group!(group)
            deadline = time() + 10
            while (group.preparation_run === nothing || !is_task_running(group.preparation_run)) && time() < deadline
                sleep(0.02)
            end
            stopped_at = time()
            stop_task_group!(group)
            wait_task_group(group)
            @test time() - stopped_at < 10
            @test group.preparation_run.result.result == "CANCEL"
            @test group.runs[1] === nothing
        end

        @testset "a stop ends every task" begin
            group = TaskGroup(_make_task_group_probe_tasks(30); jobs = 5)
            start_task_group!(group)
            deadline = time() + 10
            while build_task_group_summary(group).running < 2 && time() < deadline
                sleep(0.02)
            end
            @test build_task_group_summary(group).running >= 2
            stopped_at = time()
            stop_task_group!(group)
            wait_task_group(group)
            @test time() - stopped_at < 10
            summary = build_task_group_summary(group)
            @test summary.running == 0
            @test summary.finished + summary.pending == 5
            @test all(run === nothing || run.result.result == "CANCEL" for run in group.runs)
            @test compute_task_group_summary(group).result == "CANCEL"
        end
    end
end
