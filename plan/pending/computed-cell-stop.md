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
- [x] **2. The texts.** Decision 10 of `architecture-decisions.md`, the invariant
  `PAR-WRITE-DRIVEN-PROPAGATION`, `cell.md`, the docstrings of `ReactiveCell.jl`,
  the walk of the dirty parts in `SdlBackend.jl` and `sdl.md`, the comments of
  `PrinterLocalityTest.jl` and `DirtyRectTest.jl`, and the cost of a change in
  `roster.md`.
  - Done 2026-10-14. Decision 10 has a new title, "Propagation starts at a write
    and stops at plain data that stays the same", and `cell.md` links to its new
    anchor. `cell.md` names the two new states, the order of the edges, the
    check and the counters `:checks` and `:stops`.
  - The counts in `roster.md` come from the final engine. They are the counts of
    `:always` in the measure, for every scenario: X1 with a roster costs 18
    computations for each key, and a change of the edits of one file of 200
    costs 8.
- [ ] **3. The checks.** The suites of the kernel, the platform, the SDL backend,
  JSON and Julia, and the integration suite. The counts of the six scenarios of
  the measure, which must be the counts of `:always`. The time of the six
  scenarios against `main`, on an idle machine.
- [x] **4. The audit.** The four checks of `SEALING.md` for each changed file of
  the cell layer, reported to the owner, who seals.
  - First audit, 2026-10-14, and what it changed:
    - A defect: the check let an interrupt through before it reset the state
      of its cell, so the cell stayed checking and every later read threw
      `CellCycleException`. And an exception below a chain of k checks made
      about k²/2 computations, against k+1 without the stop. Now a check that
      meets an exception makes its cell invalid and passes the exception up to
      the check that a read started, which makes its cell compute; an exception
      that `is_fault_exception` refuses goes up through every check. The cells
      of the chain compute once, and the cell that threw twice. Two tests pin
      it.
    - The invariants `PAR-MONOTONE-INVALIDATION`, `PAR-ACYCLIC-CELLS` and
      `PAR-PROFILE-WITH-COUNTERS` name the new states, the cycle through a
      check and the two new counts. `PAR-NO-WRITE-IN-THUNK` needs no change.
    - Tests for `:checks` and `:stops` in `PerformanceCounterTest.jl`, for the
      stop after `invalidate_cell!`, and for two older promises of the
      interface: `get_cell_value_type` adds no dependency, and
      `get_cell_computation` of an `ImmutableCell` gives `nothing`.
    - The walkthrough of the cell layer shows the stop, and `cell.md` has an
      example of it and the rules of an exception in a check.
    - `_DEPENDENCY_SCAN` is `_DEPENDENCY_SCAN_LIMIT`.
  - Second audit, 2026-10-14, on 82ee15208: both files pass the four checks.
    Its probes: an interrupt in a check leaves no cell checking; a cell that
    fails below 8 checks makes 10 computations, against 45 before the fix; a
    fault scope records the fault twice in one read, against 4. Two sentences
    of the invariants followed in c24651256: a check and a stop add a count to
    the counter store, and an exception during a check is no stop.
  - `ReactiveCell.jl` and `CellInterface.jl` stay unsealed until the owner
    seals them.
