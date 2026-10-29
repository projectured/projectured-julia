# The Explorer stays fast when a group ends

Status: pending. Written 2026-10-30. Work on the branch `explorer-open-paths`
(worktree `projectured-julia-explorer-open-paths`), from main e52478247.

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

- [ ] **Step 1 — Measure the end of a group.** A headless harness with the Explorer
  of the copied project open at "queueing tests", a group of the 6 Gate tests
  (imitated processes), the group tab shown and the Explorer hidden in the same
  pane group, and the end of the group synced to its document as in the app.
  Record the time of each frame around the end of the group, the count of cells
  that compute again by file:line, and the length of the longest `dependents`
  lists at `_detach_upstream!`.
- [ ] **Step 2 — The walk builds only the open nodes.** `_collect_open_paths!`
  builds the entry of a child only when the document of the child is open (a key
  of the open places below its node). Measure again with the harness of step 1.
  Tests: the tests of the document tree, `test_explorer`, and the explorer tests of
  omnet-julia in the scratch environment.
- [ ] **Step 3 — The result.** If the frame at the end of a group is fast (under
  0.1 s with 57 tests), write the numbers here. If it is not, write the next cause
  with its numbers, and stop for the owner: a second fix (the shared `last_tasks`
  cell, or the scan of `_unregister_dependent!`) is a separate decision.

## Not in this plan

- A change of the data model of the last task of a test in omnet-julia.
- A change of the reactive cell kernel, unless the owner decides it after step 3.
