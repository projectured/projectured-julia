# Tasks

> **Kind:** design · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md)

The task slice of `ProjecturedPlatform` holds what every kind of work shares
when it runs as a task, in the words of `opp_repl` (`common/task.py`): a piece of
work that runs and ends with a result, the codes a result takes, the words in
which a result is reported, the execution of a process, and a group of tasks
that runs a number at a time. It also holds what shows them: the documents of a
task and of a group, the feed that carries what an execution says into them,
the pane of a group, the Tasks pane, and the verbs that read and act on a group.
Nothing in the slice knows what the work is. A domain adds its kinds of task,
such as the runs and the tests of a simulation, or the builds of a project.

## A task and its result

`AbstractTask` is the supertype of every kind of task. A kind answers
`get_result_codes(task)`, the family of codes that its results take, and
`format_task_parameters(task)`, the task in one line.

A kind also says what it adds to the views of tasks, with plain answers and no
document of its own:

- `get_task_columns(task)` names its columns, each the word of its header and
  its share of the width, such as `"directory" => 4`;
- `format_task_column(task, column)` gives the text of one;
- `format_task_details(task, result)` gives its facts, one a line, such as the
  command, the exit code and the error line, from what the task ended with;
- `get_task_actions(task)` gives its buttons, each a label and a function that a
  press calls with the editor that evaluates the press and the task.

The defaults answer nothing, so a task of a kind that adds nothing shows what
every task has. A run of a simulation, for example, can add its directory, its
configuration and the number of its run, the command, the exit code and the
error line of its process, and a button that opens the run in a window of its
own.

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
start of a task says while it runs, and what it ended with: its status, the
identifier of its process, its times, a `progress` fraction and a `position`
text, what the process printed on stdout and on stderr, its processor load and
resident memory, and its result. It is a live state, `@document [M, C]`: the bare
name is the native layout, which the readers of the process write only through
`update_task_execution!`. That function holds the lock of the `TaskRuntime` of the
execution, because the readers and the editor task can run on two threads. The
runtime also holds the process, the reader task, the count of the writes and
the last sample of the processor time; no view shows it.

The editor task shows an execution through its shadow in the cell layout:
`make_task_execution_shadow(execution)` makes it, and `sync_document!(shadow,
execution)` brings it up to date under the lock. A sync writes a field only when
its value changed, so a view of a field that did not change is not drawn again.
It copies a stream only when lines came, because a `TaskOutput` changes in place,
and a shadow that held the same object would never see a new line.

Each stream is a `TaskOutput`: the first 100 lines, the last 1000, and the count
of the lines between, so a process that prints without end cannot fill the
memory. `read_line(execution, line)` sees each line of stdout under the lock, and
is where a kind of task reads its progress and its position: a simulation writes
`event #4200 t=1.5`. When the process has ended and both streams are read,
`finish(process, cancelled, elapsed)` makes the result and calls
`finish_task_execution!`, which writes the result, the status of its code
(`get_task_status`) and the time of the end. A task that ends with no process,
such as one that is skipped, calls `finish_task_execution!` directly.

A `Cmd` starts in a process group of its own. `stop_task_execution!` sends
`SIGINT` to the group, so the programs that the process started stop with it —
the compilers of `make`, for example — and a program that catches the signal
can still finish its work. The status says `:cancelling` until the process
ends. A Ctrl+C at the REPL does not reach the group.
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

**A group is a kind of task.** A task of a group can be a group, as a
`MultipleTasks` of `opp_repl` holds others: a sequential group of phases, each a
concurrent group of steps. `start_task(group)` starts an inner group and answers
an execution with no process, whose `progress` and `position` (`12/40`) follow
the inner group and whose result is the `TaskGroupResult` of the inner group.
`stop_task_group!` stops the inner groups too. The counts, the progress, the
summary and the result of a group count the tasks that are no groups, at every
depth, so a build of five phases says how many of its 1700 compiles ended, and
the row of each phase says the same of its own.

`on_start`, a field of the group, is called at each start of one of its tasks,
whoever started the group. The document of a group sets it, so the tasks of an
inner group report to their documents as the tasks of the outer group do.

`TaskGroupResult` is `MultipleTaskResults` of `opp_repl`, and a `TaskResult`: the count of each code,
expected and unexpected, and the worst case. `format_task_group_summary` and
`format_task_group_reason` write it as `opp_repl` does:
`40 TOTAL, 37 PASS, 2 FAIL (unexpected), 1 ERROR (unexpected) in 3:12` and
`3/40 unexpected: 2x Fingerprint mismatch, 1x Calculated fingerprint not found`.
`compute_task_group_summary` answers a `TaskGroupSummary`, what a group looks
like at one moment for a reader of the screen: the counts, the progress, the
time that went and an estimate of the time left, the rate and the slowest task.

