# An editor says what holds its memory

**Status:** approved by the owner on 2026-11-25 ("I approve the plan"), in work. The
owner asked for this plan on 2026-11-25 ("yes, write the plan for step 1"). The work
goes in the worktree `projectured-julia-held-memory`, on the branch `held-memory`. The
owner asked that the measurement of step 3 waits until the machine is idle.

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

1. **Done on 2026-11-25, and the measurement on the editor on 2026-11-26: 121 bytes for each object.**
   **The walk and the report.** Write the slice `source/platform/memory/`:
   `compute_held_memory(root)`, which gives a `HeldMemory` with `total_bytes`,
   `object_count`, `holders` (a list of `MemoryHolder` with `path`, `type`, `bytes`
   and `object_count`), `types` and `unwalked_bytes`. Add the slice to the platform,
   to the layering guard and to its edges. Test it in `ProjecturedPlatformTest` on
   small graphs: a chain, a diamond (a shared object counts once, under the holder of
   both paths), a weak reference (not followed), a cycle, a closure, and a list of
   structs that hold references. Measure the time and the memory of a walk on the
   editor of step 3 after 30 cycles: the bytes of the walk for each object. If they
   are more than 150 bytes, stop and ask (risk 1).
2. **Done on 2026-11-26.** **The verb of the assistant.** Write `describe_held_memory()` with its mark, and
   add a case to `test_assistant_verbs`.
3. **Done on 2026-11-26, with 60 cycles in place of 230 (see "What the work found").**
   **The test of the cycle.** Write `test_editor_memory_cycle` in
   `test/projectured/performance/EditorMemoryCycleTest.jl`, with the cycle of P5 and
   the measurement of P6, and list it in `ProjecturedSuite.jl` as a slow part with a
   time limit of 30 minutes. Run it on the branch, and write each holder that grows
   into the list of P7, with its reason. Record here which stores of the reading grow,
   by how much in each cycle, and which do not.
4. **Done on 2026-11-26.** **The documentation.** Write the design document of the slice. Add the section
   "What holds the memory of an editor" to `documentation/guide/debugging-guide.md`,
   and the test of the cycle to `documentation/guide/testing-guide.md`. Add the slice
   to the index of the package documents.
5. **The check before the land.** Run all the parts in the worktree, as "Main is
   green" in `CLAUDE.md` says, and record the calls of `ProjecturedTest` and
   `ProjecturedPlatformTest` after the land. Then ask the owner to land, with the list
   of the new markers.

## What the work found

Facts and decisions of the work, in the order of the steps.

**Step 1.**

- The slice uses three modules of the kernel, and no other slice: `CellModule`,
  because a field of a cell gives no step; `AgentModule` and `ToolModule`, for
  `run_on_editor_task!` and `get_evaluation_editor` of the verb. P9 said "only Base";
  the kernel is below every slice, so the edge table of the slice stays empty.
- The walk follows each pointer of an object as `Base.summarysize` does
  (`Base.datatype_npointers`, `Base.get_nth_pointer`), so it reads every kind of
  object. So "not walked" (`unwalked_bytes`) holds the bytes of the objects that the
  walk does not walk into by rule: modules, types, methods and compiled code. Julia
  gives no size of a module, so a module counts no bytes.
- A step of the path is the name of the field of each struct, with no rule for one
  kind of list: an element of a `CellVector` is `.elements[3]`, not `[3]` as a
  reference names it. The walk reads no document interface, so it can not make a
  view or read a cell. Also hidden: a step into a `Core.Box` of a captured variable,
  and into the memory of a list or of a dictionary.
- The memory of the elements of a list or of a dictionary is a part of its owner.
  Without that rule, each line named a `Memory{T}` and not the list that owns it.
- P3 changed: an entry of a dictionary whose key is an object gives the type of the
  key with a mark of the identity of the key, `[#3fa91c FileView]`, and not the place
  of the entry. The first run of three cycles showed the path
  `.session_documents[#15 DataType].counts[#18 FileView]…`: the place of an entry
  changes when the table grows, so a holder below it gets a new path in each report,
  and the test could not compare the reports. A key that is a type shows the type.
