# ══════════════════════════════════════════════════════════════════════════════
# What every kind of task shares: the codes its results take, whether a result is
# the one that was expected, and the words a result is reported in. The rules and
# the words are those of `opp_repl` (`opp_repl/common/task.py`), so a person who
# reads one tool reads the other.
# ══════════════════════════════════════════════════════════════════════════════

"""
    AbstractTask

One piece of work that a [`TaskGroup`](@ref) runs: a run of a program, a test,
an update of a store, a step of a build. `opp_repl` calls it `Task`, which is a
type of `Base` here. A domain adds its kinds of task; this module knows none of
them.

A kind of task answers [`get_result_codes`](@ref), [`start_task`](@ref) and
[`format_task_parameters`](@ref).
"""
abstract type AbstractTask end

"""
    TaskResult

What one task ended with. Each kind of result holds the fields `task`, `result`,
`expected_result`, `reason` and `elapsed_wall_time`, named as `opp_repl` names
them. `result` and `expected_result` are codes of the [`ResultCodes`](@ref) of
the task, spelled as `opp_repl` spells them: `"DONE"`, `"PASS"`, `"KEEP"`.
"""
abstract type TaskResult end

"""
    ResultCodes(codes, roles, expected)

The codes that a family of results takes, in the order of `opp_repl`, the colour
role of each, and the code that a result is expected to take when nothing says
otherwise. The order matters: the worst case of a group reads it
([`TaskGroupResult`](@ref)).

A role says what `opp_repl` says with a terminal colour: `:success` for its
green, `:info` for its cyan, `:warning` for its yellow and `:error` for its red.
"""
struct ResultCodes
    codes::Vector{String}
    roles::Vector{Symbol}
    expected::String
end

"""The codes of a task that runs something: `DONE`, `SKIP`, `CANCEL`, `ERROR`."""
const RUN_RESULT_CODES = ResultCodes(["DONE", "SKIP", "CANCEL", "ERROR"],
                                     [:success, :info, :info, :error], "DONE")

"""The codes of a test: `PASS`, `SKIP`, `CANCEL`, `FAIL`, `ERROR`."""
const TEST_RESULT_CODES = ResultCodes(["PASS", "SKIP", "CANCEL", "FAIL", "ERROR"],
                                      [:success, :info, :info, :warning, :error], "PASS")

"""The codes of an update of a store: `KEEP`, `SKIP`, `CANCEL`, `INSERT`,
`UPDATE`, `ERROR`."""
const UPDATE_RESULT_CODES = ResultCodes(["KEEP", "SKIP", "CANCEL", "INSERT", "UPDATE", "ERROR"],
                                        [:success, :info, :info, :warning, :warning, :error],
                                        "KEEP")

"""
    get_result_codes(task) -> ResultCodes
    get_result_codes(result) -> ResultCodes

The codes that the results of `task` take. A result answers the codes of its
task.
"""
function get_result_codes end
get_result_codes(r::TaskResult) = get_result_codes(r.task)

"""
    get_result_role(codes, code) -> Symbol

The colour role of `code`: `:success`, `:info`, `:warning` or `:error`. A code
that is not one of `codes` is an error.
"""
function get_result_role(codes::ResultCodes, code::AbstractString)
    index = findfirst(==(code), codes.codes)
    index === nothing && error("$(repr(code)) is not one of the codes " * join(codes.codes, ", "))
    codes.roles[index]
end

"""Whether `result` ended with the code that was expected of it."""
is_expected(r::TaskResult) = r.result == r.expected_result

"""
    get_error_message(result) -> String

What a result that is `ERROR` says about the error, such as the error line that
a kind of task finds in the output of its process. `"<No error message>"` when it
says nothing, as `opp_repl` writes it.
"""
get_error_message(::TaskResult) = "<No error message>"

"""
    format_task_parameters(task) -> String

The task in one line, as `opp_repl` writes it after the progress of a task. A
kind of task with no parameters answers `""`.
"""
format_task_parameters(::AbstractTask) = ""

"""
    get_task_columns(task) -> Vector{Pair{String,Int}}

The columns that a kind of task adds to a table of tasks, beside the columns
that every task has: each is the word of its header and the share of the width
that it takes, as a weight against the other columns. A kind with nothing to add
answers none.
"""
get_task_columns(::AbstractTask) = Pair{String,Int}[]

