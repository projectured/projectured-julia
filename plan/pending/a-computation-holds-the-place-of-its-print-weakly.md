# A computation holds the place of its print weakly

**Status:** approved by the owner on 2026-11-26 ("Yes", to the question that asked
for the approval and for the permission to change the sealed file
`source/kernel/cell/CellFaultScope.jl`), in work. The owner asked for this plan on
2026-11-26 ("Yes", to the question: a plan for the weak link first, on its own). The work goes in the worktree `projectured-julia-weak-fault-scope`, on
the branch `weak-fault-scope`.

The plan lands nothing and pushes nothing. It ends with a request to land.

**If a step needs a change of another sealed file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

The memory test of the plan "an editor says what holds its memory"
(`test_editor_memory_cycle`) shows that the editor keeps about 7.5 MB more in each
cycle of gestures. Nearly all of it is in the views that a list view keeps for the
elements that it showed (`CellVectorView.kept`): 7.1 MiB for each kept view after 20
cycles.

The cause is the link from a computation to the place in its print:

- A computation keeps the fault scope that held when it was made:
  `_FaultScopedComputation(computation, scope)` (`CellFaultScope.jl:77`), which
  `_capture_fault_scope` (`:146`) makes for `Computation(f)` (`CellComputation.jl:35`)
  and for `set_cell_computation!` (`ReactiveCell.jl:653`). When the computation throws
  a fault, it gives the fault to that scope (`:85`).
- The scope of a print is a fault barrier, a `FaultCatchingIoMap`
  (`source/platform/projection/higherorder/FaultCatching.jl:115`), the IO map of one
  part of the print. Through its enclosing barrier and its inner IO maps, it reaches
  the whole print.
- So a view that the list keeps for later keeps the computations that the print made
  with it, and through them the whole print in which it was made. That print is no
  longer on the screen.
- The link is there because a lazy computation can run in the paint, after the print
  stage, where no scope is set. The link sends its fault to the barrier of the part
  that built it.

**The measurement** (2026-11-26, 20 cycles of the memory test, a probe outside the
repository). In the probe process only, the probe replaced `_capture_fault_scope` with
a version that holds the scope through a `WeakRef`.

| | The editor reaches | Objects | Cells | The process holds | Growth in each later cycle |
|---|---|---|---|---|---|
| Strong link, as on `main` | 213 MiB | 3.94 million | 1.19 million | 565 MiB | about 7.5 MiB |
| Weak link | 68 MiB | 0.41 million | 87 000 | 410 MiB | none in 3 more cycles |

In the probe, 315 102 computations got a weak link and none a strong one, and each
gesture of the cycles passed. A cycle took 0.24 s to 0.28 s with the weak link, and
0.24 s to 0.26 s with the strong one.

## The goal

A computation holds the place in its print weakly. While the print lives, a fault of
the computation goes to its place as now. When nothing else holds the print, the
print goes, and a fault of the computation goes to the code that reads it. The memory
test then shows no growth of the views that a list keeps.

## Proposed decisions

Each decision counts as approved when the owner approves the plan.

- **D1. A scope that is a mutable object is held through a `WeakRef`, and any other
  scope is held as now.** A weak reference to a value that is not mutable, such as a
  symbol or a struct of values, can lose the value at once, because the value has no
  identity. Such a scope holds no print. The struct `_FaultScopedComputation` keeps
  its name, and its field `scope` holds the `WeakRef` or the scope. *Rejected:* one
  `WeakRef` for each scope, kept in the barrier. It needs a field of
  `FaultCatchingIoMap` and a method for each kind of scope. Step 2 measures whether
  one `WeakRef` for each computation costs too much (risk 1).
- **D2. When the scope is gone, the computation runs with no scope.** A fault then
  goes on as an exception to the computation or to the barrier that reads the cell,
  as for a computation that was made outside every scope. Today such a fault goes to
  the barrier of the old print, which is no longer on the screen. *Rejected:* find the
  scope when the computation runs (`find_cell_fault_scope()`). In the paint no scope
  is set, so it gives the same answer. Inside a computation it gives the scope of
  the reader, which the exception reaches anyway.
- **D3. `get_cell_fault_scope(cell)` answers `nothing` when the scope is gone.** Its
  docstring says so.
- **D4. The memory test keeps an entry of `_MC_KNOWN_GROWTH` only while the test shows
  its growth.** The entry `"elements.kept"` goes when the views that a list keeps no
  longer grow, as the rule of the test says.

## Facts of the code

- `CellFaultScope.jl`: `run_in_cell_fault_scope` (`:37`), the struct (`:77`), its call
  (`:85`), `get_cell_fault_scope` (`:113`), `_get_computation_fault_scope` (`:116`,
  `:117`), `find_cell_fault_scope` (`:135`), `_capture_fault_scope` (`:146`). The file
  is sealed (`SEALING.md:145`, layer 3, cell).
- `get_cell_fault_scope` of an untracked cell: `UntrackedCell.jl:55`, through
  `_get_computation_fault_scope`.
- The only code in `source/` that sets a scope is the fault barrier:
  `_print_in_scope(barrier)` (`FaultCatching.jl:201`). The barrier is made in
  `print_document(::FaultCatchingProjection, …)` (`:176`) and is the IO map that the
  print of the part gives, so the IO map of its parent holds it while the part is in
  the print.
