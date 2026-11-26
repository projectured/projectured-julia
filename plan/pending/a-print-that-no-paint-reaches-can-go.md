# A print that no paint reaches can go

**Status:** proposed on 2026-11-26, and it waits for the approval of the owner. The
owner asked for this plan on 2026-11-26 ("yes", to the question: write the plan that
brings the printers under the rule, starting with the selection and the pointer
target, which hold the hidden tab). The work goes in the worktree
`projectured-julia-print-in-a-cell`, on the branch `print-in-a-cell`.

The plan lands nothing and pushes nothing. It ends with a request to land.

**If a step needs a change of a sealed file, or a mechanism that this plan does not
name, the work stops and the session asks.**

## The problem

The owner's design for memory (2026-11-26, in discussion): when the memory of the
editor passes a limit, release each cell that no paint needs. The live cells are the
cells that the paint of the last print read, and each cell that a live computed cell
read. Every other cell that is not written directly gives up its value and computes
again when something reads it.

A measurement on a tab that is not shown (2026-11-26, probes outside the repository,
on `main` at `68fcf14a3`, which has the weak link of the plan "a computation holds
the place of its print weakly"). A JSON file of 300 objects (20 KB) shows in a tab of
its own, then another tab shows:

| | The editor reaches |
|---|---|
| The large tab shows | 348 MiB |
| Another tab shows | 348 MiB: the hidden tab keeps its print, 282 MiB |
| After the release of the owner's rule | 336 MiB: the release frees 12.5 MiB |
| After the release, and with each computation of a cell that is not live cut | 55 MiB |
| After a close of the large tab | 66 MiB |

- The release frees 4 % of the hidden tab, and the switch back to the tab then takes
  1.2 s to 1.9 s in place of 35 ms to 86 ms: about as long as a print of the tab
  from the start after a close, 1.3 s to 1.5 s. With 1000 objects, the hidden tab
  keeps 939 MiB, and the times are 4.8 s to 5.7 s.
- The cut shows what holds the rest: the computations of cells that are not live.
  With no such computation, the print of the hidden tab goes, and the editor reaches
  less than after a close. Plain fields and written cells do not keep it.
- Each printed part has a selection and a part under the pointer, two computed
  cells. Each of their computations maps a path through an IO map, so it holds that
  IO map in its closure. The print of the hidden tab hangs on such a closure: the
  path of the holder is
  `….build[13].cell.bounds[19].cell[4].cell.inner`.

**The rule (owner, 2026-11-26: "agreed").** A printer keeps the print of a part only
as the value of a cell, never inside the closure of a computation. Then the release,
with the owner's rule unchanged, frees each part that no paint reaches, and it knows
nothing of tabs. The owner rejected a release that treats a tab in a special way
("that looks weird to me").

## The goal

1. **A test of a hidden part.** A test hides a large tab, applies the owner's rule,
   and checks that the editor reaches no more than after a close of the tab. The
   tab then shows again, with its rows.
2. **A guard of closures.** In the same window, no closure holds an IO map, except
   the known ones of a list beside the guard, each with its reason. A fix of a
   printer removes its entry.
3. **The printers that the guard names keep each print of a part in a cell,** and
   their computations read it through the cell, so both checks pass.

## Proposed decisions

Each decision counts as approved when the owner approves the plan.

- **D1. The rule is the owner's,** as "The problem" states it.
- **D2. The cell of the print of a part is a computed cell that prints the part.** A
  read of it prints the part when it holds no value, so the release can clear it,
  and the part prints again when a paint reads it. A written cell keeps its value,
  so it can not hold the print of a part for the release.
- **D3. The rule is about what is outside the print of a part.** Inside the print of
  a part, its objects hold each other as they do now: they go with the part. A
  computation outside the print of a part reaches that print only through the cell
  of the print. So a closure that captures the IO map of another part captures the
  cell of that print, and reads the cell when it runs.
- **D4. The release in the tests is a helper of the test package,** with the owner's
  rule: the live cells from a paint of the last print, and the values of all other
  computed cells cleared. It uses the cell engine as the probes did
  (`_invalidate_dependents!`, `_detach_upstream!`). *Rejected:* a release in the
  kernel now. The plan of the release at a limit decides its trigger, its search on
  another thread and its clear on the thread of the editor, and it moves the helper
  into the kernel.
- **D5. The guard counts each closure that points to an IO map,** directly or through
  the box of a captured variable, in the window of the test after the release. A
  kind of closure is the function that made it, with its file and line. A closure
  that holds a list of cells that hold IO maps is not counted: when those cells keep
  their prints in cells, the list holds nothing large.
- **D6. The scenario of the test is the JSON tab of the measurement.** Other kinds of
  files print through other printers; step 1 measures a Julia file and a Markdown
  file in a hidden tab, records what holds them, and this plan changes no printer
  for them.

## Facts of the code

- The closures that hold an IO map in the window with the hidden JSON tab
  (2026-11-26, the probe of closures; a count of closures of each kind):

  | What the closure does | Where it is made | Count |
  |---|---|---|
  | Maps the selection of a part | `_get_output_path_computations`, `source/kernel/projection/OutputPaths.jl:56` | 6642 |
  | Maps the part under the pointer | the same, `:59` | 6642 |
  | Gives the output children of a view | `_make_output_children`, `source/platform/projection/higherorder/Viewing.jl:683` | 1808 |
  | Gives the output of a template print | `_atomic_print`, `source/kernel/projection/ProjectionTemplate.jl:476` | 1506 |
  | Makes the elements of a list | `CellVector`, `source/platform/collection/CellVector.jl:202` | 7 |
  | The print of the window: undo, gesture log, references | `print_document` of `ProjectionAlgebraModule` | 5 |
  | The print of a widget | `print_document` of `WidgetModule` | 3 |

- The selection and the pointer target take a function `map_forward` from their
  caller (`make_output_path_cells`, `set_output_path_computations!`), and the
  computation holds that function. Most callers pass
  `path -> map_reference_forward(p, iomap, path)`, which holds an IO map. There are
  157 calls in `source/`.
- The template engine already holds the IO map of a node through a cell
  (`_make_node_path_cells(p, doc, iomap_cell)`, `ProjectionTemplate.jl:462`), but the
  print writes that cell after it makes the IO map, so it is a written cell (D2).
- A list of child prints already has a computed cell
  (`make_reconciled_child_iomaps_cell`), and the layouts print their children in a
  computed cell `build` (`source/platform/layout/LayoutToGraphics.jl:1288`, `:1598`).
- `OutputPaths.jl`, `ProjectionTemplate.jl` and `ReactiveCell.jl` are not sealed
  (`SEALING.md:143`, `:248`, `:251`). The platform files are not in the inventory.
- The probes are in the scratchpad of the session: `probe-hidden-tab.jl`,
  `probe-closures.jl` and `probe-cut.jl`.

## Steps

1. **The test and the guard.** Write `test_hidden_part_memory` in
   `test/projectured/performance/HiddenPartMemoryTest.jl`, a slow part of
   `ProjecturedTest`, with the helper of the release (D4) and the guard of closures
   (D5). The test of the hidden part is `@test_broken` with a `# @broken:` reason
   that names this plan, and the list of the guard holds the 7 kinds above. Measure a
   Julia file and a Markdown file in a hidden tab, and record here what holds each
   one (D6).
2. **The selection and the pointer target.** Each caller whose `map_forward` holds
   the IO map of another part reads it through the cell of that print. Where a parent
   holds the print of a part in no cell, it prints the part in a computed cell (D2,
   D3). Remove the two kinds from the list of the guard, and record which callers
   changed.
3. **The other kinds that the guard names:** the output children of a view, the
   template print with its written cell, the elements of a list, the print of the
   window and the print of a widget. Remove each kind from the list. When the list is
   empty, the test of the hidden part becomes `@test`.
4. **The memory test and the documentation.** Run `test_editor_memory_cycle` and
   update its known growths if a line changed. Add the rule to
   `documentation/rule/architecture-invariants.md`, and describe it in the guide of
   the projection system, with the test and the guard.
5. **The check before the land.** Run all the parts in the worktree, as "Main is
   green" in `CLAUDE.md` says, and the fast parts of omnet-julia against the branch.
   Record the calls of each test package whose files the land changes, after the
   land. Then ask the owner to land, with the list of the markers.

## Risks

1. **The work can grow past the steps.** 157 calls take a `map_forward`, and about 108
   fields of IO map types hold an IO map. The plan changes only what the guard names
   in its window. If a step needs more, it records the rest here and asks.
2. **A part prints later.** A part that prints in a computed cell prints when a read
   needs it, not when its parent prints. A print that has an effect, such as the
   acquire of a document or the count of its holders, then runs inside a
   computation. The tests of the printers, the readers and the navigation of the
   examples check that the effect still happens.
3. **The switch back costs a print.** After the release, a hidden part prints again
   when it shows: 1.3 s to 1.5 s for 300 objects. That is the cost that goal B of the
   owner accepts, at a limit. The plan of the release decides when it runs.
4. **A cycle of cells.** The selection of the output of a part reads the cell of the
   print of that part, whose value holds that output. A read of the selection while
   the cell computes is a cycle. The template engine avoids it today with its written
   cell; step 3 keeps that order with a computed cell.

## Not in this plan

- The release at a limit: its trigger, the order of the cells by their age, the
  search on another thread and the clear on the thread of the editor. It is the next
  plan, and it moves the helper of the release into the kernel.
- A print of only the rows that are on the screen. A tab prints every row today,
  about 0.94 MB for each object of the JSON file.
- The copies of the dispatch table of projections, about 55 MiB of each editor.
- The cost of a large folder in the explorer: 462 files make a cycle of the memory
  test about 50 % slower than 122 files.
- The printers of other kinds of files (D6).
