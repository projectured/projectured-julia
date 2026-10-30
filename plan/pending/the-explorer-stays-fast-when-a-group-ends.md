# The Explorer stays fast when a group ends

Status: pending. Written 2026-10-30. Work on the branch `explorer-open-paths`
(worktree `projectured-julia-explorer-open-paths`), from main e52478247. The
three steps are done (2026-10-30); the switch back to the Explorer after a group
still takes 3.90 s, and the next fix waits for the owner (step 3).

## The ask

The owner, 2026-10-29: "after running some queueing tests (or any other) the UI
becomes not responding when switching back to the explorer". Then: the window
comes back after some seconds; a scroll is fast after it; a run of the 6 queueing
tests is fast while it runs, and the window stops responding when the group ends.
The Explorer had the inet-cpp item "queueing tests" open with its 57 tests, each
test showing its last result. On 2026-10-30 the owner said: "Fix the explorer".

## What is known

- A perf recording of the owner's window during the slow moment (56,233 samples):
  - garbage collection takes about 40% of the time;
  - `_unregister_dependent!` (`source/kernel/cell/ReactiveCell.jl:788`) takes 14.7%:
    a reader that computes again searches the whole `dependents` list of each of
    its inputs to take itself out;
  - `_compute_open_paths` of the Explorer tree
    (`source/platform/tree/DocumentTreeToWidgetTree.jl:315`) takes 49% inclusive.
    `_collect_open_paths!` builds every child entry of an open node
    (`entries[k]`, line 337), also a closed one, only to ask whether its document
    is open. The lazy branch above it visits only the children that a walk reached.
- In omnet-julia, every test node of a kind reads the one shared cell `last_tasks`
  of its `LegacyTestKind` (`source/ide/LegacyProjectTests.jl:155`), and a folder
  node counts the results of every last task under it (line 109).
- A headless run with the real Explorer and the 57 queueing tests found shared
  cells with about 1,100 readers at the open of the folder, but it never reached
  the end of the group: the group document did not sync, so the slow frame was not
  measured.

## Rules for this work

- Never run a task against a real project folder. Copy `inet-cpp` (or the part
  that the Explorer and the queueing tests need) into the scratchpad first.
- Run every Julia process with `bounded-run`.
- omnet-julia loads projectured-julia from the main checkout, so a test in omnet
  of this branch uses a scratch environment (copy omnet `environment/all`
  Project.toml and Manifest.toml, rewrite each path to absolute, projectured to
  this worktree).

## The steps

