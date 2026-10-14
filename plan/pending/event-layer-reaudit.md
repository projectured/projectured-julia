# The re-audit of the event layer

The owner, 2026-10-14, after the seal of the clock layer: "yes, push and go for the
next layer". The event layer, `source/kernel/event/`, is layer 6 of the kernel. It goes
through the audit with four checks (SEALING.md, "The audit protocol").

The folder has eleven files, and the inventory of `SEALING.md` lists eight of them:
`EventDefaults.jl`, `SystemEvent.jl` and `WindowInput.jl` are missing. Three open
questions of the kernel audit of 2026-09-27 name the event layer, L06-7, L06-8 and
L06-11, but they are about the event patterns, which now live in the gesture layer
(`gesture/GesturePattern.jl`). L06-10 and L06-12 are decided.

## Steps

- [ ] 1. The audit: the four checks on the eleven files, the inventory, and the state of
  L06-7, L06-8 and L06-11. The lead confirms each finding in the code.
- [ ] 2. The decisions of the owner, if any, and the fixes, with a test for each.
- [ ] 3. The walkthrough and the guide `documentation/package/kernel/event.md`, if the
  audit asks for them.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
