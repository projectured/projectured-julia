# The assistant starts programs as tasks

> **Kind:** plan · **Status:** a plan of 2026-11-05, re-checked at `main` `6b93bfcf3`. No step is done.
> · **Stands on:** [task.md](../../documentation/package/platform/task/task.md),
> [assistant.md](../../documentation/package/platform/assistant/assistant.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [the-assistant-finds-its-names-by-reflection.md](the-assistant-finds-its-names-by-reflection.md)

This plan closes the gap G1 of the inet-cpp plan
`plan/pending/ieee80211-chart-baseline-evolution.md`, §9.3. The assistant of a window gets one
verb that starts a group of programs. Each program has its folder, its environment variables, its
log, its exit status and a stop. The owner decided on 2026-11-05 to close G1, G3, G4, G5 and G9
first.

The use case: for each of about 60 commits, one group checks out the commit, removes stale files,
builds INET and exports the charts, and hashes the pictures. Each step needs the step before it.
The person sees each group live in the Tasks pane, and its end wakes the assistant.

## 1. What exists

The assistant checked each row in the code on 2026-11-05, and again at projectured-julia `main`
`6b93bfcf3` and omnet-julia `main` `a1dfa5af3`.

| Thing | Where | State |
| --- | --- | --- |
| A kind that runs one command | `BuildCommandTask`, `source/platform/task/BuildStep.jl:40`; its start at `:244` | It ends `DONE`, `ERROR` or `CANCEL`, with the exit code in `BuildStepResult`. Its columns are "step" and "file" (`:337`). |
| A command that always runs | `is_build_step_up_to_date`, `BuildStep.jl:194–197` | It answers `false` when the outputs or the inputs are empty. So a caller passes `output_files = String[]` to run a program each time. |
| The environment of a build step | `setenv(command, step.environment)`, `BuildStep.jl:253` | The dictionary replaces the whole environment. omnet-julia passes a full environment (`get_env`). |
| The start of a process | `start_process_task!`, `source/platform/task/TaskExecution.jl:477` | The process gets a group of its own (`detach = true`, `:479`). `stop_task_execution!` sends `SIGINT` to that group (`:365–396`). |
| The log | `_make_output_path!`, `TaskExecution.jl:129–133`; `get_session_output_folder!` at `:101` | Each line goes to `<n>.stdout` or `<n>.stderr` under `~/.local/state/projectured/task-output/<process>`. The folder goes when the editor process ends. |
| A group | `TaskGroup`, `source/platform/task/TaskGroup.jl:191`, constructor at `:208` | It runs `jobs` tasks at a time, and `jobs = 1` is the sequential case. `_drive!` (`:428`) starts the next task after any result. |
| A task that does not start | `_run_preparation!` (`:493`), `_end_unstarted_task!` (`:525`) | When the preparation is not expected, each task ends `CANCEL` with a `TaskNotStarted` result whose reason names the preparation. |
| The document of a group | `wrap_task_group_document`, `TaskGroupDocument.jl:126`; `start_task_group_document!` at `:431` | The start adds the group to the list of the session of the editor (`:441`). The press of "Run all" calls the same function (`TaskGroupToWidget.jl:167`). |
| The names of the task slice | The mark `For the assistant.` at the end of the docstring of each verb in `source/platform/task/TaskVerbs.jl` (`function name end`), and of the types `TaskGroupDocument` (`TaskGroupDocument.jl:68`) and `TaskDocument`; `make_editor_api`, `source/platform/application/Application.jl:361`, collects every marked name; omnet-julia `source/ide/CampaignWindow.jl:232` and `source/ide/IdeWindow.jl:65` call `make_editor_api()` | Eleven verbs carry the mark. `make_task_api` does not exist. No mark starts a group: `run_tasks!`, `ProgramTask` and `TaskGroup` carry none, and `wrap_task_group_document` carries none. A marked name reaches the assistant of `omnet_ide` with no change in omnet-julia. |
| The model verbs | omnet-julia `_start_project_group!`, `source/ide/TaskVerbs.jl:657`; `run_simulations!`, `source/ide/CampaignVerbs.jl:477` | On the editor task they wrap the group, start it with `editor`, answer the document and place no tab. |
| The wake | `source/platform/assistant/AssistantWake.jl:22–52`; `ASSISTANT_WAKE_LIMIT` at `:18` | At the end of a turn, each group that started during the turn and still runs wakes the assistant when it ends, if its field `wake` is on. Any group in the list of the session counts. |
| A test that runs a program | `test/platform/conversation/AssistantWakeTest.jl:6` (`_make_wake_group`) | It runs `sleep` as a `BuildCommandTask` with no output files. |
| The seals | `SEALING.md` | The inventory covers `source/kernel/` only. No file of this plan is sealed. |

## 2. What the code lacks

1. **No verb starts a group.** `wrap_task_group_document` carries no mark, so the
   assistant of a window does not offer it, and no search result and no docstring tells a model
   about it.
2. **No kind is a program.** A `BuildCommandTask` shows the words of a build, needs empty output
   files, and drops `PATH` and `HOME` when a caller gives one variable.
3. **A sequence does not stop at a failure.** After a checkout that fails, the build runs on the
   commit before it. Its pictures then belong to the wrong commit, and nothing shows it.
4. **The docstring of `TaskGroup` lacks the form of a marked name**: "Use it to", an example
   and "See also". So the mark on `TaskGroup` fails `test_assistant_documentation` until the docstring has them.

## 3. Design

### 3.1 A program as a task

A new kind `ProgramTask <: AbstractTask` in a new file `source/platform/task/ProgramTask.jl`, with
its result `ProgramResult <: TaskResult`.

    ProgramTask(command; working_directory, environment = Dict{String,String}(),
                time_limit = nothing, name = <the file name of the program>)

- `command` is a `Cmd` or a vector of strings. A `Cmd` gives its words. A `Cmd` with a folder
  or an environment of its own throws an `ArgumentError` that names the two keywords.
- `working_directory` is required. The program runs there.
- `environment` adds its variables to the environment of the editor process with `addenv`. A
  variable of the same name replaces the one of the editor.
- `time_limit` is a number of seconds, or `nothing`. At the limit the task stops its process as a
  stop does, and ends `ERROR` with the reason `Time limit of 1800 s`. So a build that hangs can
  not hold the walk without end, and the group still ends and wakes the assistant.
- `name` is what the row of the task says, such as `"checkout"`.

The kind answers `RUN_RESULT_CODES` and its name (`format_task_parameters`). The start runs the
words with `start_process_task!`. The result is `DONE` on exit code 0, `CANCEL` after a stop, and
else `ERROR` with the reason `Non-zero exit code: 3` or `Ended by signal 15`. `ProgramResult`
holds the five fields of a result and `exit_code`. A folder that does not exist makes `run` throw,
so the group ends the task as a `TaskStartFailure` (`TaskGroup.jl:451–459`). No check reads the
disk before the start.

The kind answers the views: the columns `"name" => 2` and `"command" => 4`, and the facts
`command:`, `folder:`, `environment:` (the added variables only) and `exit code:`. A line that
holds `error:` or `fatal:`, in any case, gets the mark `:error`. A line that holds `warning:` gets
`:warning`. So the button First error of the stream page and the counts of the marks work.

### 3.2 A group that stops at a failure

`TaskGroup` gets the field and the keyword `stop_at_failure::Bool = false`. When a task of such a
group ends with a result that is not expected, `_drive!` starts no more task. The tasks that run go
on to their end. Each task that did not start ends `CANCEL` through `_end_unstarted_task!`, at
every depth. `_drive!` has the result of the task that failed, so the reason carries its name:
`Not started: checkout ended ERROR`. No reader must search for that fact later.

- With `jobs = 1` the group is a chain: each step starts only after the step before it ended
  as expected.
- With `jobs > 1` the group stops as `make` stops without `-k`.
- A stop of one task by the person ends it `CANCEL`, so the rest of the chain does not start.
- `rerun_tasks!(g; which = :unexpected)` runs the failed task and the tasks that did not start,
  in their order, under the same rule.
- The card says it: `commit 3fa2c1d (4 sequential, stops at a failure)`.

### 3.3 The verb

    run_tasks!(group::TaskGroup; title = group.name, editor = get_evaluation_editor())
        -> TaskGroupDocument

On the editor task, `run_tasks!` wraps the group with `wrap_task_group_document` and makes
`StartTaskGroupOperation` (D4). The editor evaluates it, and its evaluation calls
`start_task_group_document!(doc; editor)`. The group joins the list of the session of the editor.
So the Tasks pane shows it, and `_find_turn_task_groups` finds it at the end of the turn.

- It answers at once. The conversation shows the answer as a live card.
- It places no tab. `open_pane!(g)` places one when the person asks, and `show_pane!` shows it.
  It does not change the selection of the person.
- A group that started before throws an `ArgumentError` that names `rerun_tasks!`.
- It takes a group of any kind of task, and an inner group of any kind. The answer goes to
  `describe_task_group`, `get_task_output`, `wait_for_tasks!`, `stop_tasks!`, `stop_task!`,
  `rerun_tasks!` and `close_task_group!` as it is.
- It has no `wait` keyword. `wait_for_tasks!` waits a short time, and a person at the REPL calls
  `wait_for_task_group!(editor, g)`.

The use case in code:

    w = "<worktree>"; c = "3fa2c1d"
    g = run_tasks!(TaskGroup([
            ProgramTask(`git checkout --detach $c`; working_directory = w, name = "checkout"),
            ProgramTask(`make cleanall`; working_directory = w, name = "clean"),
            ProgramTask(`bash export-charts.sh $c`; working_directory = w,
                        environment = Dict("CHART_COMMIT" => c), name = "build and export"),
            TaskGroup([ProgramTask(`python3 hash.py $part $c`; working_directory = w, name = part)
                       for part in ("throughput", "delay")]; name = "hashes", jobs = 2)];
        name = "commit $c", jobs = 1, stop_at_failure = true); title = "commit $c")

### 3.4 How the names reach the assistant

The mark `For the assistant.` is the only rule. `make_editor_api` collects every name whose
docstring ends with the mark, and it adds the subtypes of a marked type. `run_tasks!`,
`ProgramTask` and `TaskGroup` each get the mark. The docstring of `run_tasks!` is on the generic
function (`function run_tasks! end`). The docstrings of `ProgramTask` and `TaskGroup` are on the
types. Each docstring has the form of a marked name: "Use it to", an example and "See also".
`AbstractTask` carries no mark, so the other kinds of task stay hidden. This plan changes no list
of names, and the window texts of the system (`EDITOR_SYSTEM`, `Application.jl:373`; `APPLICATION_SYSTEM`, `:426`) name `run_tasks!` (D7). `test_assistant_documentation()` checks the form.

## 4. Decisions

The assistant proposed D1, D3 and D5. The owner decided D2, D4, D6 and D7.
A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. A new kind, not `BuildCommandTask`.** A program has no input files, no output files and no
  check of what is up to date. Its row must not say "file". Rejected: `BuildCommandTask`
  as the program kind.
- **D2. The stop at a failure is a field of the group.** The owner decided this on 2026-11-05
  (open question 1, option A). `jobs` limits how many tasks run at a
  time. `stop_at_failure` says whether a task needs the tasks before it. The two combine. Rejected:
  a stop in every group with `jobs = 1`, because a set of independent runs with one job must not
  stop. Rejected: a chain of preparations, which hides the steps from the counts. Rejected: a graph
  of dependencies per task, which no view of a group shows.
- **D3. One generic verb on a `TaskGroup`.** The model builds the tree with the constructors that
  the code already has. Rejected: a verb that takes a list of commands, because it can not say
  which steps run in parallel.
- **D4. The actions of a group are operations.** The owner decided this on 2026-11-05 (open
  question 2, option A). A start, a stop of the group, a stop of one task, a rerun and a close each
  become an operation: `StartTaskGroupOperation`, `StopTaskGroupOperation`, `StopTaskOperation`,
  `RerunTaskGroupOperation` and `CloseTaskGroupOperation`. The buttons of the card and the verbs
  `run_tasks!`, `stop_tasks!`, `stop_task!`, `rerun_tasks!` and `close_task_group!` make the same
  operations, and the editor evaluates them. The inverse of each is `DoNothingOperation`, as for
  `StartExplorerSearchOperation`, because a process that ran can not be undone. The reason: the
  person and the assistant act on a group through one path, so the gesture log names the action,
  the fault barrier checks it, and the history sees it (the rule of the owner of 2026-10-01).
  Rejected: a direct call of `start_task_group_document!` from the verb, as the button calls it
  now.
- **D5. The environment adds variables.** A model names only what it changes, and the program
  keeps `PATH` and `HOME`. Rejected: a full environment, as `BuildCommandTask` takes it.
- **D7. The rule of the native assistant says how to run a program.** The owner decided this on
  2026-11-05 (option A). The last sentence of `DEFAULT_ASSISTANT_SYSTEM`
  (`AssistantDocument.jl:23` on main `6b93bfcf3`, which already holds the first two sentences) becomes: "NEVER read files or run programs directly in code. Read a
  file with the editor's verbs. Start a program as a task with `run_tasks!`, so that the person
  sees it and can stop it." The rule keeps its purpose, which is visible work through the editor,
  and it no longer forbids the editor's own verb. The docstring of `DEFAULT_AGENT_INSTRUCTIONS`
  names that rule, so its sentence changes too. Rejected: the rule as now, which forbids
  `run_tasks!` to the native assistant of the plain editor.
  Where the rule lives: step 6 of the reflection plan, on main since `97dee7cef` (2026-11-05),
  moved the rule into `EDITOR_SYSTEM`
  (`Application.jl:406`), the rules of every window, as "NEVER read files or run programs directly in
  code. Read a file with the verbs of the editor, such as `open_file!` and `read_document_file`."
  `DEFAULT_ASSISTANT_SYSTEM` (`AssistantDocument.jl:23`) is then only the fallback for an assistant whose window gives no text.
  G1 adds "Start a program as a task with `run_tasks!`, so that the person sees it and can stop
  it." to that rule of `EDITOR_SYSTEM` and to the fallback, in the same commit as the mark on
  `run_tasks!`: `test_assistant_documentation()` and `test_prompt_names()` of omnet-julia fail when
  a window text names a function that the window does not offer. Step 6 is on main
  (`6b93bfcf3`), so G1 changes the rule where main has it now. The last sentence of
  `DEFAULT_ASSISTANT_SYSTEM` (`AssistantDocument.jl:23`) is: "NEVER read files or run programs
  directly in code. Read a file with the verbs of the editor."
- **D6. This plan starts after steps 1 to 4 of `reflection-api` land.** Steps 1 to 4 landed on main `2bbc18fb5` (omnet-julia `991a89b4f`) on 2026-11-05, and `origin/main` holds them. The owner decided the order on 2026-11-05: steps 1 to 4 of `reflection-api` land on main first,
  after a rebase, its tests and the approval of the owner. Then this plan starts from main and
  uses only the mark `For the assistant.`; it adds no name to `make_editor_api`.
  Rejected: this plan first, with both forms. The investigation starts only after all six gaps
  close, so it gains nothing from an early G1, and each name would be written twice.

## 5. Steps

Each step runs in a worktree and ends with one commit. `workspace/bin/bounded-run` runs each test:
a test under `test/platform/` in `package/ProjecturedPlatformTest`, one under `test/projectured/`
in `environment/all`.

1. **A group stops at a failure.** **Done on 2026-11-06.** The field, the keyword, the shadow (`make_task_group_shadow`),
   `_drive!` and `_describe_group` in `TaskGroup.jl`, and the section "A group of tasks" of
   `task.md`. Test: `test_task_group()` (`test/platform/task/TaskGroupTest.jl`), with imitated
   processes. A new testset asserts the code and the reason of each task: a chain of three whose
   second fails, two jobs, an inner group after the failure, a stop of the second task, and a
   rerun of `:unexpected`. With the default `false`, each case of today keeps its order and its
   results. Also `test_task_views()` and `test_build_step()`.
   What the implementation found:
   - The field `stop_at_failure` sits after `jobs` in `TaskGroup` and in its shadow, so the
     positional constructor and `ACTaskGroup(...)` take it there. No file in omnet-julia
     calls the positional constructor.
   - A stop of one task ends it `CANCEL`, which is not expected, so the tasks after it end
     `CANCEL` with `Not started: two ended CANCEL`. When the whole group is stopping, the
     tasks that did not start keep no run, as before.
   - The new testset is in `test_task_group()`; `test_task_group()`, `test_task_views()` and
     `test_build_step()` pass together (213 Pass).
2. **A program is a task.** **Done on 2026-11-06.** The file `ProgramTask.jl`, included after `BuildStep.jl`, its exports,
   and a section "A program as a task" in `task.md`. Test: the new `test_program_task()`
   (`test/platform/task/ProgramTaskTest.jl`), registered in `ProjecturedPlatformTest.jl` and
   `PlatformSuite.jl`. With real `sh` processes it asserts: `DONE` and `exit_code == 0`; `exit 3`
   gives `ERROR` and `Non-zero exit code: 3`; `echo $WALK:$HOME` prints `1:` and the `HOME` of the
   editor; `pwd` prints the folder; a stop of `sleep 30` ends `CANCEL` in less than 5 s; `sleep 30`
   with `time_limit = 1` ends `ERROR` with its reason in less than 5 s; the line
   `fatal: bad revision` gets `:error`; a `Cmd` with its own folder throws; a folder that does not
   exist ends `ERROR`.
   What the implementation found:
   - `ProgramTask` is a struct of `arguments`, `working_directory`, `environment`, `time_limit`
     and `name`; `exit_code` of `ProgramResult` is `nothing` when a signal ends the process.
     The reason of a stop by the person is `Cancel by user`, as for a build step.
   - The timer is a `Timer` that the end of the process closes; a process that ended before the
     timer was kept closes it at once. The test asserts the result, the reason and the time of
     a limit and that a program that ends before its limit ends `DONE`. It does not read the
     timer itself, because no handle of it is kept anywhere that a test can reach.
   - The new test also runs `test_task_views()` (115 Pass together).
3. **The actions of a group are operations (D4).** **Done on 2026-11-06.** The five operations in `TaskGroupDocument.jl`,
   each with `evaluate_operation`, `make_inverse_operation` that answers `DoNothingOperation`, and
   `is_self_contained_operation`. The buttons of the card in `TaskGroupToWidget.jl` and the four
   verbs of today in `TaskVerbs.jl` make them. The section "The verbs" of `task.md`. Test:
   `test_task_views()` and `test_task_group_verbs()`. A new testset asserts that a press of
   **Run all**, **Stop** and **Run again** and each verb makes its operation, that the editor
   evaluates it, and that an undo after it changes nothing. Each case of today keeps its result.
   What the implementation found:
   - `CloseTaskGroupOperation(list, item)` removes the row from the list only. The Close button
     of the list did only that, and `close_task_group!` closes the panes first and then evaluates
     the operation, so each case of today keeps its result. It takes any work item, so the row of
     a search closes through it too; the Stop of a search row stays `stop_work_item!`.
   - The buttons pass the editor of the press (`editor -> evaluate_operation(editor, …)`); a
     press with `nothing` as the editor starts a group that joins no list.
   - No hook observes an evaluated operation, so the test puts a spy in the place of the editor
     for the buttons (it records the operation and evaluates it as the real editor), and asserts
     the effect of each verb, since a verb needs a real editor for `run_on_editor_task!`.
   - `test_task_views()`, `test_task_group_verbs()`, `test_task_group_table()` and
     `test_task_group()` pass together (315 Pass).
4. **The verb.** **Done on 2026-11-06.** `run_tasks!` in `TaskVerbs.jl` makes `StartTaskGroupOperation`. The three names
   `run_tasks!`, `ProgramTask` and `TaskGroup` carry the mark `For the assistant.` (D6). The
   docstrings of `run_tasks!`, `ProgramTask` and `TaskGroup`, with the mark. The `run_tasks!` sentence of D7
   in the rule of `EDITOR_SYSTEM` and in the fallback `DEFAULT_ASSISTANT_SYSTEM`, with the mark on
   `run_tasks!`. Also `test_prompt_names()` in omnet-julia. The system text, and
   the sections "The verbs" and "Add a kind of task" of `task.md`. Test: `test_task_group_verbs()`
   (`test/platform/task/TaskVerbsTest.jl`). It asserts: the answer is in `list_task_groups()` with
   its title; `wait_for_tasks!` answers `Ended: …`; a second `run_tasks!` of the group throws; the
   answer goes to `describe_task_group`, `stop_tasks!` and `close_task_group!`; the tabs and the
   selection do not change; "a model may call every verb" holds `:run_tasks!`. Then
   `test_assistant_documentation()`, `test_assistant_verbs()` and
   `test_referenced_document_editor()`, because new docstrings can move the rank of `search_api`.
   What the implementation found:
   - The system text of the native assistant lives in `source/platform/assistant/AssistantDocument.jl`
     (the plan says `conversation/`); the rule in `EDITOR_SYSTEM` and the fallback
     `DEFAULT_ASSISTANT_SYSTEM` both carry the `run_tasks!` sentence, and the docstring of
     `DEFAULT_AGENT_INSTRUCTIONS` names it.
   - `run_tasks!` checks the start time of the group on the calling task, so the `ArgumentError`
     reaches the caller and not the task of the editor.
   - The new testset of `test_task_group_verbs()` runs a chain of three programs whose second
     fails, and asserts the answer in the list, the unchanged tabs and selection, `Ended: …`,
     the `Not started: two ended ERROR` line, the second start that throws, and a stop and a close.
   - `test_task_group_verbs()` (83 Pass); `test_assistant_documentation()`,
     `test_assistant_verbs()` and `test_referenced_document_editor()` together (3268 Pass).
5. **The wake and the window.** **The automated test is done on 2026-11-06; the live check in `omnet_ide` and the move to `plan/done/` are open** (the MCP connection of `omnet_ide` was down). Test: a new testset in `test_assistant_wake()`
   (`test/platform/conversation/AssistantWakeTest.jl`). A tool calls `run_tasks!` with a
   `ProgramTask` that sleeps 1 s, and the note says `The task group "the sleep" ended: `. Then a
   live check in `omnet_ide` through its MCP connection, with a chain of four programs whose third
   is `false`. `take_picture` must show the row and its ring in the Tasks pane. The stream page of
   the second step must show its lines while it runs. The fourth step must show `CANCEL` with
   `Not started: …`. `stop_tasks!` must end a `sleep 600` in less than 5 s. Then
   `Pkg.precompile()` runs in omnet-julia, and this plan moves to `plan/done/`.


   What the implementation found:
   - The new testset of `test_assistant_wake()` has a tool that calls `run_tasks!` with a
     `ProgramTask` that sleeps 1 s; the note says `The task group "the sleep" ended: `
     (21 Pass for the whole function).
   - `Pkg.precompile()` and `test_prompt_names()` ran in a scratch environment of omnet-julia that
     points at these worktrees: 194 Pass. omnet-julia needed no change.

## 6. Risks

- **The drive schedules every group.** A fault in `_drive!` can leave a group that never ends,
  and the wake then never comes. Step 1 runs `test_task_group()`, `test_task_views()` and
  `test_build_step()`. `test_task_group_scale()` shows whether the check after each end costs time.
- **omnet-julia follows the platform.** The new field changes the positional constructor of
  `TaskGroup`. omnet-julia makes its groups with keywords, and step 5 checks that it precompiles.
- **The rank of `search_api` can move**, because the docstring of `run_tasks!` names the Tasks
  pane. Step 4 runs `test_referenced_document_editor()` and `test_assistant_verbs()`.
- **A model can forget `jobs = 1`.** The default of `jobs` is the count of processor threads, so
  the steps of a chain would run at once. The example of `run_tasks!` starts with `jobs = 1`, and
  the card says `concurrent`.
- **The timer of `time_limit` must end with its process.** A timer that stays open can hold a
  compile workload that starts a task. Step 2 asserts that no timer stays after the end.
- **The log goes with the editor process** (`TaskExecution.jl:101`). A script whose log must stay
  writes the log itself.
- **The row of an inner group shows no name**, because a table takes the columns of its first task
  (`TaskGroupDocument.jl:180–181`). Its state, its progress and its result show.

Not in this plan: the limit of three wakes (G9,
[the-assistant-wakes-until-a-long-work-ends.md](the-assistant-wakes-until-a-long-work-ends.md)), and
a sentence in the IDE text of omnet-julia (`source/ide/IdeWindow.jl:152`). Also not: the
omnet-julia verbs on `run_tasks!`, one start of a process for both kinds, and a log that stays.

## 7. Open questions for the owner

1. **The stop at a failure (D2).** Answered by the owner on 2026-11-05: the field (D2). The
   question was: is `stop_at_failure` on `TaskGroup` the right model? The
   other model stops every group with `jobs = 1`. The assistant recommends the field.
2. **The start as an operation (D4).** Answered by the owner on 2026-11-05: yes, and the stop, the
   rerun and the close too (D4). The question was: must the start of a group be an operation that the editor
   evaluates, for the press of "Run all" and for the verbs? That is a new operation type, so the
   assistant asks first. The assistant recommends no new operation in this plan.
3. **The order (D6).** Answered by the owner on 2026-11-05: no, steps 1 to 4 of `reflection-api`
   land first (D6). The question was: can this plan land on `main` before `reflection-api`, with the declared
   list and the mark? The assistant recommends yes.
