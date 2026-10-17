# Tasks

> **Kind:** design · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md), [systemprocess.md](../systemprocess/systemprocess.md), [tree.md](../tree/tree.md)

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

A kind also says what it adds to the views of tasks. All but the last answer
are plain values:

- `get_task_columns(task)` names its columns, each the word of its header and
  its share of the width, such as `"directory" => 4`;
- `format_task_column(task, column)` gives the text of one;
- `format_task_details(task, result)` gives its facts, one a line, such as the
  command, the exit code and the error line, from what the task ended with;
- `get_task_actions(task)` gives its buttons, each a label and a function that a
  press calls with the editor that evaluates the press and the task;
- `get_task_links(task)` gives its links, each `(label, text, document,
  reference)`: the name of a fact, the text of the link, and the document and the
  path from it of the part that the link opens. The task page and the execution
  page draw them among the facts, and the navigator around the page opens the
  part where its content holds the document;
- `find_task_output_mark(task, stream, line)` gives the mark of one line that the
  task printed: `:error`, `:warning`, `:notice`, `:progress` or `nothing`. It runs
  for each line under the lock of the execution, so it answers from the line
  alone;
- `get_task_output_folder(task)` gives the folder of the files of its streams, or
  `nothing` for the folder of the process;
- `get_task_result_document(task, result)` gives a document that shows the
  result in more than lines of text, such as the table of the scalars that a
  statistical test compared. The task document holds it in `result_document`,
  made when a view first reads it after the result came, and the same document
  until the result changes. The detail of the task shows it below its facts, in
  the card of an embedded document. It draws by the method of
  `make_graphics_projection` for its type, as it draws in any document, so the
  renderer of the views reads that seam too. A path reaches it,
  `tasks[i].result_document`, and the pane maps that path to the card and back,
  as a page maps an embedded file: a person edits the document where it shows.

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

The end of a kind, the `finish` of `start_process_task!`, runs on the task that
reads the process, which nobody waits for. When it throws before it wrote a
result, `start_process_task!` logs the error and ends the execution with a
`TaskFinishFailure` (`ERROR`, the exception in its reason), which goes to the
`on_finish` that the kind passes. Without that, the task would never end, and a
group that waits for it would wait forever.

Each stream is a `TaskOutput`: the first 100 lines, the last 1000, and the count
of the lines between, so a process that prints without end cannot fill the
memory. It also counts the lines of each mark that the kind gives
(`mark_counts`) and keeps the number of the first line of each
(`first_mark_lines`).

**Every line is in a file.** The reader of a stream writes each line to the file
of the stream, `path` of its `TaskOutput`: `<n>.stdout` and `<n>.stderr`, the
same `n` for both streams of one execution. The file is flushed at most five
times a second while lines come, and once at the end, so a view that reads it
while the process runs is at most that far behind. The folder is the one of the
kind (`get_task_output_folder`), or the folder of the process,
`get_session_output_folder!()`: `projectured/task-output/<process>` under the state
folder of the user (`XDG_STATE_HOME`, or `~/.local/state`), never the temporary
folder, which can be a disk in memory. The process removes its folder when it
ends, and the first use removes the folders of processes that no longer run. A
close of a group (`remove_task_group!`) removes the files of its tasks at every
depth (`remove_task_output_files!`); a folder that can not be made leaves the
stream with its bounded lines alone.

`read_line(execution, line)` sees each line of stdout under the lock, and
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
A sampler of each process that runs calls `sample_task_usage!` four times a
second, on a task of the default pool, off the loop. It reads the processor time
and the resident memory of the process with `read_system_process_usage`, which
the slice [systemprocess.md](../systemprocess/systemprocess.md) holds, and so
reads `/proc` in one place, and it writes the execution, which notes it as
changed in the store of the feed. Both the load of a task and the load of a
process there divide the ticks by `get_clock_ticks_per_second`.

## A group of tasks

