# An editor says what holds its memory

**Status:** proposed on 2026-11-25. It waits for the approval of the owner. The owner
asked for this plan on 2026-11-25 ("yes, write the plan for step 1"). The work goes in
the worktree `projectured-julia-held-memory`, on the branch `held-memory`.

The plan lands nothing and pushes nothing. It ends with a request to land.

**If a step needs a change of a kernel file, or a mechanism that this plan does not
name, the work stops and the session asks.**

## The problem

The memory of a long editor session grows and does not come back. The IDE
(`omnet_ide --assistant=acp`) grew to 10.1 GB resident memory in 27 hours on
2026-11-19, and the owner had to restart it. In that time the owner reloaded about 40
pages and opened 76 step pages.

A read of the code on 2026-11-25 found five stores that keep a document, or a view
of it, with no rule for when to let it go:

| # | Store | What it keeps | What makes it grow |
|---|---|---|---|
| 1 | `CellVectorView.kept` (`source/platform/projection/higherorder/CellVectorView.jl:46`, `:97`) | The view and the element of every element that the list view ever showed. Nothing removes an entry. | Each insert, delete or replace in a list that shows through views, and each scroll. |
| 2 | `Navigator.back` (`source/platform/navigator/NavigatorDocument.jl:114`) | One visit for each page, with the content and the view of the page. There is no limit. | Each page that a person opens. |
| 3 | `release_document!(editor, ::FileSystemFile)` (`source/platform/filesystem/FileSystemDocument.jl:84`) | The parsed document, its undo steps and its view, when the file has an unsaved edit or a caret that is not active. | A click puts a caret in the file, so a closed file that a person clicked stays. |
| 4 | `TaskDocument.executions` (`source/platform/task/TaskDocument.jl:29`), and the line index of a task output | One entry for each start of a task, and 8 bytes for each line of output. | Each start, and each line, until the group closes. |
| 5 | A file that `open_file_document!` adds with no holder (`source/platform/filesystem/FileSystemDocument.jl:299`) | A permanent entry in `OpenFileList`. | Each `file("...")` reference that nothing opens. |

Two more things make each kept item heavier:

- A cell that a write makes invalid keeps its old value until something reads it
  again (`source/kernel/cell/ReactiveCell.jl:501`). The view of a field keeps the last
  document that it showed in its closure
  (`source/platform/projection/higherorder/ContentViewDeclaration.jl:51`). So a view
  that nobody reads again holds the document that it showed last, and after a reload
  that is the old version of the file.
- An undo history keeps at most 100 steps
  (`source/platform/undo/UndoDocument.jl:49`), but one step can hold a whole old
  subtree. The undo of the window holds a closed tab with its content.

This is a reading, not a measurement. No test fails when the memory of an editor
grows, so a fix can come back unseen, and nothing can confirm which store fills the
IDE. This plan gives the two tools that the fixes need. The fixes come after it,
each in its own plan.

## The goal

1. **A report of what holds the memory.** `compute_held_memory(root)` walks from
   `root`, such as an editor, and gives the bytes that each holder keeps, with the
   path of the holder from the root, its type and the count of its objects. It also
   gives the count and the bytes of each type. `describe_held_memory()` gives the same
   report as text for the editor of the session, so the assistant of the IDE can run
   it when the owner asks.
2. **A test that the memory of an editor stays flat.** One cycle of gestures runs
   230 times in one editor. After the warm-up, the memory that each holder keeps must
   not grow. Each store that grows now is a known growth with its reason, so the test
   passes on `main`, and each later fix removes its entry.

```julia
report = compute_held_memory(editor)
report.total_bytes            # the bytes that the editor reaches through strong references
report.holders[1]             # MemoryHolder(".document.windows[1]…navigator.back", Vector{NavigatorVisit}, 412 MiB, 3.1 million objects)
describe_held_memory()        # the same report as text, for the editor of the session
```

## Proposed decisions

Each decision counts as approved when the owner approves the plan.

- **P1. The walk follows strong references only, from the root.** It does not follow
  the value of a `WeakRef`. It does not enter a module, a type, a method or compiled
  code: each of these counts only by its own size. It enters a closure through its
  captured fields, and a `Task` through its fields `code`, `result` and `storage`.
  A kind that the walk does not know counts by its own size, and the report gives
  their total on one line, "not walked". *Rejected:* a heap snapshot of the process
  (`Profile.take_heap_snapshot`). It holds the whole process, names no field of a
  document, and needs a second tool to read it. It stays the fallback if the walk
  costs too much memory in the IDE (risk 1).
