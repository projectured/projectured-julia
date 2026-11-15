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
    start_process_task!(execution, `sh -c $(task.script)`; finish, on_finish)
end

# A kind of task whose end throws before it writes a result.
struct _TaskGroupFinishFailureProbe <: AbstractTask end
TaskModule.get_result_codes(::_TaskGroupFinishFailureProbe) = RUN_RESULT_CODES
TaskModule.start_task(task::_TaskGroupFinishFailureProbe; on_finish = nothing) =
    start_process_task!(TaskExecution(task), `sh -c "exit 0"`;
                        finish = (process, cancelled, elapsed) -> error("no result"), on_finish)

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

# A kind of task whose result is made of the results of smaller tasks, as the
# result of a fingerprint test is made of its fingerprints. A leaf is
# `(name, code, reason)`; a name of `nothing` is a leaf with no task.
struct _TaskNestedTask <: AbstractTask
    name::String
    leaves::Vector{Tuple{Union{String,Nothing},String,Union{String,Nothing}}}
end
TaskModule.get_result_codes(::_TaskNestedTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::_TaskNestedTask) = task.name

struct _TaskNestedLeafResult <: TaskResult
    task::Union{_TaskGroupProbeTask,Nothing}
    result::String
    expected_result::String
    reason::Union{String,Nothing}
end

struct _TaskNestedResult <: TaskResult
    task::_TaskNestedTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
    results::Vector{_TaskNestedLeafResult}
end
TaskModule.get_inner_task_results(result::_TaskNestedResult) = result.results

function TaskModule.start_task(task::_TaskNestedTask; on_finish = nothing)
    execution = TaskExecution(task)
    finish = function (process, cancelled, elapsed)
        leaves = [_TaskNestedLeafResult(name === nothing ? nothing : _TaskGroupProbeTask(name, ""),
                                        code, "DONE", reason) for (name, code, reason) in task.leaves]
        code = all(leaf -> leaf.result == "DONE", leaves) ? "DONE" : "ERROR"
        finish_task_execution!(execution, _TaskNestedResult(task, code, "DONE", nothing, elapsed, leaves);
                               finish = on_finish)
    end
    start_process_task!(execution, `sh -c "exit 0"`; finish, on_finish)
end

# Two tasks of nested results, a plain task that fails, and a group of one task
# that fails, all with a reason that the first of them shares.
function _make_task_nested_group()
    first_task = _TaskNestedTask("first", [("a1", "ERROR", "boom"), ("a2", "ERROR", nothing),
                                           ("a3", "DONE", nothing), ("a4", "ERROR", "zap"),
                                           (nothing, "ERROR", "boom")])
    second_task = _TaskNestedTask("second", [("b1", "ERROR", "boom"), ("b2", "ERROR", "boom")])
    inner = TaskGroup(AbstractTask[_TaskGroupProbeTask("inner fail", "exit 1")]; name = "inner")
    TaskGroup(AbstractTask[first_task, second_task, _TaskGroupProbeTask("fail", "exit 1"), inner];
              name = "nested", jobs = 2)
end