A start that throws ends its task as `ERROR`, a `TaskStartFailure` with the
exception in its reason, and the group goes on with its other tasks, so one bad
task does not leave a group that never ends.

A group can have a `preparation`: one task, such as the build of a project,
that runs at each start of the group before its tasks, as a batch of runs of
`opp_repl` builds first. When the preparation ends with a result that is not
expected, no task starts, and each ends as `CANCEL` with a `TaskNotStarted`
result whose reason names the preparation, at every depth. The preparation is
not one of the tasks, so the counts, the codes, the result and the places of a
group are those of its tasks; a stop of the group stops it too. The document of
the group holds a document of the preparation (`get_task_group_preparation`),
the card of the pane says in one line how it went
(`describe_task_group_preparation`), and its button Show puts the preparation
in the detail, the pane of a preparation that is a group.

## The steps of a build

`BuildStepTask` is a step of a build, as `common/compile.py` of `opp_repl` has
them. `BuildCommandTask` runs one command in a folder, such as the compile of
one file or a link, with its input and its output files and an optional
dependency file (`.d`) that names the inputs of an output once the command wrote
it (`read_dependency_file`). When another engine runs the same command in
another folder and writes the same dependency file, `dependency_root` names that
folder, and the step reads the paths relative to either folder. After a command
ends `DONE`, its `postprocess`, such as `ranlib`, runs on its first output, and
then the step touches its outputs, so a command that leaves an output as it was
is up to date the next time. `BuildCopyTask` copies one file, and accepts
a hard link or a target that is not older than its source. `BuildRemoveTask`
removes a file or a folder, as a clean does. `is_build_step_up_to_date` says
whether every output is newer than every input; a step that is up to date
answers `SKIP` with "Up-to-date", and `SKIP` is its expected result. A failed
command ends `ERROR` with what it printed on stderr as its error message. A
domain computes the command lines and puts the steps in groups: a build of a
project is a sequential group of phases, each a concurrent group of steps.

## The documents and the feed

`TaskDocument` is one task on the screen: the task, the native layout of its
current execution in `running`, and the shadow of every execution of the task in
`executions`, the newest last. It holds nothing that a kind of task knows: a view
asks the task for its columns, its facts and its buttons.
`start_task!(document; options...)` starts the task through `start_task` of its
kind and answers at once; `stop_task!` and `wait_task_document` act on the
current execution. A view reads the shadow of the current execution
(`get_current_task_execution`), and `get_task_document_status`,
`get_task_document_result` and `collect_task_document_lines` read its status, its
result and its lines.

A start again, or a run again of a group, adds an execution and replaces none
(`add_task_execution!`). The earlier executions keep their own results
(`get_earlier_task_executions`). A task that waits to start again has no current
execution, so its status is `:pending` and all its executions are earlier then. The row of a task in the pane shows the current execution; the
detail lists the earlier ones, each with its verdict and its start time
(`describe_task_execution`), and `describe_task` says how many ran. An execution
keeps its output within the bounds of `TaskOutput`, so each run again of a group
adds at most those lines for each task that ran again, until the group is
closed.

No reader of a process writes a cell. A `TaskFeedStore` holds each execution
that runs with its shadow and its owner, the document that shows it, and
`drain_task_feed!` syncs each shadow whose execution changed, on the task that
reads the documents. After a sync it calls `record_task_execution_sync!` with the
owner: a group counts the change of the state there, and a document adds a
shadow that the drain made. A window gives its editor a `TaskFeed`, which drains
at most once in its interval and asks for a frame only while an execution runs.
A caller with no window drains the store itself: `wait_task_document` and
`wait_task_group_document` do.

`TaskGroupDocument` is a group on the screen: the `TaskGroup`, one
`TaskDocument` for each task, a tally of the states that each sync keeps, the
summary, and an identifier `T1`, `T2`, … that never changes. Each task that is
a group has a `TaskGroupDocument` of its own, `T1.1`, `T1.2`, …
(`find_task_group_document`); only the outer group has a row in the Tasks pane.
`start_task_group_document!`, `rerun_task_group_document!` and
`stop_task_group_document!` act on the group, and its status is `:pending`,
`:running`, `:stopping` or `:finished`. The status reads the tally, not the
documents, so a group of 18,500 tasks costs the same at each change as a group
of five.