- **P2. A holder keeps an object when every path from the root to the object goes
  through the holder.** This is the dominator of the object in the graph of the walk.
  The bytes of a holder are the bytes of the objects that it keeps, so no object
  counts two times, and a growth goes to the store that keeps it. The walk numbers
  the objects, and the dominators come from the iterative algorithm of Cooper, Harvey
  and Kennedy ("A Simple, Fast Dominance Algorithm", 2001). *Rejected:* the first path
  of a breadth-first walk. It names an object as the holder when another path also
  reaches the object, so a removal of that holder can free nothing.
- **P3. The path of a holder uses the words of a reference.** A step is the name of a
  field of a document or an index of a list, as a reference names it: `.navigator.back`,
  `.tabs[2]`. The fields of a cell, such as `value`, give no step. An entry of a `Dict`
  or an `IdDict` gives the step `[#n]`, the place of the entry, with the type of its
  key. The path is the shortest path of the walk to the holder.
- **P4. The report lists each holder that keeps at least 1 MiB or 1 % of the total,
  in order of its bytes, at most 40 lines.** A holder appears only when no holder
  below it keeps nearly all of its bytes (90 %), so a line names the store and not
  each object above it.
- **P5. The cycle of the test is fixed, and it goes through the window.** It runs on a
  headless backend, as the window watch test does
  (`test/projectured/editor/FileWatchWindowTest.jl:11`). The folder of the test holds
  `list.json`, an array of three objects, `other.json`, and two new files for each
  cycle `k`: `page-k.json` and `tab-k.json`. `list.json` shows in a tab for the whole
  test. One cycle has these gestures:
  1. In the tab of `list.json`, insert an element at the start of the array, then
     delete it (store 1).
  2. Open `page-k.json` as the page of the navigator of the explorer (store 2).
  3. Click a value of the page at its pixels, type one character, and save with
     Ctrl+S (store 3 and the undo).
  4. Write a new text of `page-k.json` on disk, and wait until the page shows it. The
     wait has a bound of 10 s, as `_fw_wait_until` has (the old document after a
     reload).
  5. Open `tab-k.json` in a tab of its own, click a value in it, and close the tab
     (store 3, and the undo of the window).
  6. Open `other.json` as the page of the navigator, then go Back. So each cycle adds
     one visit to the Back list (store 2).

  Stores 4 and 5 are not in the cycle. They need a task group and a `file("...")`
  reference, and the report shows them in the IDE.
- **P6. Flat means that no holder grows in both halves of the measurement.** The
  undo capacity of the test is 10 (`HistorySettings.undo_capacity`), so each history
  is full after the warm-up. The test takes three reports, after the full collection
  of `GC.gc(true)`: R0 after 30 cycles, R1 after 130 and R2 after 230. A holder grows
  when its path keeps more than 4 KiB more in R1 than in R0, and again in R2 than in
  R1. A growth that repeats is a store that keeps something in each cycle; a step
  that happens once, such as a table that doubles, does not repeat. The test also
  checks two totals in the second half: the bytes that the editor reaches, and the
  live memory of the process that the editor does not reach (`Base.gc_live_bytes()`
  less the total of the report). Step 3 measures the noise of each total on `main`
  and sets each bound at four times that noise.
- **P7. The known growth is a list of `key => reason` pairs beside the test, as the
  guards keep their known violations.** A key is a part of the path of a holder, such
  as `navigator.back`. A growth that an entry excuses counts as broken
  (`@test_broken`, with its `# @broken:` reason). A growth that no entry excuses
  fails, and so does an entry that excuses no growth. So a fix of a store must remove
  its entry. Each entry is a new marker for a fault that this plan did not make, and
  the approval of this plan is the word of the owner for each one. The report of the
  land names each entry.
- **P8. The test runs the stop steps of its editor at the end**
  (`foreach(step -> step(editor), editor.stop_steps)`, as
  `FileWatchWindowTest.jl:118` does). Without them the editor stays in the worker
  for the life of the process.
- **P9. The report is a new slice of the platform, `source/platform/memory/`, with the
  module `MemoryModule`.** It needs only Base, so it imports no other slice. Its
  design document is `documentation/package/platform/memory/memory.md`. *Rejected:*
  the performance layer of the kernel, whose files are sealed, and which needs no
  report to work. *Rejected:* a tool of the tests only, which the IDE could not run.
- **P10. `describe_held_memory()` is a verb of the assistant.** Its docstring carries
  the mark of the verbs that the system text lists, and it says what a run costs
  (risk 1). The assistant runs it only when the owner asks, because the walk holds
  the editor for its whole time.

## Facts of the code

- The headless window of the application: `_fw_make_window(paths, root)`
  (`test/projectured/editor/FileWatchWindowTest.jl:11`), with `make_settings()`,
  `make_application_document`, `build_editor`, `start_application!`,
  `drain_operations!` and `run_frame!`. The application document has an explorer
  with a navigator (`source/platform/application/Application.jl:144`).
