# What a task says while it runs, with plain shell commands as the work: the bound
# on the lines of a stream, the execution that the readers of a process write —
# its process, its times, its two streams apart, a fraction and a position that a
# kind reads from the lines, the use of the processor and of the memory — a stop,
# and a task that ends with no process.

struct _TaskExecutionProbeTask <: AbstractTask end
TaskModule.get_result_codes(::_TaskExecutionProbeTask) = RUN_RESULT_CODES

struct _TaskExecutionProbeResult <: TaskResult
    task::_TaskExecutionProbeTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

# Start `script` in `sh` as a task whose kind reads `progress N%` and `at X` lines,
# and ends DONE, ERROR or CANCEL by the exit code and the stop.
function _start_probe_process(script::AbstractString)
    execution = TaskExecution(_TaskExecutionProbeTask())
    read_line = function (e, line)
        m = match(r"progress (\d+)%", line)
        m === nothing || (e.progress = parse(Int, m.captures[1]) / 100)
        m = match(r"at (\S+)", line)
        m === nothing || (e.position = String(m.captures[1]))
    end
    finish = function (process, cancelled, elapsed)
        code = cancelled ? "CANCEL" : process.exitcode == 0 ? "DONE" : "ERROR"
        finish_task_execution!(execution,
            _TaskExecutionProbeResult(execution.task, code, "DONE", nothing, elapsed))
    end
    start_process_task!(execution, `sh -c $script`; read_line, finish)
end

function _wait_task_status(execution, status; seconds = 10)
    deadline = time() + seconds
    while execution.status !== status && time() < deadline
        sleep(0.02)
    end
    execution.status
end

function test_task_execution()
    @testset "task execution" begin
        @testset "a stream keeps its first and its last lines" begin
            lines = TaskOutput(; head = 2, tail = 3)
            @test find_last_output_line(lines) === nothing
            for i in 1:10
                append_output_line!(lines, "line $i")
            end
            @test lines.count == 10
            @test get_left_out_line_count(lines) == 5
            @test collect_output_lines(lines) ==
                  ["line 1", "line 2", "⋯ 5 lines left out ⋯", "line 8", "line 9", "line 10"]
            @test find_last_output_line(lines) == "line 10"
            @test endswith(format_output_text(lines), "line 10\n")
        end

        @testset "the execution of a process" begin
            execution = _start_probe_process(
                "echo 'progress 10% at one'; echo 'a warning' >&2; sleep 1; echo 'progress 50% at two'")
            @test _wait_task_status(execution, :running) === :running
            @test execution.process_id == getpid(execution.runtime.process)
            @test isdir("/proc/$(execution.process_id)")
            @test execution.start_time !== nothing && execution.end_time === nothing
            sample_task_usage!(execution)
            sleep(0.2)
            sample_task_usage!(execution)
            @test execution.resident_memory !== nothing && execution.resident_memory > 0
            @test execution.processor_load !== nothing && execution.processor_load >= 0
            wait_task_execution(execution)
            @test execution.result.result == "DONE"
            @test execution.status === :done
            @test execution.end_time >= execution.start_time
            # The two streams apart, and what the kind read from the lines.
            @test collect_output_lines(execution.output) == ["progress 10% at one", "progress 50% at two"]
            @test collect_output_lines(execution.error_output) == ["a warning"]
            @test execution.progress == 0.5 && execution.position == "two"
        end

        @testset "a shadow follows its execution, and a sync writes only what changed" begin
            execution = wait_task_execution(_start_probe_process("echo out; echo err >&2; exit 3"))
            shadow = make_task_execution_shadow(execution)
            @test shadow isa ACTaskExecution && shadow.runtime === nothing
            @test shadow.result.result == "ERROR" && shadow.status === :error
            @test collect_output_lines(shadow.output) == ["out"]
            @test collect_output_lines(shadow.error_output) == ["err"]
            # A reader of the status recomputes only when a sync writes the status.
            reads = Ref(0)
            status = Cell(nothing)
            set_cell_computation!(status, () -> (reads[] += 1; shadow.status))
            @test status[] === :error && reads[] == 1
            # The shadow holds a copy of a stream, which a later line does not change.
            output, error_output = shadow.output, shadow.error_output
            update_task_execution!(e -> append_output_line!(e.output, "late"), execution)
            @test collect_output_lines(shadow.output) == ["out"]
            sync_document!(shadow, execution)
            @test collect_output_lines(shadow.output) == ["out", "late"]
            @test shadow.output !== output && shadow.error_output === error_output
            @test status[] === :error && reads[] == 1
            update_task_execution!(e -> (e.status = :done), execution)
            sync_document!(shadow, execution)
            @test status[] === :done && reads[] == 2
        end

        @testset "a stop ends the process as cancelled" begin
            execution = _start_probe_process("sleep 30")
            @test _wait_task_status(execution, :running) === :running
            stop_task_execution!(execution)
            @test execution.status in (:cancelling, :cancelled)
            wait_task_execution(execution)
            @test execution.result.result == "CANCEL" && execution.status === :cancelled
            @test !is_task_running(execution)
        end

        @testset "a stop reaches the programs that the process started" begin
            execution = _start_probe_process("sleep 30; echo late")
            @test _wait_task_status(execution, :running) === :running
            stopped_at = time()
            stop_task_execution!(execution)
            wait_task_execution(execution)
            @test time() - stopped_at < 5
            @test execution.result.result == "CANCEL"
            @test isempty(collect_output_lines(execution.output))
        end

        @testset "a task that ends with no process" begin
            execution = TaskExecution(_TaskExecutionProbeTask())
            finished = Ref{Any}(nothing)
            finish_task_execution!(execution,
                _TaskExecutionProbeResult(execution.task, "SKIP", "SKIP", "nothing to do", nothing);
                finish = result -> (finished[] = result))
            @test execution.status === :skipped && finished[] === execution.result
            @test get_task_status("KEEP") === :done && get_task_status("FAIL") === :error
        end
    end
end