`TaskGroupList` is the groups of the session, newest first, that the Tasks pane
shows. A group adds itself when it starts, and stays until a person closes its
row. `set_task_group_opener!` says what Show does; a window sets it, and it
captures no editor (PAR-NO-EDITOR-IN-DOCUMENT).

## The views

`TaskGroupDocumentToWidgetPane` draws a group as its pane: a card with the
counts of each code, a bar of the progress, the time, the reason of what was not
expected and the actions on the whole group; a table with one row for each task;
and the detail of the task that a person picked, with its facts, its buttons
and its two streams. The detail of a task that is a group is the pane of that
group: its card, with no actions of its own, its table and its detail. The columns of the table are the pick and the state, the
columns of the kind of the first task, and then the progress or the position,
the elapsed time, the process, the processor, the memory and the result. A row
reads the cells of its own document, so a task that reports draws only its own
row again, and the rows are a lazy list, so a group of 22,731 tasks costs what a
group of twenty costs.

`make_task_group_tab_title` is the title of the tab of a group, and the
`make_pane_tab_title` of a group: an icon and badges that say how far the group
is and the worst that it found. `TaskGroupListToWidgetPane` draws the Tasks
pane, one row for each group of the session, with Show, Stop, Run unexpected
again and Close.

The panes draw with `TaskTheme`. `build_task_graphics_entry` makes the rows of
the natural renderer for both panes, each with a widget renderer of its own so
that a press reaches its button, and the slice registers them, so any
`NaturalToGraphics` draws a tab that holds a group or the list of groups.

## The verbs

A person at the REPL and a model through `execute_julia_code` read and act on
the groups of the session with the verbs of the slice: `list_task_groups`,
`find_task_group`, `describe_task_group`, `describe_task`, `get_task_output`,
`stop_tasks!`, `stop_task!`, `rerun_tasks!`, `wait_for_task_group!` and
`close_task_group!`. Each but `wait_for_task_group!` takes the keyword
`editor = get_evaluation_editor()`, so the code of a model names no editor;
`wait_for_task_group!` takes `editor` first. Each does its document work on the
task of the editor through `run_on_editor_task!`, so a person at the REPL, who
passes `editor`, calls it while the window runs. `describe_task` writes the facts that the kind
of the task gives (`format_task_details`).

**A client of `execute_julia_code` never passes `wait = true`.** The call runs
in a frame of the window, so a verb that waits holds the window until the group
ends.

`make_task_api()` is what a window declares that a model may call of the slice,
as a `TaskModule => names` pair, beside the verbs of its domain that start the
groups.

## Add a kind of task

A domain adds a kind of task in five steps. The example is a build that runs
`make` in a directory.

1. Declare the kind, a subtype of `AbstractTask`, and its result, a subtype of
   `TaskResult` with the five fields of a result.
2. Answer `get_result_codes` and `format_task_parameters` for the kind.
3. Add a method of `start_task`. It makes a `TaskExecution`, starts the process
   with `start_process_task!`, and in `finish` makes the result and calls
   `finish_task_execution!` with `on_finish`.
4. If the views must show more than every task has, answer the functions of the
   views: `get_task_columns`, `format_task_column`, `format_task_details` and
   `get_task_actions`.
5. Give a model the verbs: the verbs of the domain that start a group, and
   `make_task_api()` for the rest.

```julia
struct BuildTask <: AbstractTask
    directory::String
end

struct BuildResult <: TaskResult
    task::BuildTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

TaskModule.get_result_codes(::BuildTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::BuildTask) = task.directory
TaskModule.get_task_columns(::BuildTask) = ["directory" => 4]
TaskModule.format_task_column(task::BuildTask, column::AbstractString) =
    column == "directory" ? task.directory : ""

function TaskModule.start_task(task::BuildTask; on_finish = nothing)
    execution = TaskExecution(task)
    finish = function (process, cancelled, elapsed)
        code = cancelled ? "CANCEL" : process.exitcode == 0 ? "DONE" : "ERROR"
        finish_task_execution!(execution, BuildResult(task, code, "DONE", nothing, elapsed);
                               finish = on_finish)
    end
    start_process_task!(execution, Cmd(`make`; dir = task.directory); finish)
end

group = wrap_task_group_document(TaskGroup(tasks; name = "builds", action = "Building", jobs = 4))
start_task_group_document!(group)
open_pane!(group; title = "Builds")
```

The group then reports into its pane, its tab says how far it is, the Tasks pane
lists it, and when it ends, the card of its pane starts with `Built builds` and
the summary line of `opp_repl`.
