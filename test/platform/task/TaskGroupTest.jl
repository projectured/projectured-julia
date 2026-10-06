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
