# The re-audit of the clock layer

The owner, 2026-10-13, after the seal of the struct layer: "land and push, continue
with next layer". The clock layer, `source/kernel/clock/`, is layer 5 of the kernel. It
goes through the audit with four checks (SEALING.md, "The audit protocol").

The layer has two files: `ClockModule.jl` and `Clock.jl`. The same day, 01024a2a9
removed the heartbeat (`start_wall_clock!`, `stop_wall_clock!`), and `make_editor` and
`build_editor` took the keyword `clock`. The layer has no guide of its own, only a
paragraph in `cell.md`, and no walkthrough in `ProjecturedKernelExample`.

The one open question of the kernel audit of 2026-09-27, L05-1 (a heartbeat write
that reaches a computing cell), applies no more: the heartbeat is gone, and the owner
decided L03-2 as B, the single-writer rule.

## Steps

- [ ] 1. The audit: the four checks on the two files. The lead confirms each finding
  in the code.
- [ ] 2. The decisions of the owner, if any, and the fixes, with a test for each.
- [ ] 3. The walkthrough and the guide `documentation/package/kernel/clock.md`.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
