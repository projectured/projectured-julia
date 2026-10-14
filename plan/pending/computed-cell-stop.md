# A stop for a computed cell

The cell engine stops a write of plain data that is `===` to the value of a cell
with no computation. This plan gives a computed cell the same stop: a computation
that gives plain data `===` to the value that it had leaves its readers as they
were. The measure in `plan/done/computed-cell-stop-measure.md` found that the
stop changes no result of any suite, costs at most 0.02 ms in a step, and makes
the step of a roster of 200 rows three times faster, with one cell painted in
place of the whole pane. The owner agreed to a stop for every computed cell, and
allowed the change of the sealed cell layer, on 2026-10-14.

## The engine

The engine keeps the algorithm of the experiment:

1. A write marks the direct readers of the written cell invalid, and every
   valid cell below them "maybe invalid". A failed cell stays failed.
2. A read of a "maybe invalid" cell brings its dependencies up to date in the
   order that the last run read them, and stops at the first one that computed
   a new value: that one made the cell invalid, and the cell computes. If none
   did, the cell is valid with no computation. A cell is "checking" while it
   checks, and a read of a checking cell is a cycle.
3. A computation that gives plain data `===` to the value that the cell had
   leaves its readers. Any other value, and a failure, makes the readers that
   wait for a check invalid.
4. An exception of a dependency during a check makes the reader compute, so
   that the computation of the reader meets the exception.
5. `set_cell_computation!`, `invalidate_cell!` and a write still make the
   direct readers invalid.

It changes the storage of the experiment. `dependencies` is a `Vector` in the
order of the first read, with no field beside it: a read pushes a cell that is
not the last one, and the end of a computation removes the repeats. There is no
switch and no hook. The counters `:checks` and `:stops` count the checks and the
computations that gave the value that they had, and `:invalidations` counts both
marks.

The architecture invariant `PAR-WRITE-DRIVEN-PROPAGATION` keeps its name:
propagation still starts at a write and at no other place. Its rule and its line
in the table change.

## Steps

- [x] **1. The engine.** `ReactiveCell.jl` as above. The rules of the stop are
  tests in `CellTest.jl`. `SEALING.md` marks each changed file of the cell layer
  unsealed.
  - Done 2026-10-14. The end of a run removes repeats by a scan up to 32
    dependencies and with an `IdSet` past that. A read registers the reader only
    when it puts a cell in the list.
  - `CellInterface.jl` changed too: the docstring of `is_cell_valid` says that a
    cell that is not valid can become valid by a check, and the one of
    `invalidate_cell!` says that the cells below the readers are maybe invalid.
    `SEALING.md` marks `ReactiveCell.jl` and `CellInterface.jl` unsealed;
    `CellModule.jl` stays true and sealed.
  - A mark of a cell that waits for a check, when a dependency gives a new
    value, is not counted again: the walk of the write counted it.
  - `test_cell` has 8 new testsets and passes, 261 tests; `test_untracked_cell`,
    `test_cell_fault_scope` and `test_cell_example` pass.
- [ ] **2. The texts.** Decision 10 of `architecture-decisions.md`, the invariant
  `PAR-WRITE-DRIVEN-PROPAGATION`, `cell.md`, the docstrings of `ReactiveCell.jl`,
  the walk of the dirty parts in `SdlBackend.jl` and `sdl.md`, the comments of
  `PrinterLocalityTest.jl` and `DirtyRectTest.jl`, and the cost of a change in
  `roster.md`.
- [ ] **3. The checks.** The suites of the kernel, the platform, the SDL backend,
  JSON and Julia, and the integration suite. The counts of the six scenarios of
  the measure, which must be the counts of `:always`. The time of the six
  scenarios against `main`, on an idle machine.
- [ ] **4. The audit.** The four checks of `SEALING.md` for each changed file of
  the cell layer, reported to the owner, who seals.
