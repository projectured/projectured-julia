# The feeds of an editor are its own

Status: DONE, branch `feeds-of-an-editor` here and in omnet-julia, 2026-10-26. No decision is open.

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

1. [x] **The wrappers.** The three wrappers, on by default; the two pushes go; the
   downstream window takes the wrapper. Tests: `test_platform()` for the task, the
   system process and the assistant slices; `test/platform/conversation/AgentWorkTest.jl`,
   which counts the task feeds of an editor; and a new test: a task group that a
   verb starts in a window with no assistant updates its rows.
2. [x] **The task feed of each editor.** The editor of each entry, and the drain
   that takes only its own. Tests: `test/platform/task/TaskDocumentTest.jl`, and a
   new test: two editors in one process each start a task group; each editor shows
   only its own tasks, and neither records a `ForeignCellWriteException`.
3. [x] **The guides.** `documentation/package/kernel/editor.md` ("The feeds": the
   list is fixed when the editor is made), `documentation/package/platform/task/task.md`,
   and `documentation/design/communication-anatomy.md`. The plan moves to
   `plan/done/`.

## Not in this plan

- One store for each editor, the option A of L21-1 in
  `plan/pending/kernel-audit-fixes.md`, which D12 keeps for later.

## As built

Steps 1 and 2 change the same lines of `TaskFeed.jl`, so one commit holds both.

- **The wrappers.** `task` (`TaskFeed.jl`), `system_process`
  (`SystemProcessSync.jl`) and `agent_event` (`AgentEventFeed.jl`), each
  `:screen => 20` and on by default (`is_wrapper_default`). A tie in a layer is
  ordered by the keyword, so the feed of the agents drains before the feed of the
  tasks, and a background task that an event registers is synced in the same
  frame.
- **No push into a running editor.** `show_system_process_tree!` finds the feed
  and throws an `ArgumentError` when the editor has none. The join of a source of
  the agents finds the feed; with none, an editor whose loop runs throws, and an
  editor with no loop, as in a test, applies the events at once as before.
  (Mine: an error and not a fallback, because a fallback is the push that the
  plan removes.)
- **Editors that apply no wrappers.** `make_editor` and `Editor` get only the
  feeds that the caller gives. `make_task_feeds()` stays for them. The gallery
  of examples (`_make_window_scene_editor`) gives the three feeds itself,
  because its windows can show an assistant. The tests that build an `Editor`
  for an assistant with a loop give `AgentEventFeed()`.
- **The editor of an execution.** `TaskFeedEntry` holds it.
  `register_task_execution!` reads it from `find_evaluation_editor()`.
  `start_task_group_document!` and `rerun_task_group_document!` run the start
  under `run_with_evaluation_editor`, so the scheduler of the group and every
  task that it starts, at any depth and in the preparation, inherit the editor
  through the scoped value. No document holds the editor. An editor that is not
  an `Editor`, such as the stand-in `(document = a,)`, counts as no editor,
  because it has no feed.
- **The drain.** `drain_task_feed!(store; editor)` and
  `has_task_feed_entries(store; editor)` take only the entries of `editor`, with
  `find_evaluation_editor()` as the default, so a call in a frame or in a feed
  drains its editor, and a script drains no editor. A drain also lets go every
  entry of an editor whose loop ended, so a closed window leaks no entry.
  `start_task!`, `wait_task_document` and `wait_task_group_document` take the
  keyword `editor`; a test that starts a group in an editor waits with it.
- **Downstream (omnet-julia, branch `feeds-of-an-editor`).** `CampaignWindow`
  takes the task feed from the wrapper. The two launchers of the legacy examples
  give no feed, because the gallery gives it. `wait_for_run_card!` drains with
  its editor.
- **Tests.** New in `TaskDocumentTest.jl`: a drain of an editor syncs only its
  own executions, a feed of one editor asks for no frame for another, and the
  entries of an ended editor are let go; a window that `build_editor` makes has
  one feed of each kind, and a group that a verb starts there with no assistant
  follows its tasks in the frames. The platform tests (task document, system
  process, task verbs, task views, agent work, assistant work, layering): 617 of
  618; the one failure is the layering guard, which names two files that this
  plan does not touch and fails on main the same way. The assistant tests and
  the gallery wrappers: 226 pass, 4 broken. The naming guard passes. In
  omnet-julia, over both branches in one scratch environment: the task feed, the
  statistical test, the task verbs, the campaign loop, the campaign actions, the
  explorer, the part pages and the study runs: 290 pass after three tests wait
  with the editor that started their group.