"""
    format_task_column(task, column) -> String

The text of `task` in `column`, one of the names that
[`get_task_columns`](@ref) answers for it. `""` for a column that the kind does
not know.
"""
format_task_column(::AbstractTask, ::AbstractString) = ""

"""
    get_task_actions(task) -> Vector{Pair{String,Function}}

The buttons that a kind of task adds to the detail of a task, beside Stop and
Run again: each is a label and the function that a press calls with the editor
that evaluates the press and the task, `action(editor, task)`. A kind with
nothing to add answers none.
"""
get_task_actions(::AbstractTask) = Pair{String,Function}[]

"""
    format_task_details(task, result) -> Vector{String}

What a kind of task says about `task` beside its state, one fact a line, such as
`command: …`, the exit code of its process, and the line that says why it
failed. `result` is what the task ended with, or `nothing` while it has not
ended. A kind with nothing to say answers none.
"""
format_task_details(::AbstractTask, result) = String[]

# ── Words ────────────────────────────────────────────────────────────────────

"""
    format_elapsed_time(seconds; precision = 3) -> String

A time span as `format_timedelta` of `opp_repl` writes it: `H:MM:SS`, `M:SS` or
`S`, with no leading zero unit, and the fraction rounded to `precision` places
with its trailing zeros removed — `0.12`, `45`, `1:05.1`, `1:01:01`.
"""
function format_elapsed_time(seconds::Real; precision::Integer = 3)
    0 <= precision <= 6 || error("precision must be between 0 and 6")
    # Whole microseconds first, as a `timedelta` holds them, so that no float
    # rounding reaches the digits.
    total = round(Int, seconds * 1_000_000)
    sign = total < 0 ? "-" : ""
    total = abs(total)
    if precision < 6
        factor = 10^(6 - precision)
        total = (total + factor ÷ 2) ÷ factor * factor
    end
    whole, micro = divrem(total, 1_000_000)
    hours, rest = divrem(whole, 3600)
    minutes, secs = divrem(rest, 60)
    base = hours > 0 ? string(hours, ":", lpad(minutes, 2, '0'), ":", lpad(secs, 2, '0')) :
           minutes > 0 ? string(minutes, ":", lpad(secs, 2, '0')) :
           string(secs)
    fraction = ""
    if precision > 0 && micro > 0
        digits = rstrip(lpad(string(micro), 6, '0')[1:precision], '0')
        isempty(digits) || (fraction = "." * digits)
    end
    sign * base * fraction
end

"""
    PAST_TENSE

The past tense of the action of a group, as `opp_repl` writes it when the group
ends: `"Running"` becomes `"Ran"`. An action that is not here stays as it is.
"""
const PAST_TENSE = Dict{String,String}(
    "Building" => "Built", "Cleaning" => "Cleaned", "Compiling" => "Compiled",
    "Generating" => "Generated", "Linking" => "Linked", "Copying" => "Copied",
    "Running" => "Ran", "Testing" => "Tested", "Updating" => "Updated",
    "Removing" => "Removed", "Installing" => "Installed", "Capturing" => "Captured")

"""The past tense of `action`, or `action` itself when [`PAST_TENSE`](@ref) has
no entry for it."""
format_past_tense(action::AbstractString) = get(PAST_TENSE, String(action), String(action))

"""
    format_task_result(result) -> String

One result in the words of `opp_repl` (`TaskResult.get_description`): the code;
`(unexpected)` when it is not the expected one, or `(expected)` when it is and its
role is not `:success`; the reason; the error message of an `ERROR`; and the
time it took — `FAIL (unexpected) (Fingerprint mismatch) in 1.5`.
"""
function format_task_result(r::TaskResult)
    role = get_result_role(get_result_codes(r), r.result)
    text = r.result
    expected = is_expected(r)
    expected || (text *= " (unexpected)")
    expected && role !== :success && (text *= " (expected)")
    _has_text(r.reason) && (text *= " (" * r.reason * ")")
    r.result == "ERROR" && (text *= " " * get_error_message(r))
    _has_time(r.elapsed_wall_time) && (text *= " in " * format_elapsed_time(r.elapsed_wall_time))
    text
end

# What `opp_repl` tests with the truth of a value: a reason that is `None` or
# empty says nothing, and a time that is `None` or zero is not written.
_has_text(value) = value !== nothing && !isempty(value)
_has_time(value) = value !== nothing && value != 0
