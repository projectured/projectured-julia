# The feeds of an editor are its own

Status: PENDING, 2026-10-19. Not started. No decision is open.

## The ask

The owner, 2026-10-19, after the survey of the means of communication: "let's
plan this and also the smaller items". Two small items are about the feeds: a
feed that joins a running editor gets no wake, and the task feed of one editor
writes the task documents of every editor.

## The problem

1. **Two slices add a feed to a running editor.** The tree of the system processes
   adds a `SystemProcessFeed` at its first use (`SystemProcessProgram.jl:43`),
   and the assistant adds an `AgentEventFeed` and a `TaskFeed`
   (`AgentEventFeed.jl:585`). No call gives these feeds the wake of the editor.
   Each of the three gets its frames by a deadline or by a direct
   `wake_editor!`, so nothing is broken today, but a feed with a store would lose
   its wake. The push also runs inside the drain of the inbox, while the loop
   iterates the feeds. The kernel says that registration is the one moment a feed
   meets its editor (`Editor.jl:172`).
2. **No application gives a `TaskFeed` when it makes the editor.** Only the
   assistant adds one. So in a window with no assistant session, the rows of a
   task group that a verb starts do not follow the task.
3. **The task feed writes the documents of every editor.** The store of the task
   feed is one for the process (`SESSION_TASK_FEED_STORE`), and its drain syncs
   every entry that changed, whatever editor the task belongs to
   (`TaskFeed.jl:113`). With two editors, the first editor that drains writes the
   shadow and the rows of the tasks of the second editor from its own owner task,
   and the second editor never sees those changes. The owner decided on
   2026-10-14 that the stores stay one for the process and that each editor has
   its own documents, which its own feeds copy (D12 of
   `plan/done/the-editor-always-answers-the-person.md`).

## The model

1. **Every feed meets its editor when the editor is made.** The task slice, the
   system process slice and the assistant give their feed through a wrapper of
   the build, as the log, the MCP log, the file change and the frame statistics do
   today. The wrappers are on by default, because a feed with nothing to watch
   costs no frame. The two pushes into a running editor go. A window that gives
   its task feed by hand (`CampaignWindow.jl:272` in the downstream simulator)
   takes the wrapper instead.
2. **The task feed copies only the tasks of its editor.** Each entry of the store
   records the editor that the task belongs to: the editor of the evaluation that
   starts the task, which a start off the owner task passes down. The drain of a
   feed takes only the entries of its editor, and leaves the others in the store.
   A caller with no window (`wait_task_document`, `wait_task_group_document`)
   drains only the entries with no editor. The store stays one for the process, as
   D12 decided.

## Steps

1. [ ] **The wrappers.** The three wrappers, on by default; the two pushes go; the
   downstream window takes the wrapper. Tests: `test_platform()` for the task, the
   system process and the assistant slices; `test/platform/conversation/AgentWorkTest.jl`,
   which counts the task feeds of an editor; and a new test: a task group that a
   verb starts in a window with no assistant updates its rows.
2. [ ] **The task feed of each editor.** The editor of each entry, and the drain
   that takes only its own. Tests: `test/platform/task/TaskDocumentTest.jl`, and a
   new test: two editors in one process each start a task group; each editor shows
   only its own tasks, and neither records a `ForeignCellWriteException`.
3. [ ] **The guides.** `documentation/package/kernel/editor.md` ("The feeds": the
   list is fixed when the editor is made), `documentation/package/platform/task/task.md`,
   and `documentation/design/communication-anatomy.md`. The plan moves to
   `plan/done/`.

## Not in this plan

- One store for each editor, the option A of L21-1 in
  `plan/pending/kernel-audit-fixes.md`, which D12 keeps for later.

## As built

Nothing yet.