- [x] **Step 1 — Measure the end of a group.** A headless harness with the Explorer
  of the copied project open at "queueing tests", a group of the 6 Gate tests
  (imitated processes), the group tab shown and the Explorer hidden in the same
  pane group, and the end of the group synced to its document as in the app.
  Record the time of each frame around the end of the group, the count of cells
  that compute again by file:line, and the length of the longest `dependents`
  lists at `_detach_upstream!`.

  **Done.** The frame at the end of the group is fast; the slow frame is the first
  frame that shows the Explorer again after the group: 6.6 s and 3.9 GB.

  - The harness: a copy of inet-cpp without `.git`, `out`, `statistics`, `doc`,
    the libraries, the `work` folders and the results (90 MB). The window is that
    of `run_campaign_window` without the loop, the assistant and SDL (headless
    backend, `file_change`, the acquire of the window tree), over the copy, with
    the Explorer open at Simulation projects › inet › Tests › Queueing tests (57
    rows). A frame is `drain_feeds!` and `run_frame!`, as `run_measured_frame!`
    runs them. The group syncs at its end through the `TaskFeed` of the editor,
    which `drain_feeds!` drains; the start of the group runs with the editor as
    the editor of the evaluation (`run_with_evaluation_editor`), so that its
    executions belong to that editor. The imitated `opp_test` writes
    `work/<test>` in the copy and runs 2 s. First all 57 queueing tests run once
    with the Explorer shown, then the 6 Gate tests with the group tab shown and
    the Explorer hidden, then the Explorer is shown again, then the group tab and
    the Explorer once more with no group in between.
  - The frames, in a run with no probe: the end of the 57 tests with the Explorer
    shown 0.040 s; the end of the Gate group with the Explorer hidden 0.011 s; the
    first frame that shows the Explorer after it **6.64 s, 3.9 GB allocated, 0.38 s
    of GC** (6.34 s and 6.84 s in two more runs), the next frame 0.31 s (0.29 s
    compile), then 0.001 s. The control, the Explorer shown again with no group
    since it was hidden: 0.0024 s.
  - The cells in that frame (a probe run, which takes 8.9 s): 298,083 computes,
    and 660 million entries of `dependents` scanned by `_unregister_dependent!`.
    By place:
    - 91,760 computes of 1 cell: the listing of the folder `tests/queueing`, a
      background cell (`FileSystemDocument.jl:237`) that is provisional from the
      write of `work` until its answer comes;
    - 91,759 computes of 1 cell: the elements of `entries` of the node "Queueing
      tests" (`_make_tree_entry`, `CellVector.jl:186`), and 53,824 computes of
      52,666 new slots of it (`_make_tree_entry` of a child);
    - 37,382 computes of 1 cell: the elements of `nodes` of that node, and 18,448
      computes of 18,286 new slots of it (`_make_tree_node`);
    - 611 computes of `_compute_open_paths` (the open paths of the widget) and
      610 of the print of the `WidgetTree`.
    Three cells were invalidated in the frame, the listing among them.
  - The longest `dependents` lists at a detach: 4,001 entries, 294 of them alive
    after the frame, each scanned about 92,000 times: the cell `folder` of the
    kind, the field `entries` of the folder, its elements, and the computation of
    the entries of the folder (`LegacyProjectTests.jl:241`, 3,929 entries). A
    reader that a recompute replaced is not collected inside the frame, so its
    entry stays in the list until a GC.
  - The cause: a provisional cell computes again at each read by a computation
    (`make_background_cell`). While the Explorer is hidden nothing reads the
    listing, so it stays provisional until the switch. Then every read of a child
    of "Queueing tests" computes the listing and the elements of `entries` again
    (step 3 says why), and the elements make 57 new slots each time.
    `_collect_open_paths!` reads every child (`entries[k]`) of the open node
    "Queueing tests", and the open paths, provisional too, compute again at each
    read by the widget. With the Explorer shown, the listing is provisional for
    one frame only (the 0.040 s at the end of the 57 tests).
  - The owner's window matches the harness: the perf recording has the same chain
    (`_compute_open_paths` → `_collect_open_paths!` → `getindex` → `_recompute!`
    → `_detach_upstream!` → `_unregister_dependent!`), and the owner saw the
    window stop at the switch back to the Explorer. GC is 40% of the recording
    and 6% of the harness frame; the recording ran with SDL and the whole IDE.
  - Scripts: `explorer/end.jl` and `explorer/run.sh` in the scratchpad of the
    session; the omnet environment of this branch is `explorer/env`.
- [ ] **Step 2 — The walk builds only the open nodes.** `_collect_open_paths!`
  builds the entry of a child only when the document of the child is open (a key
  of the open places below its node). Measure again with the harness of step 1.
  Tests: the tests of the document tree, `test_explorer`, and the explorer tests of
  omnet-julia in the scratch environment.

  **Done.** `_collect_open_paths!` returns after it records an open node whose
  open places below are empty, so it reads no child of a node that is open with
  every child closed, such as "Queueing tests". For a node with an open place
  below it, it reads the documents of the children with
  `collect_read_tree_children` (the children in the order of `entries`, from
  their collections), and reads `entries[k]` only for a child whose document is
  a key of the open places below. The lazy branch already did so. The tree guide
  says it under the design decisions.

  - The switch frame of step 1, with no probe: **3.90 s and 2.8 GB** (6.64 s and
    3.9 GB before); the next frame 0.24 s, then 0.001 s. The end of the 57 tests
    with the Explorer shown 0.035 s (0.040 s before), the end of the Gate group
    with the Explorer hidden 0.010 s (0.011 s), the control 0.0014 s (0.0024 s).
  - The cells of the switch frame (probe): 190,113 computes (298,083 before),
    204 million entries scanned at a detach (660 million). The open paths no
    longer compute again in the frame (611 times before). The listing computes
    55,770 times (91,760), the elements of `entries` of "Queueing tests" 55,769
    times (91,759) with 18,444 computes of 18,281 new slots (53,824 of 52,666),
    the elements of `nodes` 37,382 times and its slots 18,448 times (both as
    before), the print of the `WidgetTree` 610 times (610). The longest
    `dependents` lists at a detach have 1,322 entries (4,001), the same four
    cells of the folder.
  - Tests, all on this branch: `test_document_tree`, `test_explorer`,
    `test_explorer_row_notes`, `test_help_tree`, `test_document_decoration`,
    `test_system_process` and `test_work_plan` in `environment/all`: 726 Pass,
    0 Fail, 0 Error, 0 Broken. In omnet-julia, through the scratch environment
    that loads this worktree: `test_campaign_explorer_content`,
    `test_campaign_explorer` and `test_project_tests`: 154 Pass, 0 Fail, 0 Error,
    0 Broken.