- A path reuses the path of the object before it, and a memory of more than 32
  elements gets a table of the places of its elements once. Without that, the
  report of an editor of 1.9 million objects took 35 s and allocated 1362 bytes for
  each object, because each of 2000 paths searched large lists again from the root.
- The holder rule "at least 1 MiB or 1 %" lists a holder above the smaller of the
  two. The test lists by bytes only with `minimum_share = 1`.
- The cost of the walk on a graph of 5.0 million small objects (cells, structs and
  lists of 3 trees of depth 9), in one process with no editor: the tables need
  85.8 bytes for each object at their largest, and the walk allocates 253 bytes for
  each object in all, because each table doubles as it grows. The walk takes 4.8 s,
  of which 0.8 s is the collector. The plan bound of 150 bytes for each object holds.
- The cost on the editor of the cycle after 3 cycles (1.93 million objects, 10.7
  million edges, 130 MiB that the editor reaches), measured on 2026-11-26 with one
  other job on the machine: a second report takes 4.9 s, of which the walk takes
  2.0 s and the dominators 0.9 s. The tables need 120.6 bytes for each object at
  their largest, under the bound of 150; the report allocates 371.6 bytes for each
  object in all. The first report of a process takes 29.8 s, of which 23.8 s
  compiles the code of the walk, because no image holds it yet.
- The first report of the cycle names a store that the reading did not find: each
  view of an element of `list.json` keeps 16.2 MiB, about 400 000 objects. The path
  goes from the view of the element (`….elements.kept[#… JsonObject].view`) through
  the cell of its list of entries (`.entries.viewed`) to the fault scope of the
  computation of that cell (`.scope`, a `_FaultScopedComputation`), and from there
  to the IO map of the print in which the view was made
  (`.enclosing.enclosing… FaultCatchingIoMap`). So a view that a print makes keeps
  that print. It also shows the dispatch table of a projection, 9.2 MiB and 24 463
  objects, five times, each under a holder of its own.
- `test_held_memory()` passes 40 of 40 (44 of 44 after the checks of step 3), and the layering guard and the edge guard of
  the platform pass with the broken counts of their lists. The static guards
  `test/suite/documentation.jl` and `test/suite/exports.jl` fail on main too, with 2
  links to a plan that moved and 1 export order in `GestureModule.jl`; the branch adds
  no fault to them.
- The precompile of `ProjecturedPlatform` says that 1626 of its 13543 recorded calls no
  longer resolve. Runs on the code of main say 1599, so the list of main is stale, and
  the branch adds 27. The record of the calls after the land must also record the list
  of `ProjecturedPlatform`.

**Step 3.**

- The folder of the test holds the files of all the cycles from the start, so the
  folder that the explorer lists does not grow in the cycle.
- The folder reads its entries only when a part shows them, as when a person opens
  its row. The test opens the page of the folder once, and waits until it lists all
  the files.
- Back is a press and a release of the side button of the mouse on the page, which
  the navigator binds (`MouseClickPattern(:back)`). A test that also sends the click
  goes back two visits, because the window makes a click of the press and the
  release. The click waits for a second click, so the page shows in a later frame.
- **P5 and P6 changed, and the owner must confirm it: the cycle runs 60 times, and
  the reports are after cycle 20, 40 and 60.** The first run of 230 cycles stopped at
  its cap of 12 GB after the second report. The editor reached 630 MB in 13.5
  million objects after cycle 30, and 2.46 GB in 56.3 million objects after cycle
  130: about 18 MB more in each cycle. At cycle 230 it would reach about 4.3 GB, and
  the walk would need about 9 GB of tables, more than a part of the suite has. A half
  of 20 cycles with the margin of 4 KiB still finds a store that keeps 205 bytes or
  more in each cycle; a document, a view or a visit is larger. When the fixes make
  the cycle flat, the count can grow again.
- The report after cycle 130 took 120 s for 56.3 million objects, with 91.8 bytes of
  tables for each object.
