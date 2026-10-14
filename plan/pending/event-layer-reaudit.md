# The re-audit of the event layer

The owner, 2026-10-14, after the seal of the clock layer: "yes, push and go for the
next layer". The event layer, `source/kernel/event/`, is layer 6 of the kernel. It goes
through the audit with four checks (SEALING.md, "The audit protocol").

The folder has eleven files, and the inventory of `SEALING.md` lists all of them, in
the include order of `EventModule.jl`. Three open
questions of the kernel audit of 2026-09-27 name the event layer, L06-7, L06-8 and
L06-11, but they are about the event patterns, which now live in the gesture layer
(`gesture/GesturePattern.jl`). L06-10 and L06-12 are decided.

## The audit

An auditor read the layer on 8cd75496b; the lead confirmed E6-1. All four checks fail;
the code is sound (`test_event_module` 31, the layering guard 10). Architecture: E6-1
(Medium, the docstring of the four modifier predicates attaches to one of them), E6-2
and E6-3 (Medium, docstrings that name or describe layers above), E6-4 to E6-9 (Low and
advice). Tests: E6-10 (`is_move_without_button` and `find_typed_character` have no
direct test), E6-11 (constructor forms that the docstrings promise). Example: E6-12, no
walkthrough. Guide: E6-13, no `event.md`; E6-14, errors in `devices-and-backends.md`.
L06-8 and L06-11 concern only the gesture layer and go to its audit. L06-7 has a new
fact: the four predicates have no caller left.

Questions for the owner (the lead's recommendation in brackets): Q1, drop the backend
names and say "an input source" [yes]; Q2, a `TimerExpire` stays bare, and `:none`
marks an input from a source with no window [keep both, document]; Q3, a `show` method
for `ModifierKeys` that prints the held keys [yes]; L06-7, keep the four predicates
[keep].

## Steps

- [x] 1. The audit: the four checks on the eleven files, the inventory, and the state of
  L06-7, L06-8 and L06-11. The lead confirms each finding in the code.
- [ ] 2. The decisions of the owner, if any, and the fixes, with a test for each.
- [ ] 3. The walkthrough and the guide `documentation/package/kernel/event.md`, if the
  audit asks for them.
- [ ] 4. An audit that finds nothing, then the seal on the owner's word.
