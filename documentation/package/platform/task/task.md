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

## The execution of a process

A task that runs a program starts it with `start_process_task!(execution,
command; read_line, finish)` and answers at once. `TaskExecution` is what one
start of a task says while it runs, and what it ended with: its status, its
process and identifier, its times, a `progress` fraction and a `position` text,
what the process printed on stdout and on stderr, its processor load and resident
memory, and its result. The readers of the process write it only through
`update_task_execution!`, which holds its lock, because the readers and a reader
of the screen can run on two threads; a reader takes a copy with
`get_task_execution_snapshot`.

Each stream is a `TaskOutput`: the first 100 lines, the last 1000, and the count
of the lines between, so a process that prints without end cannot fill the
memory. `read_line(execution, line)` sees each line of stdout under the lock, and
is where a kind of task reads its progress and its position: a simulation writes
`event #4200 t=1.5`. When the process has ended and both streams are read,
`finish(process, cancelled, elapsed)` makes the result and calls
`finish_task_execution!`, which writes the result, the status of its code
(`get_task_status`) and the time of the end. A task that ends with no process,
such as one that is skipped, calls `finish_task_execution!` directly.

`stop_task_execution!` sends `SIGINT`, so a program that catches it can still
finish its work, and the status says `:cancelling` until the process ends.
`sample_task_usage!` reads the processor time and the resident memory from
`/proc`.

## A group of tasks

`TaskGroup` is `MultipleTasks` of `opp_repl`: tasks that run at most `jobs` at a
time. `start_task_group!` starts them on a task of the group and answers at once;
each task starts through `start_task(task; on_finish)`, the function that a kind
of task adds a method to, and its `TaskExecution` stays in `runs` for the whole
life of the group. `rerun_task_group!(group, which)` runs again the tasks that
`which` names — `:all`, `:unfinished`, `:unexpected`, `:failed` or their
positions — in place, and keeps every other execution. `stop_task_group!`
starts no more tasks and stops the ones that run. `finish`, when it is set, is
called once when the last task of a start ends: an update writes its store
there.

`TaskGroupResult` is `MultipleTaskResults` of `opp_repl`: the count of each code,
expected and unexpected, and the worst case. `format_task_group_summary` and
`format_task_group_reason` write it as `opp_repl` does:
`40 TOTAL, 37 PASS, 2 FAIL (unexpected), 1 ERROR (unexpected) in 3:12` and
`3/40 unexpected: 2x Fingerprint mismatch, 1x Calculated fingerprint not found`.
`compute_task_group_summary` answers a `TaskGroupSummary`, what a group looks
like at one moment for a reader of the screen: the counts, the progress, the
time that went and an estimate of the time left, the rate and the slowest task.

