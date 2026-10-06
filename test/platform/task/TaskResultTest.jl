# What every kind of task shares: the codes of a result and their roles, a result
# in one line, a time span, and the result of a group, each written as `opp_repl`
# writes it. `tool/parity/opp_repl_task_summary.py` of omnet-julia makes the
# table of groups below from the Python of `opp_repl`; it is kept here, so the
# test needs no Python.

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

const _TASK_RESULT_FAMILIES = Dict(:run => RUN_RESULT_CODES, :test => TEST_RESULT_CODES,
                                   :update => UPDATE_RESULT_CODES)

# Each case: the group, its results as (result, expected_result, reason,
# error_message, elapsed_wall_time), and what `opp_repl` answered.
const _OPP_REPL_GROUP_CASES = [
    (family = :run, name = "simulation", action = "Running", concurrent = true, elapsed = 3.25,
     results = [("DONE", "DONE", nothing, nothing, 1.0), ("DONE", "DONE", nothing, nothing, 1.0), ("DONE", "DONE", nothing, nothing, 1.0), ("DONE", "DONE", nothing, nothing, 1.0), ("ERROR", "DONE", "Non-zero exit code: 1", "boom", 0.5)],
     result = "ERROR", expected = false, summary = "5 TOTAL, 4 DONE, 1 ERROR (unexpected) in 3.25",
     reason = "1/5 unexpected: 1x Non-zero exit code: 1",
     close = "Ran simulation (5 concurrent)", description = "Running simulation (5 concurrent)"),
    (family = :run, name = "simulation", action = "Running", concurrent = true, elapsed = 0.0,
     results = [("DONE", "DONE", nothing, nothing, nothing), ("DONE", "DONE", nothing, nothing, nothing), ("DONE", "DONE", nothing, nothing, nothing)],
     result = "DONE", expected = true, summary = "3 DONE",
     reason = nothing,
     close = "Ran simulation (3 concurrent)", description = "Running simulation (3 concurrent)"),
    (family = :run, name = "simulation", action = "Running", concurrent = false, elapsed = 2.0,
     results = [("DONE", "DONE", nothing, nothing, nothing), ("SKIP", "SKIP", "Unbounded simulation", nothing, nothing), ("SKIP", "SKIP", "Unbounded simulation", nothing, nothing)],
     result = "DONE", expected = true, summary = "3 TOTAL, 1 DONE, 2 SKIP (expected) in 2",
     reason = nothing,
     close = "Ran simulation (3 sequential)", description = "Running simulation (3 sequential)"),
    (family = :run, name = "simulation", action = "Running", concurrent = true, elapsed = 65.1,
     results = [("CANCEL", "DONE", "Cancelled on request", nothing, nothing), ("CANCEL", "DONE", "Cancelled on request", nothing, nothing), ("DONE", "DONE", nothing, nothing, nothing)],
     result = "CANCEL", expected = false, summary = "3 TOTAL, 1 DONE, 2 CANCEL (unexpected) in 1:05.1",
     reason = "2/3 unexpected: 2x Cancelled on request",
     close = "Ran simulation (3 concurrent)", description = "Running simulation (3 concurrent)"),
    (family = :test, name = "fingerprint test", action = "Checking fingerprint", concurrent = true, elapsed = 192.0,
     results = [("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("FAIL", "PASS", "Fingerprint mismatch", nothing, nothing), ("FAIL", "PASS", "Fingerprint mismatch", nothing, nothing), ("ERROR", "PASS", "Calculated fingerprint not found", nothing, nothing)],
     result = "ERROR", expected = false, summary = "40 TOTAL, 37 PASS, 2 FAIL (unexpected), 1 ERROR (unexpected) in 3:12",
     reason = "3/40 unexpected: 2x Fingerprint mismatch, 1x Calculated fingerprint not found",
     close = "Checking fingerprint fingerprint test (40 concurrent)", description = "Checking fingerprint fingerprint test (40 concurrent)"),
    (family = :test, name = "smoke test", action = "Testing", concurrent = true, elapsed = 4.5,
     results = [("PASS", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing), ("FAIL", "FAIL", "Expected failure", nothing, nothing)],
     result = "PASS", expected = true, summary = "3 TOTAL, 2 PASS, 1 FAIL (expected) in 4.5",
     reason = nothing,
     close = "Tested smoke test (3 concurrent)", description = "Testing smoke test (3 concurrent)"),
    (family = :test, name = "fingerprint test", action = "Checking fingerprint", concurrent = true, elapsed = 1.5,
     results = [("FAIL", "PASS", "Fingerprint mismatch", nothing, 1.5)],
     result = "FAIL", expected = false, summary = "FAIL (unexpected) (Fingerprint mismatch) in 1.5",
     reason = "1/1 unexpected: 1x Fingerprint mismatch",
     close = "Checking fingerprint fingerprint test (1 concurrent)", description = "Checking fingerprint fingerprint test (1 concurrent)"),
    (family = :test, name = "smoke test", action = "Testing", concurrent = true, elapsed = 0.75,
     results = [("ERROR", "PASS", "Non-zero exit code: 1", "<!> Error: boom", 0.75)],
     result = "ERROR", expected = false, summary = "ERROR (unexpected) (Non-zero exit code: 1) <!> Error: boom in 0.75",
     reason = "1/1 unexpected: 1x Non-zero exit code: 1",
     close = "Tested smoke test (1 concurrent)", description = "Testing smoke test (1 concurrent)"),
    (family = :update, name = "fingerprint update", action = "Updating", concurrent = true, elapsed = 30.0,
     results = [("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("UPDATE", "KEEP", nothing, nothing, nothing), ("UPDATE", "KEEP", nothing, nothing, nothing), ("INSERT", "KEEP", nothing, nothing, nothing)],
     result = "UPDATE", expected = false, summary = "40 TOTAL, 37 KEEP, 1 INSERT (unexpected), 2 UPDATE (unexpected) in 30",
     reason = "3/40 unexpected: 2x UPDATE, 1x INSERT",
     close = "Updated fingerprint update (40 concurrent)", description = "Updating fingerprint update (40 concurrent)"),
    (family = :update, name = "fingerprint update", action = "Updating", concurrent = true, elapsed = 3661.0,
     results = [("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing), ("KEEP", "KEEP", nothing, nothing, nothing)],
     result = "KEEP", expected = true, summary = "4 KEEP in 1:01:01",
     reason = nothing,
     close = "Updated fingerprint update (4 concurrent)", description = "Updating fingerprint update (4 concurrent)"),
    (family = :run, name = "simulation", action = "Running", concurrent = true, elapsed = 1.0,
     results = [("DONE", "ERROR", nothing, nothing, nothing), ("ERROR", "ERROR", "Non-zero exit code: 1", nothing, nothing)],
     result = "DONE", expected = false, summary = "2 TOTAL, 1 DONE, 1 ERROR (expected) in 1",
     reason = "1/2 unexpected: 1x DONE",
     close = "Ran simulation (2 concurrent)", description = "Running simulation (2 concurrent)"),
    (family = :run, name = "simulation", action = "Running", concurrent = true, elapsed = nothing,
     results = [],
     result = "DONE", expected = true, summary = nothing,
     reason = nothing,
     close = "Ran simulation (0 concurrent)", description = "Running simulation (0 concurrent)"),
    (family = :test, name = "statistical test", action = "Checking", concurrent = true, elapsed = 12.0,
     results = [("FAIL", "PASS", "a", nothing, nothing), ("FAIL", "PASS", "a", nothing, nothing), ("FAIL", "PASS", "a", nothing, nothing), ("FAIL", "PASS", "b", nothing, nothing), ("FAIL", "PASS", "b", nothing, nothing), ("ERROR", "PASS", "c", nothing, nothing), ("ERROR", "PASS", "d", nothing, nothing), ("ERROR", "PASS", nothing, nothing, nothing), ("PASS", "PASS", nothing, nothing, nothing)],
     result = "ERROR", expected = false, summary = "9 TOTAL, 1 PASS, 5 FAIL (unexpected), 3 ERROR (unexpected) in 12",
     reason = "8/9 unexpected: 3x a, 2x b, 1x c, +2 more",
     close = "Checking statistical test (9 concurrent)", description = "Checking statistical test (9 concurrent)"),
    (family = :run, name = "simulation", action = "", concurrent = true, elapsed = 59.9996,
     results = [("DONE", "DONE", nothing, nothing, nothing), ("SKIP", "DONE", nothing, nothing, nothing)],
     result = "SKIP", expected = false, summary = "2 TOTAL, 1 DONE, 1 SKIP (unexpected) in 1:00",
     reason = "1/2 unexpected: 1x SKIP",
     close = "simulation (2 concurrent)", description = "simulation (2 concurrent)"),
]

function _make_task_result_parity_group(case)
    codes = _TASK_RESULT_FAMILIES[case.family]
    tasks = _TaskResultProbeTask[_TaskResultProbeTask(codes) for _ in case.results]
    group = TaskGroup(tasks; name = case.name, action = case.action,
                      jobs = case.concurrent ? 4 : 1, codes = codes)
    results = [_TaskResultProbeResult(tasks[i], r[1], r[2], r[3], r[4],
                                       r[5] === nothing ? nothing : Float64(r[5]))
               for (i, r) in enumerate(case.results)]
    group, TaskGroupResult(results; codes = codes, elapsed_wall_time = case.elapsed, group = group)
end

const _TASK_RESULT_TIMES = [(0.12, "0.12"), (45.0, "45"), (65.1, "1:05.1"), (3661.0, "1:01:01"),
                            (0.0004, "0"), (59.9996, "1:00"), (192.0, "3:12"), (0.5, "0.5"),
                            (7200.25, "2:00:00.25")]

_make_task_probe_result(codes, result, expected; reason = nothing, error = nothing, elapsed = nothing) =
    _TaskResultProbeResult(_TaskResultProbeTask(codes), result, expected, reason, error, elapsed)

function test_task_result()
    @testset "task result" begin
        @testset "a group says what opp_repl says: $(case.close)" for case in _OPP_REPL_GROUP_CASES
            group, result = _make_task_result_parity_group(case)
            @test result.result == case.result
            @test is_expected(result) == case.expected
            case.summary === nothing || @test format_task_group_summary(result) == case.summary
            @test format_task_group_reason(result) == case.reason
            @test format_task_group_close_description(group) == case.close
            @test format_task_group_description(group) == case.description
            length(case.results) > 1 && @test startswith(repr(result), case.close * ": " * case.summary)
        end
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
