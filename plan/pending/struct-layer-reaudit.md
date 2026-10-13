# The re-audit of the struct layer

The owner, 2026-10-13, after the seal of the cell layer: "let's go for the next layer".
The struct layer, `source/kernel/struct/`, is layer 4 of the kernel. It goes through the
audit with four checks (SEALING.md, "The audit protocol"). The owner, the same day:
"the struct guide will be done with the struct layer sealing".

The layer has three files: `CellStructModule.jl`, `CellStructPlan.jl` and
`CellStruct.jl`. Its guide is `documentation/package/kernel/struct.md`, which holds only
the section that moved out of `cell.md` (24b553cad). It has no walkthrough in
`ProjecturedKernelExample`. Five decisions of the kernel audit of 2026-09-27 are open
for it: L04-2 to L04-6 (`kernel-audit-fixes.md`).

## The audit

An auditor read the layer on 22723b1ba; the lead confirmed S4-1 and S4-2 in the code.
All four checks fail. Architecture: S4-1 (Medium, `build_cell_struct_exprs` changes its
argument), S4-2 (Medium, no builder takes a plan, so a field that
`add_cell_struct_field!` adds loses its type and its default), S4-3 … S4-7 (Low, texts
that the code does not keep), S4-8 … S4-10 (advice). Tests: S4-11 (three exports with
no test), S4-12 (seven promises with no test). Example: no walkthrough. Guide: S4-13.

**The owner, 2026-10-13:** "point 1: agreed / point 2: agreed / point 3: agreed, keep
them". So L04-2 A (the setter refuses a cell as a value), L04-3 C (a `Computation` and
a cell of `Any` give a type parameter its declared bound), L04-4 B (texts only), L04-5
B (only `@document` applies Rule Y), L04-6 A (the generated methods point to the
declaration, with a keyword `source`); S4-2: `build_cell_struct_exprs(plan; default)`,
and the method for a definition works on a copy (S4-1); S4-10: the three `get_` names
stay.

## Steps

- [x] 1. The audit: the four checks on the three files, and the state of L04-2 to L04-6
  on the current code. The lead confirms each finding in the code.
- [x] 2. The decisions of the owner, and the fixes, with a test for each.
  - Both methods of `build_cell_struct_exprs` work on a copy and call a private
    `_build_cell_struct_exprs!`; the generated block ends with `nothing`, as a
    `struct` definition does (S4-1, S4-2).
  - The setter refuses a cell with an `ArgumentError` (L04-2). The setter of
    `@document` has a private refusal of its own, so the check adds no export.
  - `get_cell_struct_parameter_bounds(plan)` is a new export, and
    `get_cell_struct_argument_type(argument, bound = Any)` gives `bound` for a
    `Computation` and for a cell of `Any`. The inferring constructors of
    `@cell_struct` and `@document` pass the bound (L04-3). A bound that names
    another parameter gives `Any`.
  - L04-4: texts in `DocumentInterface.jl`, `DocumentSync.jl` and `ListNode.jl`; the
    test of a record of mixed kinds exists already (`ContractMixedKinds`).
  - L04-5: `macros.md` and the docstring of the positional builder.
  - L04-6: the keyword `source`; `@cell_struct`, `@iomap` and `@projection` pass
    `__source__`. `@document` does not call `build_cell_struct_exprs`.
  - The texts of S4-3 … S4-9, and PAR-NO-NESTED-CELL. Each new test set of a fix
    fails on the code before it (checked in a worktree at f8f42d393).
- [x] 3. The walkthrough and the full guide. `print_cell_struct_example()` with its
  exact-text test; `struct.md` in full. Checked: `test_cell_struct` 96,
  `test_cell_struct_plan` 69, the walkthrough 2, the kernel suite 4504 of 4504, the
  survey of `CellStructModule` clean, the documentation guard.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
  - The second pass found R-1 (a comment promised `Point(1)`, which no Rule Y
    makes), R-2 (the plan form with a `source` wrote the line nodes of the default
    expressions that the copy shared with the caller), R-3 (a fragment header), and
    the advice R-4 (`Real>:A>:Int` gave the lower bound), R-5 (a long line) and R-6
    (`_is_naming_any_of` is `_mentions_any_name`). All six are fixed, R-2 and R-4
    with a test. Checked: `test_cell_struct` 96, `test_cell_struct_plan` 72, the
    walkthrough 2, the layering guard 10.
  - The final check of the auditor: the four checks pass, and no finding is left.
  - Each suite in its own process: the kernel suite 4504 of 4504, and every other
    suite with the failure places of the baseline. `test_integration` reached its
    60-minute bound, because the six fixes landed during the run and each later
    suite compiled the packages again. Run part by part, it ended in 48 minutes
    with the known failures, and one more: `test_evaluator_duplicate`, because the
    Julia parser keeps comments since 948779e3a of another session. A scan of the
    three repositories found no write of a cell through a setter.