function test_task_group()
    @testset "task group" begin
        @testset "the pool holds the job count" begin
            group = TaskGroup(_make_task_group_probe_tasks(); jobs = 2)
            @test length(group) == 5
            @test measure_task_group_progress(group) == 0.0
            observed = Int[]
            start_task_group!(group)
            sampler = @async while group.runtime.scheduler === nothing || !istaskdone(group.runtime.scheduler)
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
            # The drivers run on other threads, so a task can end between two reads:
            # a sample counts only when no inner group changed while it was taken.
            read_counts(group) = (s = build_task_group_summary(group); (s.total, s.finished, s.running))
            sampler = @async while outer.runtime.scheduler === nothing || !istaskdone(outer.runtime.scheduler)
                before = [read_counts(phase) for phase in phases]
                summary = read_counts(outer)
                after = [read_counts(phase) for phase in phases]
                before == after &&
                    push!(agree, summary == Tuple(sum(counts[k] for counts in before) for k in 1:3))
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

        @testset "an imitation runs a group and starts no program" begin
            # The imitation answers for the script of each probe: its line, and the
            # exit code of the last command of the script.
            imitation = function (command, output, error_output)
                script = last(command.exec)
                println(output, "imitated ", script)
                endswith(script, "exit 1") ? 1 : 0
            end
            group = run_with_process_imitation(imitation) do
                run_task_group(TaskGroup(_make_task_group_probe_tasks(30); jobs = 2))
            end
            summary = build_task_group_summary(group)
            @test summary.finished == 5
            @test summary.counts["DONE"] == 4 && summary.counts["ERROR"] == 1
            @test all(execution -> execution.runtime.process isa ImitatedProcess &&
                                  execution.process_id === nothing, group.runs)
            @test all(execution -> any(startswith("imitated "), collect_output_lines(execution.output)),
                      group.runs)
            # The imitations end at once, though each script sleeps for 30 s.
            @test all(execution -> execution.end_time - execution.start_time < 10, group.runs)

            # An exception of the imitation ends it with the code 1 and its
            # message in the error output.
            group = run_with_process_imitation((command, output, error_output) -> error("no program")) do
                run_task_group(TaskGroup(_make_task_group_probe_tasks(0.0)[1:1]))
            end
            execution = only(group.runs)
            @test execution.result.result == "ERROR" && execution.runtime.process.exitcode == 1
            @test any(line -> occursin("no program", line), collect_output_lines(execution.error_output))

            # A stop records the signal, and the end reports the task as cancelled.
            release = Channel{Nothing}(1)
            waiting = (command, output, error_output) -> (take!(release); 0)
            group = TaskGroup(_make_task_group_probe_tasks(0.0)[1:1])
            run_with_process_imitation(() -> start_task_group!(group), waiting)
            deadline = time() + 10
            while build_task_group_summary(group).running < 1 && time() < deadline
                sleep(0.02)
            end
            stop_task_group!(group)
            put!(release, nothing)
            wait_task_group(group)
            execution = only(group.runs)
            @test execution.result.result == "CANCEL" && Base.process_signaled(execution.runtime.process)
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

        @testset "the tally gives the summary that a walk of every task gives" begin
            # The first task ends after the inner one, so the order of the ends is
            # not the order of the tasks; the details of the two unexpected
            # results tie, and the words list them in the order of the tasks.
            inner = TaskGroup(AbstractTask[_TaskGroupProbeTask("i1", "exit 0"),
                                           _TaskGroupProbeTask("i2", "exit 4")]; name = "inner", jobs = 2)
            tasks = AbstractTask[_TaskGroupProbeTask("a", "sleep 0.3; exit 3"), inner,
                                 _TaskGroupProbeTask("b", "exit 0")]
            group = run_task_group(TaskGroup(tasks; jobs = 2))
            walked = compute_task_group_result(group)
            summary = compute_task_group_summary(group)
            @test summary.total == 4 && summary.finished == 4 && summary.running == 0
            @test summary.result == walked.result == "ERROR"
            @test summary.summary == format_task_group_summary(walked)
            @test summary.reason == format_task_group_reason(walked) ==
                  "2/4 unexpected: 1x Non-zero exit code: 3, 1x Non-zero exit code: 4"
            @test summary.counts == [(code, walked.num_expected[code], walked.num_unexpected[code])
                                     for code in group.codes.codes
                                     if walked.num_expected[code] + walked.num_unexpected[code] > 0]
            @test summary.slowest !== nothing && summary.slowest[1] == "a"
            @test build_task_group_summary(group).counts == Dict("DONE" => 2, "ERROR" => 2)
            # A run again counts the failures again, and no result twice.
            wait_task_group(rerun_task_group!(group, :failed))
            @test compute_task_group_summary(group).finished == 4
            @test compute_task_group_summary(group).summary ==
                  format_task_group_summary(compute_task_group_result(group))
        end

        @testset "a shadow of a group follows its counts, and writes what changed" begin
            group = TaskGroup(AbstractTask[_TaskGroupProbeTask("a", "exit 0"),
                                           _TaskGroupProbeTask("b", "exit 1")]; jobs = 1)
            shadow = make_task_group_shadow(group)
            @test shadow isa ACTaskGroup && isempty(shadow.runs) && shadow.runtime === nothing
            @test shadow.counts.pending == 2 && shadow.summary.finished == 0
            reads = Ref(0)
            counts = Cell(nothing)
            set_cell_computation!(counts, () -> (reads[] += 1; shadow.counts))
            @test counts[].pending == 2 && reads[] == 1
            sync_document!(shadow, group)                   # nothing changed
            @test counts[].pending == 2 && reads[] == 1
            run_task_group(group)
            sync_document!(shadow, group)
            @test counts[].finished == 2 && reads[] == 2
            @test shadow.summary.result == "ERROR"
        end

        @testset "the unexpected leaves of the results are counted by reason, and a leaf is named by its task" begin
            leaf = _TaskGroupProbeResult(_TaskGroupProbeTask("x", ""), "ERROR", "DONE", "bad", nothing)
            @test get_inner_task_results(leaf) == TaskResult[]
            group = run_task_group(_make_task_nested_group())
            result = compute_task_group_result(group)
            @test result isa TaskGroupResult && get_inner_task_results(result) === result.results
            @test length(get_inner_task_results(result.results[1])) == 5
            summary = compute_task_group_summary(group)
            # A leaf with no task is named by the task that ended with it; a leaf that gives no
            # reason gives its code; reasons of equal count keep the order in which they came.
            @test summary.reasons == [("boom", 4, ["a1", "first", "b1", "b2"]),
                                      ("Non-zero exit code: 1", 2, ["fail", "inner fail"]),
                                      ("ERROR", 1, ["a2"]), ("zap", 1, ["a4"])]
            # `reason` keeps the words of opp_repl, counted over the results of the tasks.
            @test summary.reason == "4/4 unexpected: 2x ERROR, 2x Non-zero exit code: 1"
            counts = get_task_group_counts(summary)
            @test counts.reasons == summary.reasons
            @test compute_task_group_summary(TaskGroup(_make_task_group_probe_tasks(0.0); jobs = 4)).reasons == []
            @test compute_task_group_summary(run_task_group(
                TaskGroup(AbstractTask[_TaskGroupProbeTask("ok", "exit 0")]))).reasons == []
        end

        @testset "a sync with no start and no end writes the counts no more" begin
            group = run_task_group(_make_task_nested_group())
            shadow = make_task_group_shadow(group)
            before = shadow.counts
            @test !isempty(before.reasons)
            reads = Ref(0)
            counts = Cell(nothing)
            set_cell_computation!(counts, () -> (reads[] += 1; shadow.counts))
            @test counts[].reasons == before.reasons && reads[] == 1
            sync_document!(shadow, group)
            sync_document!(shadow, group)
            @test shadow.counts === before && counts[].reasons == before.reasons && reads[] == 1
        end

        @testset "an end that throws ends its task as an error, and the group ends" begin
            group = TaskGroup(AbstractTask[_TaskGroupFinishFailureProbe(),
                                           _TaskGroupProbeTask("after", "exit 0")]; jobs = 1)
            runner = @test_logs (:error, "the end of a task failed") match_mode = :any begin
                runner = @async run_task_group(group)
                deadline = time() + 10
                while !istaskdone(runner) && time() < deadline
                    sleep(0.02)
                end
                runner
            end
            @test istaskdone(runner)
            results = collect_task_group_results(group)
            @test results[1] isa TaskFinishFailure && results[1].result == "ERROR"
            @test occursin("no result", results[1].reason)
            @test results[2].result == "DONE"
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
            group.runtime.on_preparation = execution -> push!(started, execution)
            run_task_group(group)
            @test only(started) === group.runtime.preparation_run
            @test group.runtime.preparation_run.result.result == "DONE"
            # The tasks found what the preparation made, and only they are counted.
            summary = build_task_group_summary(group)
            @test summary.total == 2 && summary.counts == Dict("DONE" => 2)
            @test length(group) == 2

            failing = TaskGroup(tasks; jobs = 1,
                                preparation = TaskGroup([_TaskGroupProbeTask("compile", "exit 2")];
                                                        name = "stub", action = "Building"))
            run_task_group(failing)
            @test failing.runtime.preparation_run.result.result == "ERROR"
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
            while (group.runtime.preparation_run === nothing || !is_task_running(group.runtime.preparation_run)) && time() < deadline
                sleep(0.02)
            end
            stopped_at = time()
            stop_task_group!(group)
            wait_task_group(group)
            @test time() - stopped_at < 10
            @test group.runtime.preparation_run.result.result == "CANCEL"
            @test group.runs[1] === nothing
        end

        @testset "a group that stops at a failure starts no task after a failed one" begin
            chain(scripts...; kwargs...) = TaskGroup(
                AbstractTask[_TaskGroupProbeTask(name, script) for (name, script) in scripts];
                kwargs...)
            codes(group) = [run === nothing ? "-" : run.result.result for run in group.runs]

            group = run_task_group(chain("one" => "exit 0", "two" => "exit 1", "three" => "exit 0";
                                         jobs = 1, stop_at_failure = true))
            @test codes(group) == ["DONE", "ERROR", "CANCEL"]
            skipped = group.runs[3].result
            @test skipped isa TaskNotStarted
            @test skipped.reason == "Not started: two ended ERROR"
            @test format_task_group_description(group) == "task (3 sequential, stops at a failure)"

            # With the default, each task runs.
            group = run_task_group(chain("one" => "exit 0", "two" => "exit 1", "three" => "exit 0";
                                         jobs = 1))
            @test codes(group) == ["DONE", "ERROR", "DONE"]

            # With two jobs, the tasks that go run to their end.
            group = run_task_group(chain("fail" => "exit 1", "slow" => "sleep 0.3",
                                         "next" => "exit 0", "last" => "exit 0";
                                         jobs = 2, stop_at_failure = true))
            @test codes(group) == ["ERROR", "DONE", "CANCEL", "CANCEL"]
            @test group.runs[4].result.reason == "Not started: fail ended ERROR"

            # An inner group after the failure ends each of its tasks.
            inner = chain("x" => "exit 0", "y" => "exit 0"; name = "inner")
            group = TaskGroup(AbstractTask[_TaskGroupProbeTask("bad", "exit 1"), inner];
                              jobs = 1, stop_at_failure = true)
            run_task_group(group)
            @test codes(inner) == ["CANCEL", "CANCEL"]
            @test all(run.result isa TaskNotStarted for run in inner.runs)
            @test build_task_group_summary(group).counts == Dict("ERROR" => 1, "CANCEL" => 2)

            # A stop of the second task ends it CANCEL, and the third does not start.
            group = chain("one" => "exit 0",
                          "two" => "trap 'kill \$!; exit 130' INT; sleep 30 & wait \$!",
                          "three" => "exit 0"; jobs = 1, stop_at_failure = true)
            start_task_group!(group)
            deadline = time() + 10
            while (group.runs[2] === nothing || !is_task_running(group.runs[2])) && time() < deadline
                sleep(0.02)
            end
            stop_task_execution!(group.runs[2])
            wait_task_group(group)
            @test codes(group) == ["DONE", "CANCEL", "CANCEL"]
            @test group.runs[3].result.reason == "Not started: two ended CANCEL"

            # A run again of what did not succeed follows the same rule.
            folder = mktempdir()
            flag = joinpath(folder, "flag")
            group = chain("one" => "exit 0", "two" => "test -f $flag", "three" => "exit 0",
                          "four" => "test -f $flag"; jobs = 1, stop_at_failure = true)
            run_task_group(group)
            @test codes(group) == ["DONE", "ERROR", "CANCEL", "CANCEL"]
            @test compute_task_group_indices(group, :unexpected) == [2, 3, 4]
            touch(flag)
            rerun_task_group!(group, :unexpected)
            wait_task_group(group)
            @test codes(group) == ["DONE", "DONE", "DONE", "DONE"]
            rm(flag)
            rerun_task_group!(group, [2, 3, 4])
            wait_task_group(group)
            @test codes(group) == ["DONE", "ERROR", "CANCEL", "CANCEL"]
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
