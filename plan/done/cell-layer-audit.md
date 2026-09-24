# The audit of the cell layer

The owner asked for a review of the whole shape of the cell layer
(`source/kernel/cell/`) and an audit against the rules in
`documentation/rule/`. The audit found one defect in behavior, dead code, two
loops written twice, comments with history, docstrings that repeat themselves,
and two contract generics that the interface file does not declare. The owner
approved every item on 2026-09-24, gave permission to change the sealed file
`CellInterface.jl`, and chose `has_dependent_cells` as the new name of
`has_dependents`.

The question of `Computed` against `ComputedCell` is a plan of its own:
[computed-cell-spelling.md](computed-cell-spelling.md).

## Decisions

- **`has_dependents` becomes `has_dependent_cells`.** The word for the kind of
  thing goes last, and every other function of the layer names the cell.
- **`_force_thunk` retries only in an older world.** It runs the thunk again
  through `Base.invokelatest` only when the task runs in a world older than the
  latest one. Code inside `invokelatest` runs in the latest world, so a nested
  cell does not retry. Before this, one real `MethodError` at the bottom of a
  chain ran the bottom thunk 2^depth times: 2, 4, 32, 1024 and 32768 runs at
  the depths 1, 2, 5, 10 and 15.
- **`is_computed_cell` and `has_dependent_cells` are contract generics.** Each
  has a method for every kind, so `CellInterface.jl` declares them, and
  `CellDefaults.jl` holds the method of each kind, as it does for `unwrap_cell`
  and `copy_cell_as`.
- **The private names start with a verb.** The field `deps` is
  `dependencies`; `_deps!` is `_get_dependencies!`; `_dependents!` is
  `_get_dependents!`; `_computing_stack` is `_get_computing_stack`;
  `recompute!` is `_recompute!`.
- **One invalidation walk.** `_invalidate_walk!` and `_invalidate_dependents!`
  had the same loop. One recursive `_invalidate_dependents!` remains, so the
  walk still uses one stack frame for each level. The generated precompile
  statement files of three repositories name `_invalidate_walk!`; both kinds of
  file skip an entry that names nothing, so they need no change.

## Steps

- [x] 1. `_force_thunk` retries only in an older world, and two tests cover it:
  a chain with a real `MethodError` runs its bottom thunk once, and a thunk that
  calls a newer method gets its value through the retry.
- [x] 2. The engine: remove `invalidate!`, `is_cell_up_to_date(::Vector{Cell})`
  and `ReactiveCell(value)`; `_recompute!` calls `_detach_upstream!`; one
  invalidation walk; the private names of the decisions above.
- [x] 3. The contract: `CellInterface.jl` declares `is_computed_cell` and
  `has_dependent_cells` and loses the four docstring halves that repeat the
  first half; `CellDefaults.jl` holds the methods of both; `has_dependents`
  becomes `has_dependent_cells` in the code, the tests and the guides;
  `_reject_computation` throws an `ArgumentError`.
- [x] 4. The comments and docstrings of `ReactiveCell.jl`, `CellDefaults.jl` and
  `CellComputed.jl`: no history, no first person, no repeated half, no false
  claim, no line over 90 characters.
- [x] 5. `CellModule.jl`: the docstring in the writing rules, the `using` of
  `PerformanceModule` moved from `ReactiveCell.jl`, and the exports grouped by
  fragment.
- [x] 6. Outside the layer: the guide `cell.md`, the two engine names in
  `architecture-invariants.md`, and the read of the `valid` field in
  `DbCatalogToSyntax.jl`.

## What the implementation found

- The example of `copy_cell_as` in `CellInterface.jl` passed `original.width`,
  which reads the value and not the cell. It passes
  `getfield(original, :width)` now.
- The cell test carried history comments and a link to `plan/pending/` for a
  plan in `plan/done/`. They say what is now.
- The chain test reads inside `Base.invokelatest`. The world of a test task is
  fixed when its top-level call starts, and an earlier test in the same call
  can define methods, so a bare read can run in an older world. In an older
  world, each level of a chain retries once: a chain of ten runs its bottom
  thunk eleven times, where it ran 1024 times before.
- No runnable test covers `_children_realized` in `DbCatalogToSyntax.jl`; the
  DbCatalog syntax tests need an ODBC database. A check by hand gave the same
  answers as before: `false` for a computed element list before its read, and
  `true` after it, for a stored list, and for a value that is not a
  `CellVector`.

## Verification

- `test_cell()`: 83 pass, with the counters compiled out and compiled in.
- `test_performance_counter()`: 3 pass, and 11 with the counters compiled in.
- `test_kernel_layering()`: 10 pass. `test/suite/naming.jl`: clean.
- `test_declared_api()`: 117 pass.
- `test_frame_statistics_feed()`: 41 pass. `test_serialization()`: 56 pass.
  `test_documentation()`: pass. `test_reactive_surface()`: no error.
