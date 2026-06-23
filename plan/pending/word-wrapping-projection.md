# Word wrapping — remaining work

The structural refactor (extracting wrap out of `TextToGraphics` into a
context-aware `WordWrapping` with a bidirectional mapping table) is done —
see [plan/done/word-wrapping-projection.md](../done/word-wrapping-projection.md).
What follows are the items the original plan called for that are not yet
landed.

## Remaining tests (§6 of the original plan)

Existing coverage in
[`test/src/projection/WordWrappingTest.jl`](../../test/src/projection/WordWrappingTest.jl)
covers character preservation, no-wrap, selection round-trip, and
`available_width`-from-context. Still to add:

### 1. Wrap parity ⏳

**⏳ OPEN (verified):** No parity/snapshot test exists. `package/test/src/projection/WordWrappingTest.jl` contains no comparison against captured pre-refactor `GraphicsText` x/y or `canvas_w/h` output (no `parity`/`snapshot` references found).

For a corpus of spans + a given `max_width`, assert the visual line breaks
produced by `WordWrapping`+`TextToGraphics` match the pre-refactor output
(captured snapshot of `GraphicsText` x/y, `canvas_w/h`). Useful as a
regression net while we still remember the old behaviour. The fixture
files would live alongside the test.

### 2. Reactivity / incremental invalidation ⏳

**⏳ OPEN (verified):** No `perf_counters`-based invalidation test exists in `package/test/src/projection/WordWrappingTest.jl` (no `perf_counters` reference found).

Using `perf_counters()` (see
[guide/reactive-cells.md](../../guide/reactive-cells.md#L58-L63)), assert:

- Changing `:available_width` re-wraps and invalidates only the wrap /
  layout cells, not upstream syntax/text cells.
- Editing a single input span re-wraps only the affected output portion.

### 3. Keyboard navigation across soft-wrapped lines ⏳

**⏳ OPEN (verified):** No end-to-end `KeyDown` navigation test for soft-wrapped lines exists in `package/test/src/projection/WordWrappingTest.jl` (no `KeyDown` reference found).

End-to-end test through the full chain (`… → SyntaxToText → WordWrapping
→ TextToGraphics`): for a wrapped paragraph, simulate `KeyDown(:left)`,
`:right`, `:up`, `:down`, `:home`, `:end` and assert the resulting input
selection lands on the same characters as before the refactor.

This is the highest-value remaining test because it exercises the full
forward+backward selection mapping pipeline that the load-bearing
`WrapSeg` table sits on top of.

## Optional follow-ups

### Soft/hard newline distinction ⏳

**⏳ OPEN (verified):** `TextNewline` still has no `soft` field — `package/domain/src/document/Text.jl:86` defines it with `font, font_color, fill_color, line_color, padding, selection` only.

Add a `soft::Bool` flag to `TextNewline` set by `WordWrapping`. Today
soft (wrap) and hard (source `\n`) breaks are indistinguishable to
`TextToGraphics`, which is fine for layout and visual-line nav but blocks
features like "go to end of logical line". Out of scope until a consumer
needs it.

## Open questions (carry-over from the original plan)

- **`:available_width` content vs. raw viewport width.** Today the scroll
  pane already subtracts its padding before publishing
  `:available_width`, so `WordWrapping` reads the content width. If a
  consumer needs the raw viewport width too, we'd add a separate
  property; settle when the next layout-shape consumer shows up.
  See [widget-layout.md](../done/widget-layout.md).
- **Boundary cursor convention.** The current forward-mapper prefers the
  start of the next visual line at a wrap boundary, matching
  `TextToGraphics`'s existing boundary-duplicate convention
  ([TextToGraphics.jl:117](../../program/src/projection/primitive/TextToGraphics.jl#L117)).
  This needs a real-user verification once we exercise it through the
  workbench editor; covered indirectly by the "keyboard navigation across
  soft-wrapped lines" test above.
- **Does the `ListNode` (lazy paragraph) path still earn its keep** once
  wrapping is external and every visual line is its own `TextNewline`-
  delimited paragraph? Possibly simplify to the eager path. Evaluate
  separately when we have a large-document use case to profile.

## Adjacent fix that surfaced during this work

**✅ DONE (verified):** `TextLineNumbering` now has a real reader. `package/domain/src/projection/primitive/LineNumbering.jl:97-110` implements `projection_read(::TextLineNumbering, ::SimpleIoMap, ::ReplaceSelectionOperation)`, mapping output `.elements[out_span].content{char}` paths back to the input span via `_output_to_input_map` (lines 117-141), plus a `KeyDown` pass-through (line 112) — exactly the "analogous to what `WordWrapping` now has" fix described below. `LineNumbering()` is still wired into the julia chain between `SyntaxToText` and `TextToGraphics` (`package/example/src/projection/Julia.jl:5`). (Note: this was tracked separately from this plan; the fix has since landed. Tests not re-run here — Julia is not installed in this environment — but the reader code is present.)

The two failing `julia` selection tests are a pre-existing gap in
`LineNumbering`'s selection mapping (after it was inserted between
`SyntaxToText` and `TextToGraphics` in
[example/src/projection/Julia.jl](../../example/src/projection/Julia.jl)).
Verified independently: removing the `LineNumbering` step from that chain
makes the julia test green. The fix is to give `LineNumbering` a real
`map_reference_backward` / `projection_read` (analogous to what
`WordWrapping` now has) so cursor ops can flow back through it. Track
separately, not under this plan.
