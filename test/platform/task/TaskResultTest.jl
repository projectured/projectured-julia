# What every kind of task shares: the codes of a result and their roles, a result
# in one line, and a time span, each written as `opp_repl` writes it. The cases
# are those that `tool/parity/opp_repl_task_summary.py` of omnet-julia takes from
# the Python of `opp_repl`.

struct _TaskResultProbeTask <: AbstractTask
    codes::ResultCodes
end
TaskModule.get_result_codes(task::_TaskResultProbeTask) = task.codes

struct _TaskResultProbeResult <: TaskResult
    task::_TaskResultProbeTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    error_message::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end
TaskModule.get_error_message(result::_TaskResultProbeResult) =
    something(result.error_message, "<No error message>")

const _TASK_RESULT_TIMES = [(0.12, "0.12"), (45.0, "45"), (65.1, "1:05.1"), (3661.0, "1:01:01"),
                            (0.0004, "0"), (59.9996, "1:00"), (192.0, "3:12"), (0.5, "0.5"),
                            (7200.25, "2:00:00.25")]

_make_task_probe_result(codes, result, expected; reason = nothing, error = nothing, elapsed = nothing) =
    _TaskResultProbeResult(_TaskResultProbeTask(codes), result, expected, reason, error, elapsed)

function test_task_result()
    @testset "task result" begin
        @testset "a time span is written as opp_repl writes it" begin
            for (seconds, text) in _TASK_RESULT_TIMES
                @test format_elapsed_time(seconds) == text
            end
        end
        @testset "a code has the role of its colour in opp_repl" begin
            @test get_result_role(RUN_RESULT_CODES, "DONE") === :success
            @test get_result_role(RUN_RESULT_CODES, "CANCEL") === :info
            @test get_result_role(TEST_RESULT_CODES, "FAIL") === :warning
            @test get_result_role(UPDATE_RESULT_CODES, "UPDATE") === :warning
            @test get_result_role(UPDATE_RESULT_CODES, "ERROR") === :error
            @test_throws ErrorException get_result_role(RUN_RESULT_CODES, "PASS")
        end
        @testset "a result in one line, as opp_repl writes it" begin
            @test format_task_result(_make_task_probe_result(TEST_RESULT_CODES, "FAIL", "PASS";
                      reason = "Fingerprint mismatch", elapsed = 1.5)) ==
                  "FAIL (unexpected) (Fingerprint mismatch) in 1.5"
            @test format_task_result(_make_task_probe_result(TEST_RESULT_CODES, "ERROR", "PASS";
                      reason = "Non-zero exit code: 1", error = "<!> Error: boom", elapsed = 0.75)) ==
                  "ERROR (unexpected) (Non-zero exit code: 1) <!> Error: boom in 0.75"
            @test format_task_result(_make_task_probe_result(RUN_RESULT_CODES, "SKIP", "SKIP";
                      reason = "Unbounded simulation")) == "SKIP (expected) (Unbounded simulation)"
            @test is_expected(_make_task_probe_result(RUN_RESULT_CODES, "DONE", "DONE"))
        end
        @testset "an action is written in the past tense when its group ends" begin
            @test format_past_tense("Running") == "Ran"
            @test format_past_tense("Checking fingerprint") == "Checking fingerprint"
        end
    end
end
