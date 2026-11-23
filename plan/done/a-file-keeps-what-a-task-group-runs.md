# A file keeps what a task group runs

## The problem

This is F11 of [the-editor-for-the-assistant-of-the-catch-up.md](the-editor-for-the-assistant-of-the-catch-up.md).
`write_document_file!` of a document that holds a task group fails:

    cannot write a ProjecturedPlatform.TaskModule.ProgramTask at entries.children.elements.tasks.task

The workflow of the catch-up holds the task group of the walk log in its walk stage,
and the Catch-up explorer holds the workflow. The assistant took the task elements out
before each save of the workflow and put them back.

The cause: a `.pred` file writes a document as the call of its fields, and the default
`pred_arguments` writes every field. `TaskGroupDocument` and `TaskDocument` have no file
form of their own, so the writer writes their live fields too: the native `TaskGroup`
with its runs and its scheduler, the shadow, and in each `TaskDocument` the task value,
the executions and the process tree. `AbstractTask` is not a `Document`, and no task kind
says that a file can build it, so the writer refuses the first task value, a
`ProgramTask`.

## The decision of the owner (2026-11-20)

A file keeps what the group runs, and a load gives the same group, not started. The
output of a run is not kept. The other choices were a record of the run that cannot
start again, and a mark that a live group was there.

This follows the rule of `SystemProcessTree`: "A file keeps the roots, the title and the
folder that the tree reads, and not what a read found."

## The design

- `ProgramTask`, `BuildCommandTask`, `BuildCopyTask`, `BuildRemoveTask` and `ResultCodes`
  are plain data. Each one says that a file can build it (`is_pred_constructible`), with
  a file form that its constructor reads back.
- The native `TaskGroup` writes only what it runs: `tasks`, `name`, `action`, `jobs`,
  `stop_at_failure`, `codes` and `preparation`. It writes no runs, no tally, no summary,
  no counts, no times and no runtime. An inner group and a preparation that is a group
  write in the same way.
- `TaskGroupDocument` writes its group, its title, its description and its job count. A
  load makes the document with `wrap_task_group_document`, which makes the task
  documents and the inner groups. The group is not started and gets a new identifier. At
  its first start it joins the task list of the session, as every group does
  (`start_task_group_document!` calls `add_task_group!`).
- A `TaskDocument` writes its task and its title. A load makes a task of no group, not
  started.

## Proposed decisions (approved with the plan, 2026-11-20)

1. The environment of a task is written as a mapping of names, because the notation has
   no `Dict`. An empty environment is left out. A name that the notation cannot write is
   refused at the save, and the error names it.
2. The codes of a group are always written, so a load gives the same codes.
3. A task kind with no file form stays refused at the save, and the error names its type,
   as now: the tasks of omnet-julia and `AgentBackgroundTask`.
4. A document that holds one task of a group alone writes it as a task of no group.

## Steps

1. ✅ A test that fails on main: a section holds a group of two `ProgramTask`s in a
   temporary folder; the group runs, the section is saved, and the load gives the same
   commands with the state "not started"; a start adds the group to the task list of the
   session. A testset of `test_task_document`. Done 2026-11-23: the testset also holds a
   preparation, a task of no group and a group of groups. On main it fails at the save
   with "cannot write a ProjecturedPlatform.TaskModule.ProgramTask at entries.tasks.task",
   and the other 131 checks of `test_task_document` pass.
2. ✅ The file forms of `ProgramTask`, the three build steps and `ResultCodes`. Done
   2026-11-23. `TaskResult.jl` holds what each kind shares: `ResultCodes` is
   constructible, and a helper writes the keywords of a kind with each field that holds
   something, the environment as a mapping of names in the order of the names. A
   `ProgramTask` is `ProgramTask(arguments, working_directory = …, name = …)`, with
   `environment` and `time_limit` only when it has them. A build step is the call of its
   keyword constructor. Proposed decision 1 is in the writer of a mapping of names in
   `PredFile.jl`, for every mapping: a name that is no Julia name is refused, as a
   symbol that does not read back is, with the place, such as
   `environment.MY-VAR`. Tests: `test_program_task` 39 of 39, `test_build_step` 40 of
   40, `test_pred_file` 90 of 90.
3. ✅ The file forms of `TaskGroup`, `TaskGroupDocument` and `TaskDocument`. Done
   2026-11-23. `TaskGroup` writes its tasks, `name`, `action`, `jobs`,
   `stop_at_failure`, `codes` and `preparation`; `TaskDocument` writes its task and its
   title; `TaskGroupDocument` writes its group, its title, its description and its job
   count, and its reader calls `wrap_task_group_document`. Found on the way: the writer
   named a call by `nameof` of the type, so a file said `MTaskGroup(…)`, because the
   bare name `TaskGroup` of a `@document [M, C]` schema is an alias of the native layout
   `MTaskGroup`. The kernel gives `get_document_schema_name` for the name that a reader
   sees, and the reader of a file already knows both names, so the writer now names a
   document and a value by `get_document_schema_name`. In projectured-julia only
   `TaskGroup` and `TaskExecution` have such a bare name, and no file wrote either
   before; omnet-julia has 30 such schemas, and no saved file and no test text of it
   names a native layout. omnet-julia defines no file form of a type of this plan.
   Tests: `test_task_document` 154 of 154, `test_task_group` 111 of 111,
   `test_program_task` 39 of 39, `test_build_step` 40 of 40, `test_pred_file` 90 of 90.

The tests of each step: `test_task_document`, `test_program_task`, `test_build_step`,
`test_task_group` and `test_pred_file`.

## State

Done 2026-11-23. The owner approved the land and the push. The three steps landed on
main by a fast-forward at `eb60f1408`, after a rebase over main `d85427334` with no
conflict, and were pushed. The IDE gets the fix with its next build; then the assistant
saves the workflow of the catch-up with its task group, and needs no `save_workflow_1`.