`TaskGroup` is `MultipleTasks` of `opp_repl`: tasks that run at most `jobs` at a
time. `start_task_group!` starts them on a task of the group and answers at once;
each task starts through `start_task(task; on_finish)`, the function that a kind
of task adds a method to, and its `TaskExecution` stays in `runs` for the whole
life of the group. `rerun_task_group!(group, which)` runs again the tasks that
`which` names — `:all`, `:unfinished`, `:unexpected`, `:failed` or their
positions — in place, and keeps every other execution. `stop_task_group!`
starts no more tasks and stops the ones that run. `runtime.finish`, when it is
set, is called once when the last task of a start ends: an update writes its
store there.

**A group is a live state**, `@document [M, C] struct TaskGroup <: AbstractTask`.
Its native layout holds the tasks, the names, the codes, the times, the `runs`,
the `tally` that its scheduler keeps, and the `summary` and `counts` of the last
sync. A `TaskGroupRuntime` holds what no view shows: the lock of the tally, the
scheduler, `finish`, `on_start`, `on_preparation` and `preparation_run`. The
`TaskGroupTally` counts the tasks of the group that are no groups: the finished
ones, the places that run, the counts of each code, the unexpected details by
place, the durations and the slowest. The construction and each start build it
once from the executions; the scheduler adds each start and each end. So
`compute_task_group_summary` costs the codes, the inner groups and the running
tasks, and not a walk of every task. `make_task_group_shadow` makes the shadow
in the cell layout, which holds no `runs`, `tally` or `runtime`, and
`sync_document!(shadow, group)` computes the summary and writes the fields that
changed; the counts change only when a task starts or ends.

**A group is a kind of task.** A task of a group can be a group, as a
`MultipleTasks` of `opp_repl` holds others: a sequential group of phases, each a
concurrent group of steps. `start_task(group)` starts an inner group and answers
an execution with no process, whose `progress` and `position` (`12/40`) follow
the inner group and whose result is the `TaskGroupResult` of the inner group.
`stop_task_group!` stops the inner groups too. The counts, the progress, the
summary and the result of a group count the tasks that are no groups, at every
depth, so a build of five phases says how many of its 1700 compiles ended, and
the row of each phase says the same of its own.

`runtime.on_start` is called at each start of one of the tasks of the group,
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
`executions`, the newest last, a `CellVector`, so a selection goes into the page
of an execution. It holds nothing that a kind of task knows: a view asks the task
for its columns, its facts and its buttons. `group` holds, in a `Ref`, the group
document of the task and its place in it, which `wrap_task_group_document` sets
(`find_task_document_group`); a walk and a copy of the documents do not go round
through it. A task is called by `format_task_parameters` of its task, a group by
its title, and an execution by the time it started.
`start_task!(document; options...)` starts the task through `start_task` of its
kind and answers at once; `stop_task!` and `wait_task_document` act on the
current execution. A view reads the shadow of the current execution
(`get_current_task_execution`), and `get_task_document_status`,
`get_task_document_result` and `collect_task_document_lines` read its status, its
result and its lines.

`process_tree` is a computed field of `TaskDocument`, as `result_document` is. It is the `SystemProcessTree` of the process of the current execution, made when a view first reads it, while the execution has a process and no result; after the result it is `nothing`. A tree that no view read is never made, so a task that nobody looked at costs no read of `/proc`. `drain_task_feed!` takes the step of the tree for each execution that changed, when a view read its tree; a `TaskDocument` and the slot of a group of tasks both answer the step. The sampler writes the execution of a process that runs four times a second, so the tree of a running task takes its step at each drain, and the feed of the tasks already wakes the window then; the tree needs no wake of its own. The read of the tree runs off the loop, as for any tree. So a build or a simulation run shows its compilers or its workers with no code in its domain.

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

