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
- [ ] 2. The decisions of the owner, and the fixes, with a test for each.
- [ ] 3. The walkthrough and the full guide.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