- [x] **Step 3 — The result.** If the frame at the end of a group is fast (under
  0.1 s with 57 tests), write the numbers here. If it is not, write the next cause
  with its numbers, and stop for the owner: a second fix (the shared `last_tasks`
  cell, or the scan of `_unregister_dependent!`) is a separate decision.

  **Done: not fast; the work stops here for the owner.** The frame at the end of
  the group is under 0.1 s before and after (0.010 s with the Explorer hidden,
  0.035 s with it shown), but the first frame that shows the Explorer after the
  group takes 3.90 s (6.64 s before step 2).

  The next cause is the provisional listing of the folder, not `last_tasks`: the
  `dependents` list of `last_tasks` is not among the ten that cost the most scan
  at a detach, and the cells that compute most are the listing and the lists of
  the tree node. A background cell that waits for its answer is provisional, a
  provisional cell computes again at each read by a computation
  (`make_background_cell`, `BackgroundCells.jl`), and so does each cell that read
  it. The write of `work/` in `tests/queueing` makes the listing provisional, and
  nothing reads it while the Explorer is hidden. The keys of `entries` of a node
  (`_make_tree_entry`, `DocumentTreeToWidgetTree.jl:72`) ask for the children
  first (`demand_tree_children`), and for "Queueing tests" the ask reads the
  listing; so the keys are provisional though their value, `1:57`, does not
  change. At the switch, each read of the children of "Queueing tests" by the
  print of the widget computes the elements of `entries` again (55,769 times in
  the frame, and the listing 55,770 times), and the elements of `nodes`, which
  read the length of `entries`, 37,382 times. Each compute of a `CellVector` with
  `element` makes a new slot for every one of the 57 keys (`CellVector.jl:186`),
  so the frame makes 18,281 new entries and 18,309 new nodes, and the print of
  the `WidgetTree` computes 610 times. Each reader that a compute replaced stays
  in the `dependents` lists of the cells that the children of the node read (the
  `runners` and the `folder` of the kind, the `entries` of the folder, and their
  elements) until a GC: 1,322 entries, 204 million entries scanned by
  `_unregister_dependent!`.

  Three places could take the rest; none is measured, and each is the owner's
  decision:
  - the tree: the ask for the children of a node moves out of the keys of
    `entries` into a cell of its own that the node reads with no dependency, so
    the keys of "Queueing tests" stay final while the listing waits
    (`DocumentTreeToWidgetTree.jl`);
  - the collection: a `CellVector` with `element` keeps the slot of a key that
    stays when its keys compute again, so a compute of `entries` and `nodes` of a
    node makes no new entry and no new node for a child that stays
    (`CellVector.jl`);
  - the kernel: a provisional cell computes once for each new input or answer in
    place of at each read (`BackgroundCells.jl`, `ReactiveCell.jl`), or
    `_unregister_dependent!` stops scanning the whole list of a cell.

## Not in this plan

- A change of the data model of the last task of a test in omnet-julia.
- A change of the reactive cell kernel, unless the owner decides it after step 3.