`TaskGroupDocument` is a group on the screen: the native `TaskGroup`, its
shadow, one `TaskDocument` for each task, and an identifier `T1`, `T2`, … that
never changes. A roster reads the group and its tasks by facets. A task has the
facets `name`, `status`, `result`, `expected` and `reason`; a group has `kind`,
the name of its `TaskGroup`. The `:tasks` source of the roster slice lists the
tasks of the open groups of the session, each with its group as `within`
([roster.md](../roster/roster.md)). The slot of each task syncs the shadow of the group after the
task (`get_task_group_document_summary`, `get_task_group_document_counts`). Each task that is
a group has a `TaskGroupDocument` of its own, `T1.1`, `T1.2`, …, which its
`TaskDocument` holds in the field `inner_group`
(`find_task_group_document`). So an inner group has a path under its outer group,
`tasks[i].inner_group`. Only the outer group has a row in the Tasks pane.
`start_task_group_document!`, `rerun_task_group_document!` and
`stop_task_group_document!` act on the group, and its status is `:pending`,
`:running`, `:stopping` or `:finished`. A start and a rerun take the keyword
`editor`, which defaults to the editor of the evaluation. The group joins the list
of that editor. A caller that runs at once, such as a verb with an editor of its
own, passes it. A start also takes `end_operation`, an operation that the editor
evaluates when the group ends, such as a new read of what a build changes. A task
of its own waits for the group and posts it, so no document holds the editor. The status reads the counts of the
shadow, not the documents, so a group of 18,500 tasks costs the same at each
change as a group of five.

`TaskGroupList` is the groups of the session of an editor, in the order of their
starts, which the Tasks pane shows newest first. It is a session document of the
editor (`get_session_task_group_list(; editor = find_evaluation_editor())`), and
no module constant holds it. The first call with an editor takes the list that a
tab of its window shows, or that the content of a tab holds a few documents down,
such as the content of a navigator, because a window can make its Tasks tab before
its editor exists; else it makes a new list. The search enters no collection, so
it reads no lazy part of a content. A group adds itself at the end of the
list of the editor of the evaluation when it starts. A group that starts outside
every editor, such as from a script, joins no list.

`TaskGroupList` has the insertion alias "tasks", and its insertion gives the list of the session (`make_insertion_document`). It is a kind of the explorer (`is_explorer_entry_type`). `pred_arguments` writes no field, and a loaded list is the list of the session of the editor that loads it, so a window file and the file of the explorer keep that a tab or an entry shows the list, and no group.

A group keeps its place, so a path `groups[k]` names the same group for the whole
session. A close of its row puts a `ClosedTaskGroup` in the place: the
identifier, the title and the line that sums the group up. The tasks and their
executions go with the group, so their memory goes. The Tasks pane and the
records of the tasks hide a closed group, `collect_task_group_documents` gives the
open groups, and the page of a closed group says that it closed. A group that
runs again goes back into its place.

## The views

`TaskGroupDocumentToWidgetPane` draws a group as its pane: a card with the
counts of each code, a bar of the progress, the time, the reason of what was not
expected and the actions on the whole group; a table with one row for each task;
and the detail of the task whose row a person pressed, with its facts, its
buttons and its two streams. While the current execution of that task has a process, the detail shows the tree of its processes in a card, after the buttons and before the card of the result ([tree.md](../tree/tree.md) says how a tree draws). A task that ended has no tree, so the card of the result follows the buttons at once. The detail of a task that is a group is the pane of
that group: its card, with no actions of its own, its table and its detail. The
columns of the table are the state, the columns of the kind of the first task, and then the progress, the elapsed time,
the process, the processor, the memory and the result. The progress is a
`WidgetProgressRing` while the task runs: filled to the fraction that the task
reports, or turning when it reports none, with the position of the task in its
tooltip. A row reads the shadow of the current execution of its own document,
so a task that reports draws only its own row again, and the rows are a lazy
list, so a group of 22,731 tasks costs what a group of twenty costs. The head of
the list is the task that the `anchor` of the group names. A scroll far from the
head writes the head of the list of the table, and the pane writes the anchor
instead, as the owner of a list does; the list then starts again from that task.

**The links.** The row is what a person presses, and no cell of it. The table
gives a press on a row back as the selection of the row, and the pane turns it
into what the press does to the task of the row, at the place of the anchor: a
press shows the task in the detail, a double press opens the page of the task,
and Ctrl+press opens it in a new tab. A double press opens the page in the
navigator around the pane, or in a new tab when no navigator is there. The press writes `selected` of the group as
view state, so the undo does not record it. The table selects the
row of the task of the detail, and its tooltip says what a press does. The row
takes no key: the walk of the selection leaves the table out. The detail has
Open the task page, and in the Tasks pane the title of a group
opens the page of the group. Each answers `OpenPageOperation` with the document
that holds the part and a path from it, `tasks[i]` of a group or `groups[k]` of
the list, so the navigator around the pane opens the page where its content
holds it, and an open that no navigator takes opens a tab.

