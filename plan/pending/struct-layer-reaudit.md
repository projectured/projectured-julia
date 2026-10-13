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

## Steps

- [ ] 1. The audit: the four checks on the three files, and the state of L04-2 to L04-6
  on the current code. The lead confirms each finding in the code.
- [ ] 2. The decisions of the owner, and the fixes, with a test for each.
- [ ] 3. The walkthrough and the full guide.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
