# Tasks

> **Kind:** design · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md)

The task slice of `ProjecturedPlatform` holds what every kind of work shares
when it runs as a task, in the words of `opp_repl` (`common/task.py`): a piece of
work that runs and ends with a result, the codes a result takes, and the words in
which a result is reported. Nothing in the slice knows what the work is. A domain
adds its kinds of task, such as the runs and the tests of a simulation.

## A task and its result

`AbstractTask` is the supertype of every kind of task. A kind answers
`get_result_codes(task)`, the family of codes that its results take, and
`format_task_parameters(task)`, the task in one line.

`TaskResult` is the supertype of what a task ended with. Each kind of result
holds the fields `task`, `result`, `expected_result`, `reason` and
`elapsed_wall_time`, named as `opp_repl` names them. A result is expected when
`result == expected_result`.

`ResultCodes` is a family of codes in the order of `opp_repl`, the colour role of
each code and the code that a result takes when nothing says otherwise. Three
families exist:

| Family | Codes | Expected |
| --- | --- | --- |
| `RUN_RESULT_CODES` | DONE, SKIP, CANCEL, ERROR | DONE |
| `TEST_RESULT_CODES` | PASS, SKIP, CANCEL, FAIL, ERROR | PASS |
| `UPDATE_RESULT_CODES` | KEEP, SKIP, CANCEL, INSERT, UPDATE, ERROR | KEEP |

A role is what `opp_repl` says with a terminal colour: `:success` for green,
`:info` for cyan, `:warning` for yellow and `:error` for red. Only ERROR is red.

## The words

`format_task_result(result)` writes one result as `opp_repl` writes it:
`FAIL (unexpected) (Fingerprint mismatch) in 1.5`. `format_elapsed_time(seconds)`
writes a time span as `format_timedelta` of `opp_repl` does: `0.12`, `1:05.1`,
`1:01:01`. `format_past_tense(action)` turns the action of a group into the past
tense when the group ends: `Running` becomes `Ran`.