In a tree, the text of a task is its name and its status with the time when it started while it runs (`running since 14:02:11`), or the code of its result and how long it ran, with an icon of its status. The text reads no clock, so it changes only when the task does. A task is a leaf, but a task that is a group has the tasks of its inner group under its node. A group has its tasks under its node, and its text says its identifier, its title, how many of its tasks finished and each code that came back unexpected (`T3 fingerprint tests · 37/40 · 2 FAIL`), with the icon of its tab. The list of groups has a node for each group, and a closed group says that it closed.

`make_task_group_tab_title` is the title of the tab of a group, and the
`make_pane_tab_title` of a group: an icon and badges that say how far the group
is and the worst that it found. `TaskGroupListToWidgetPane` draws the Tasks
pane, one row for each open group of the session, newest first, with Stop, Run
unexpected again and Close. The title of a row is a link to the page of the group.
`make_task_group_list_tab_title` is the title of the Tasks tab, and the
`make_pane_tab_title` of a list: the icon of a list, and a badge with the count of
the groups that run. So a navigator whose page is the list gives its tab the same
icon and badge. `ClosedTaskGroupToWidgetPane` draws the page of a
closed group.

The panes draw with `TaskTheme`. `build_task_graphics_entry` makes the rows of
the natural renderer for both panes, each with a widget renderer of its own so
that a press reaches its button, and the slice registers them, so any
`NaturalToGraphics` draws a tab that holds a group or the list of groups.

## The pages

A navigator shows a task, an execution and a stream as pages; the slice registers
a row of the natural renderer for each. A part that leads to another page answers
`OpenPageOperation` with the document that holds it and a path from it, so the
navigator around the page opens it, and Ctrl+press opens it in a new tab.

- **The page of a task** (`TaskDocumentToWidgetPane`): its name, its state, and a
  link to its group; the facts of its kind, its process and its time; Stop, Run
  again and the buttons of its kind, which act through the group of the task, so
  the counts of the group follow, or on the task itself when it has no group; a
  kind that the editor does not start (`start_task`), such as a background task
  of an agent ([assistant.md](../assistant/assistant.md)), has only the buttons of
  its kind; a link to the page of the group of a task that is a group; its executions, the
  newest first, each a link to its page; and the last lines of each stream of its
  current execution, with a link to the page of the stream.
- **The page of an execution** (`TaskExecutionToWidgetPane`), the page of a
  shadow: its time, its verdict, the facts of the kind of its task, its process,
  its times, its use of the machine and its reason, and a link to the page of
  each stream.
- **The page of a stream** (`TaskStreamToWidget`): each shadow holds a
  `TaskStream` for each stream, `stdout_page` and `stderr_page`, which keeps the
  state of its view while the shadow follows its execution. A grid holds the bar
  at its height and the lines below it, which take the rest of the height. The
  bar holds the field of Find with ‹ and › and the count of the matches, the field
  of the text that the lines that show hold, the follow of the end, First error
  and Open as a file; each field is an `ObjectField` of the lines, and each
  button answers an operation on them (`make_task_stream_find_operation`,
  `make_task_stream_first_error_operation`). The lines
  (`TaskStreamLines`, drawn by `TaskStreamLinesToWidget`) read the file of the
  stream: an index of where each line starts grows as the file grows, so a
  stream of a million lines costs the lines that fit the height. Each line shows
  its number and its text in the colour of its mark, and the line of the current
  match in the colour of a task that runs. A turn of the wheel moves the top by
  three lines a notch, and the scroll bar jumps; at the last lines the page
  follows the end again. A search reads the file on the editor task, once for
  each text, and goes on from where it ended when the file grows.

The stream page has these limits: a line longer than the page is cut, no key
moves the lines (the wheel and the scroll bar do), the page copies no line, and a
search of a stream of many megabytes holds the editor task while it reads.

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
   views: `get_task_columns`, `format_task_column`, `format_task_details`,
   `get_task_actions`, `get_task_links` and `get_task_result_document`.
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
