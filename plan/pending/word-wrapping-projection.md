# Word wrapping — remaining work

> **Status (2026-08-12): IN PROGRESS.** All three "remaining tests" below are
> still not written, and the soft/hard newline distinction is still not
> built. The adjacent `LineNumbering` fix is done, but its wiring into the
> Julia example chain was removed for a different, unrelated reason since
> the last check — see that section below. Paths are updated for the current
> per-domain package layout.

The structural refactor (extracting wrap out of `TextToGraphics` into a
context-aware `WordWrapping` with a bidirectional mapping table) is done —
see [plan/done/word-wrapping-projection.md](../done/word-wrapping-projection.md).
What follows are the items the original plan called for that are not yet
landed.

## Remaining tests (§6 of the original plan)

Existing coverage in
[`package/substrate/test/projection/WordWrappingTest.jl`](../../test/substrate/projection/WordWrappingTest.jl)
covers character preservation, no-wrap, selection round-trip, and the
maximum width from the context. Still to add:

### 1. Wrap parity ⏳

**⏳ OPEN (re-verified 2026-08-12):** No parity/snapshot test exists. `package/substrate/test/projection/WordWrappingTest.jl` contains no comparison against captured pre-refactor `GraphicsText` x/y or `canvas_w/h` output (no `parity`/`snapshot` references found).

For a corpus of spans + a given `max_width`, assert the visual line breaks
produced by `WordWrapping`+`TextToGraphics` match the pre-refactor output
(captured snapshot of `GraphicsText` x/y, `canvas_w/h`). Useful as a
regression net while we still remember the old behaviour. The fixture
files would live alongside the test.

### 2. Reactivity / incremental invalidation ⏳

**⏳ OPEN (re-verified 2026-08-12):** No performance-counter-based invalidation
test exists in `package/substrate/test/projection/WordWrappingTest.jl`. Note the
API this item should use has itself been renamed since the plan was written:
there is no bare `perf_counters()` function any more — the current API is
`run_with_performance_counters(f)` / `get_performance_counters()` /
`record_performance!` (`package/kernel/main/cell/PerformanceCounter.jl`,
documented in `package/kernel/doc/cell.md`, "PerformanceCounterModule —
instrumentation").

Using `perf_counters()` (see
[package/kernel/doc/cell.md](../../documentation/package/kernel/cell.md), "PerformanceCounterModule — instrumentation"), assert:

- Changing the maximum width of the context re-wraps and invalidates only the wrap /
  layout cells, not upstream syntax/text cells.
- Editing a single input span re-wraps only the affected output portion.

### 3. Keyboard navigation across soft-wrapped lines ⏳

**⏳ OPEN (re-verified 2026-08-12):** No end-to-end `KeyDown` navigation test for soft-wrapped lines exists in `package/substrate/test/projection/WordWrappingTest.jl` (no `KeyDown` reference found).

End-to-end test through the full chain (`… → SyntaxToText → WordWrapping
→ TextToGraphics`): for a wrapped paragraph, simulate `KeyDown(:left)`,
`:right`, `:up`, `:down`, `:home`, `:end` and assert the resulting input
selection lands on the same characters as before the refactor.

This is the highest-value remaining test because it exercises the full
forward+backward selection mapping pipeline that the load-bearing
`WrapSeg` table sits on top of.

## Optional follow-ups

### Soft/hard newline distinction ⏳

**⏳ OPEN (re-verified 2026-08-12):** `TextNewline` still has no `soft` field — `package/text/main/Text.jl:83-89` defines it with `font, font_color, fill_color, line_color, padding` (plus the `selection` field every `@document` gets) only.

Add a `soft::Bool` flag to `TextNewline` set by `WordWrapping`. Today
soft (wrap) and hard (source `\n`) breaks are indistinguishable to
`TextToGraphics`, which is fine for layout and visual-line nav but blocks
features like "go to end of logical line". Out of scope until a consumer
needs it.

## Open questions (carry-over from the original plan)

- **The content width vs. the raw viewport width.** Today the scroll
  pane already subtracts its padding before it passes its range on
  (`with_inner_size`), so `WordWrapping` reads the content width. If a
  consumer needs the raw viewport width too, we'd add a separate
  property; settle when the next layout-shape consumer shows up.
  See [widget-layout.md](../done/widget-layout.md).
- **Boundary cursor convention.** The current forward-mapper prefers the
  start of the next visual line at a wrap boundary, matching
  `TextToGraphics`'s boundary-duplicate convention as it stood when this plan
  was written. *(Note, re-checked 2026-08-12: the caret model itself has since
  moved to a pure flat character offset with no `(span, char)` duplicate pair
  to prefer between — see `package/text/main/Text.jl:396-398`. Whether this
  open question still applies in the same form, or dissolved along with the
  duplicate-pair model, needs a fresh look before picking this up.)* This
  needs a real-user verification once we exercise it through the
  workbench editor; covered indirectly by the "keyboard navigation across
  soft-wrapped lines" test above.
- **Does the `ListNode` (lazy paragraph) path still earn its keep** once
  wrapping is external and every visual line is its own `TextNewline`-
  delimited paragraph? Possibly simplify to the eager path. Evaluate
  separately when we have a large-document use case to profile.

## Adjacent fix that surfaced during this work

**✅ DONE, but the julia wiring was since removed for an unrelated reason
(re-verified 2026-08-12):** `TextLineNumbering` still has a real reader.
`package/text/main/LineNumbering.jl:107` implements
`read_intent(::TextLineNumbering, ::SimpleIoMap, ::ReplaceSelectionOperation)`
(the function was renamed from `projection_read`), mapping output
`.elements[out_span].content{char}` paths back to the input span via
`_output_to_input_map` (line 132), plus a `KeyDown` pass-through — exactly the
"analogous to what `WordWrapping` now has" fix described below. **However,
`LineNumbering()` is no longer wired into the julia chain** —
`package/julia/example/projection/Julia.jl` now reads
`ChainingProjection(RecursiveProjection(JuliaToSyntax()), RecursiveProjection(SyntaxToText()), TextToGraphics(measure=measure))`,
with no `LineNumbering` stage. It was removed by commit `43ec6e76`
("fix(nav): round-trip introduced-token carets so Julia text/tree navigation
works", 2026-07-02) for a *different* reason than this note describes: its
`print_document` hardcoded the output `.selection` to `Cell(nothing)`, which
dropped the caret outright (not merely a missing backward mapper), and the
commit says line numbering "is being reworked from a text to a graphics
projection separately" — tracked in the now-done
[plan/done/julia-navigation-caret-roundtrip.md](../done/julia-navigation-caret-roundtrip.md).
As of 2026-08-12 that rework has not landed: `LineNumbering` is still a
Text→Text projection, just no longer in the Julia example chain.

The two failing `julia` selection tests this note originally referred to are a
historical, pre-existing gap in
`LineNumbering`'s selection mapping (after it was inserted between
`SyntaxToText` and `TextToGraphics` in
`package/julia/example/projection/Julia.jl`, since removed as described
above).
Verified independently at the time: removing the `LineNumbering` step from that chain
makes the julia test green. The fix is to give `LineNumbering` a real
`map_reference_backward` / `read_intent` (analogous to what
`WordWrapping` now has) so cursor ops can flow back through it — that reader
now exists, but is moot for `julia` since the stage was removed instead. Track
separately, not under this plan.