- A gesture: `_fw_press!` (`:31`) pushes `WindowInput` events and draws a frame;
  `_fw_click!` (`:34`) clicks at a point; `_fw_drawn` (`:28`) gives each drawn text
  with its place; `_fw_wait_until` (`:42`) drains the feeds and draws frames until a
  condition holds, with a bound.
- A file in a tab: `open_file!(path; editor)`
  (`source/platform/filesystem/FileSystemDocument.jl:356`). A tab closes by
  `make_pane_close_tab_operation(tree, group, index)`
  (`source/platform/pane/PaneSurgery.jl:674`); no test closes a tab with Ctrl+W.
- A page of a navigator: `make_navigator_open_operation(navigator, address)` and
  `make_navigator_back_operation(navigator)`
  (`source/platform/navigator/NavigatorVisits.jl:176`, `:228`).
- The undo capacity: `get_settings_group!(settings, HistorySettings).undo_capacity`,
  set before `make_application_document`, because a buffer reads it when it is made
  (`test/projectured/editor/ApplicationTest.jl:803`).
- The nearest test of memory: `test/kernel/backend/HeadlessBackendTest.jl:62`, where
  20 paints must keep the growth of `gc_live_bytes` under 4 MiB.
- The test package of the window tests is `ProjecturedTest` (`test/projectured/`):
  `test_window_frame_guards` is in `test/projectured/performance/WindowFrameGuardTest.jl`
  and is listed at `test/projectured/ProjecturedSuite.jl:563`.

## Steps

1. **The walk and the report.** Write the slice `source/platform/memory/`:
   `compute_held_memory(root)`, which gives a `HeldMemory` with `total_bytes`,
   `object_count`, `holders` (a list of `MemoryHolder` with `path`, `type`, `bytes`
   and `object_count`), `types` and `unwalked_bytes`. Add the slice to the platform,
   to the layering guard and to its edges. Test it in `ProjecturedPlatformTest` on
   small graphs: a chain, a diamond (a shared object counts once, under the holder of
   both paths), a weak reference (not followed), a cycle, a closure, and a list of
   structs that hold references. Measure the time and the memory of a walk on the
   editor of step 3 after 30 cycles: the bytes of the walk for each object. If they
   are more than 150 bytes, stop and ask (risk 1).
2. **The verb of the assistant.** Write `describe_held_memory()` with its mark, and
   add a case to `test_assistant_verbs`.
3. **The test of the cycle.** Write `test_editor_memory_cycle` in
   `test/projectured/performance/EditorMemoryCycleTest.jl`, with the cycle of P5 and
   the measurement of P6, and list it in `ProjecturedSuite.jl` as a slow part with a
   time limit of 30 minutes. Run it on the branch, and write each holder that grows
   into the list of P7, with its reason. Record here which stores of the reading grow,
   by how much in each cycle, and which do not.
4. **The documentation.** Write the design document of the slice. Add the section
   "What holds the memory of an editor" to `documentation/guide/debugging-guide.md`,
   and the test of the cycle to `documentation/guide/testing-guide.md`. Add the slice
   to the index of the package documents.
5. **The check before the land.** Run all the parts in the worktree, as "Main is
   green" in `CLAUDE.md` says, and record the calls of `ProjecturedTest` and
   `ProjecturedPlatformTest` after the land. Then ask the owner to land, with the list
   of the new markers.

## Risks

1. **The walk needs memory of its own.** It keeps one entry of an `IdDict` and a few
   `Int32` numbers for each object, and one or two `Int32` numbers for each edge. The
   estimate is about 100 bytes for each object. The editor of a JSON file of 1000
   objects reaches 21 million objects, so a walk of it needs about 2 GB. In the IDE a
   walk can need several GB more than the IDE holds, so the owner decides when it
   runs. Step 1 measures the real number.
2. **Julia has kinds of objects that the walk does not know.** Each one counts by its
   own size, and the line "not walked" shows their total, so a growth there is still
   seen.
3. **The cycle depends on the watch of files.** Gesture 4 waits for a read on another
   task. The wait has a bound, so a slow machine gives a failure with a clear message,
   not a hang.
4. **The live memory of a worker has noise.** Compiled code and the records of the
   tests can grow. Step 3 measures the noise on `main` and sets the bounds from it.

## Not in this plan

- The fixes of the five stores and of the two things that make an item heavier: the
  rule that drops a view, the closed file that keeps only the path of its caret, the
  limit of the Back list, the old value of an invalid cell, and a limit on the size
  of an undo history.
- A run of the report in the IDE. The IDE is the process of the owner.