- The message log of the process keeps its last 1000 lines, and each frame that
  evaluates an operation logs a line, so the log was full only after about 50 cycles
  and grew in both halves. The test sets its capacity to 100 for its time, as it
  sets the undo capacity, and puts the old capacity back.
- **P6 changed: the repeat rule is exact, and the check of the total that the
  editor reaches is the line of the root.** A holder grows when the gain that the
  growing holders below it do not explain is more than the margin in each half, and
  neither half gains more than four times the other. Without the second part, the
  window undo (7 KB, then 576 KB) and three old views of elements (6.4 MB, then
  6 KB) counted as stores. The root takes the growth of the reached bytes that no
  listed holder explains, so a separate bound on the reached total says nothing
  more; its noise between two reports in a row is 45 bytes. The live memory of the
  process that the editor does not reach is the line `(unreached)`, with a margin of
  4 MiB: four times its noise of 0.8 MB between two reports in a row.
- **The margin of a holder is 64 KiB in each half, about 3.3 KB in each cycle, not
  4 KiB.** With 4 KiB small lines grow in some runs and not in others, and a check
  that fails only at some times gets no marker. Two kinds showed:
  - The list of the files of the folder of the explorer (store 3) gains 20 KB to
    131 KB in a half. Its line moves between
    `….counts[#… FileSystemDirectory].key.elements.elements` and
    `….counts[#… WorkspaceFolder].key.directory` from run to run; one run of four
    showed neither.
  - Each of the four sides of the margin of a window projection,
    `….opened_window_projections[2].second.margin.computation.value.top` and the
    three others, gains 37 KB in the first half and 15 KB in the second.
- **The known growth of the root also names the lines of the folder (step 5).** The
  first run of all parts failed on the line of the folder: 84 KB, then 131 KB,
  above the margin of 64 KiB. A probe after 3 and 6 cycles showed why the line
  moves. Each `FileSystemFile` of the folder keeps 40 bytes alone, and the root
  keeps its cells, about 1 KB to 2 KB for each file that a cycle opened, because a
  second path reaches them. In some runs the folder keeps a part of them alone. So
  store 3 moves between the root and the line of the folder, and the entry of the
  root is a pattern of the three lines. The entry is in use in each run, because the
  root gains 0.86 MB to 1.9 MB in each half. *Rejected:* a larger margin, because
  the gain of the folder is not bounded by a number that the runs show; and an
  entry of its own for store 3, because it names no growth in the runs where the
  root keeps the cells, so it fails only at some times.
- The lines of the runs of 60 cycles on main, the same in four runs:

  | Line | Gain in the first half | Gain in the second half | In each cycle |
  |---|---|---|---|
  | `….counts[#… FileView].key.content.content.elements.kept`, store 1 | 127.5 MB | 149.9 MB | about 7.5 MB |
  | `(unreached)` | 32.1 to 32.3 MB | 32.3 MB | about 1.6 MB |
  | `(the root)` | 0.86 to 1.02 MB | 1.08 to 1.16 MB | about 50 KB |

  With the margin of 64 KiB the root also takes the folder: 1.27 MB, then 1.75 MB.
  The test then passes with 3 broken, one for each line.
- `test_assistant_verbs()` passes 128 of 128 with the case of the report.

  The editor reaches 224 MB after cycle 20, 375 MB after cycle 40 and 527 MB after
  cycle 60; the live memory of the process is 594 MB, 778 MB and 962 MB. In the
  second half the objects that gain the most bytes are `Cell` (44 MB),
  `Memory{_Dependency}` (32 MB), `Memory{WeakRef}` (22 MB), `Vector{WeakRef}`
  (10 MB) and `WeakRef` (6 MB): the cells of the prints that the kept views hold.
- Store 2, the Back list, shows no line of its own, and store 3 shows only as the
  small line of the folder above. The probable reason, not checked: a page that both
  the Back list and a file of the folder keep belongs to neither of them, but to the
  nearest object above both, because a removal of one of the two frees nothing. So
  these stores are a part of the line of the root. A report of the navigator alone,
  `compute_held_memory(navigator)`, can check it.

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
