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

## The audit

An auditor read the layer on c7313ab89; the lead confirmed K5-1. All four checks fail.
Architecture: K5-1 (Medium, the docstrings name the editor and its functions, which
PAR-NO-CONSUMER-DOCS forbids; the text came in with 01024a2a9), K5-2 (Low, "each write
invalidates" is false for a write of the same time), K5-3 (Low, `show` drops the quotes
of a string, against its comment), and the advice K5-4 (`time()` in an example), K5-5
(the editor reads the time cell to ask whether the clock has readers), K5-6 (a clock
made from a computation). Tests: K5-7 and K5-8, two promises with no test. Example:
K5-9, no walkthrough. Guide: K5-10, no `clock.md`.

Questions for the owner (the lead's recommendation in brackets): K5-1, the hand-off to
the editor moves from the docstrings to the guide [yes]; K5-3, fix `show` or the comment
[`show`]; K5-5, a new export `has_clock_readers(clock)` [yes]; the walkthrough shows the
hand-off to an editor [no, the guide does].

**The owner, 2026-10-14:** "agreed", to the four recommendations.

## Steps

- [x] 1. The audit: the four checks on the two files. The lead confirms each finding
  in the code.
- [x] 2. The decisions of the owner, if any, and the fixes, with a test for each.
  The docstrings name no layer above (K5-1) and say "a write of a new time" (K5-2);
  `show` shows the time as Julia shows it, so a string keeps its quotes (K5-3); the
  example of `set_clock_time!` uses the monotonic `time_ns` (K5-4); a new export
  `has_clock_readers(clock)`, which `Feeds.jl` asks in place of the time cell (K5-5);
  one sentence on a clock made with a computation (K5-6); tests of the stored
  `Float64`, of `clock.time` as a read that records, of a write of the same time and
  of `has_clock_readers` (K5-7, K5-8).
- [x] 3. The walkthrough and the guide `documentation/package/kernel/clock.md`.
  `print_clock_example()` with its exact-text test, and the guide, which `cell.md`,
  `editor.md`, `architecture.md` and the index link. Checked: `test_clock` 39,
  `test_build_editor` 37, the walkthrough 2, the kernel suite 4520 of 4520, the survey
  of `ClockModule` clean, the guards.
- [x] 4. An audit that finds nothing, then the seal on the owner's word. **The owner,
  2026-10-14:** "yes", to the seal and to the push.
  - The second pass found K5-11: the docstring of `has_clock_readers` advised a
    writer to skip the write while nothing reads the clock, which gives stale reads
    (the owner rejected that pattern on 2026-09-25). It now says that the answer
    chooses how long a writer may wait, and that the writer still writes the time
    each time it runs. The advice: a freed reader counts until the collector frees
    it; the guide names the next timer; a comment of the walkthrough. Checked:
    `test_clock` 39, the walkthrough 2, `test_editor_wait` 25, the layering guard.
  - The final check of the auditor: the four checks pass, and no finding is left.