- The tests of the fault scope use scopes that are not mutable: `:part` and
  `PartScope([])`, a struct (`test/kernel/cell/CellFaultScopeTest.jl`,
  `test/kernel/cell/CellExampleTest.jl:109`).
- The tests that read where a fault goes: `test_cell_fault_scope`, `test_cell_example`,
  `test_fault_example` (`test/kernel/fault/FaultExampleTest.jl:94`),
  `test_editor_fault_barriers` (`test/kernel/editor/FaultBarriersTest.jl:176`),
  `test_fault_catching` (`test/platform/fault/FaultCatchingTest.jl:129`) and
  `test_fault_part` (`test/platform/fault/FaultPartTest.jl:81`).
- The documents that describe the link: `documentation/package/kernel/cell.md:206` and
  `documentation/package/kernel/fault.md:200`. The example of a report in
  `documentation/guide/debugging-guide.md:444` names the kept views with 449 778 004
  bytes.

## Steps

1. **Done on 2026-11-26.** **The weak link.** In `CellFaultScope.jl`, `_capture_fault_scope` keeps a mutable
   scope through a `WeakRef` (D1). The call of `_FaultScopedComputation` runs the
   computation with no scope when the scope is gone (D2), and
   `_get_computation_fault_scope` answers `nothing` then (D3). Add cases to
   `test_cell_fault_scope`:
   - a computation made in a mutable scope: while the scope lives,
     `get_cell_fault_scope` gives it, and a fault goes to it;
   - after the last other holder of the scope goes and `GC.gc()` runs: the cell does
     not keep the scope (a `WeakRef` of the test is empty), `get_cell_fault_scope`
     gives `nothing`, and a fault of the computation reaches its reader as an
     exception;
   - a scope that is not mutable stays after `GC.gc()`.

   Run the tests of the fault scope and of the barriers that "Facts of the code"
   names, and `test_cell()`.
2. **The memory test and the cost.** Run `test_editor_memory_cycle` on the branch.
   Remove each entry of `_MC_KNOWN_GROWTH` that names no growth, and record here the
   lines that grow and by how much. Record the time of the 60 cycles and the time of
   the collector in them, beside the probe numbers above. If a cycle takes more than
   10 % longer than in the probe on `main`, stop and ask (risk 1).
3. **The documentation.** Say in `cell.md` and in `fault.md` that a computation holds
   a mutable scope weakly, and where a fault goes when the scope is gone. Give the
   example of the report in `debugging-guide.md` the output of the branch.
4. **The audit of `CellFaultScope.jl`.** Run the audit of `SEALING.md` on the changed
   file, and report each check. Checks 3 and 4 run at the last file of the layer,
   `cell/CellDefaults.jl`; the report says whether the change makes the example or the
   guide of the layer wrong. The owner decides on the new seal.
5. **The check before the land.** Run all the parts in the worktree, as "Main is green"
   in `CLAUDE.md` says, and the fast parts of omnet-julia against the branch. Record
   the calls of each test package whose files the land changes, after the land. Then
   ask the owner to land, with the list of the markers that the branch removes.

## What the work found

**Step 1.**

- `_FaultScopedComputation` keeps its two fields. `_get_held_scope` reads the scope
  through the `WeakRef` or as it is. A run reads the scope once at its start, so the
  scope stays while the computation runs.
- `test_cell_fault_scope` passes 52 of 52, five times in one process, so the
  collection in the new cases is stable. `test_cell_example` passes 2 of 2,
  `test_cell` 334 of 334, `test_fault_example` 2 of 2, `test_editor_fault_barriers`
  34 of 34, `test_fault_catching` 53 of 53 and `test_fault_part` 26 of 26.

## Risks

1. **One `WeakRef` for each computation.** The probe made 315 102 in 20 cycles, about
   16 000 in each cycle, and the collector visits each weak reference that lives. The
   probe showed no slower cycle, but it measured no time of the collector. Step 2
   measures it.
2. **A scope that goes while its part is still in the print.** A barrier lives while
   the IO map of its parent holds it. If a computation outlives the barrier while its
   part still shows, its fault goes to its reader and not to its own place. The tests
   of the barriers check where a fault shows.
3. **The memory test can show a new line.** With the large store gone, a smaller line
   can pass the margin of 64 KiB. Step 2 records it; a line that grows in each run
   gets an entry with its reason, and a line that grows only at some times is no
   marker (`CLAUDE.md`, "Main is green").

## Not in this plan

- The release of the computed cells that no paint reads, when the memory passes a
  limit. The owner's design for it is in discussion. It is measured after this plan,
  on a case that it is for, such as a large tab that is not shown.
- The copies of the dispatch table of projections. After the weak link, they are
  about 55 MiB of the 68 MiB that the editor reaches: 9.2 MiB and 24 463 objects each.
  They do not grow in a cycle.
- The other stores of the plan "an editor says what holds its memory": the Back
  list, the files of the folder, the runs of a task and the list of open files.
- The memory of the process that the editor does not reach, about 1.6 MB in each
  cycle on `main`.
