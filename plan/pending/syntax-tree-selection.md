# Syntax Tree Selection — remaining slices

> **Status (2026-08-12): IN PROGRESS.** Item 2 (wrapped/paragraph highlight) is
> still not built. Item 1 changed shape since the last check: the renamed
> successor of `TextRectangularReference` now paints a ragged per-row highlight
> for any range (see below), and a new flat range step type exists with a
> highlight render path — but no gesture yet creates a non-degenerate range
> selection, and the structural sibling-range piece (`.children[2..4]`) is still
> not built. Both open questions still have no test.

The whole-element syntax selection **foundation shipped** — the `∅` (empty-path)
data model, forward/backward mapping, the region-box rendering
(now `TextSpanReferenceStep`, see below), and the keyboard + mouse interaction.
That work is recorded in [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md).

This file tracks the two **deferred stretch slices** and the remaining open
questions.

## 1. Range / multi-element text selection ⏳ (partly landed under new names)

**Renaming since this plan was written:** `TextRectangularReference` is now
`TextSpanReferenceStep` (`package/text/main/TextSpanReferenceStep.jl`) — same
`(start, stop)` flat-offset payload, still `:structural` (terminal). Its
renderer, `_compute_span_rows` in
[`package/text/main/TextToGraphics.jl`](../../package/text/main/TextToGraphics.jl)
(around line 1151), already paints the **ragged content-hugging per-row
rectangles** this section asked for, not a single bounding box — that upgrade
landed as part of the whole-element highlight, not as a separate range feature.

**✅ landed (verified 2026-08-12), as a side effect, not a dedicated feature:**
a real flat character-range type, `TextRangeReferenceStep`
(`package/text/main/TextRangeReferenceStep.jl`), whose non-degenerate form
(`start != stop`) is recognized by `_highlight_char_range`
(`TextToGraphics.jl` around line 1096) and painted through the same
`_compute_span_rows` ragged-row renderer. `TextColumnReferenceStep`
(`package/text/main/TextColumnReferenceStep.jl`) is a further, separate
addition — a true rectangular column-box selection (Sublime/VS Code style) —
reserved with its own geometry helper `_compute_column_geo`, but **no
producer emits it yet**.

**⏳ still OPEN (verified 2026-08-12):** nothing constructs a
`TextRangeReferenceStep` with `start != stop` from a live gesture — grep for
`MouseDown` / `MouseDrag` / `Shift` in
[`package/text/main/Text.jl`](../../package/text/main/Text.jl) and
[`TextToGraphics.jl`](../../package/text/main/TextToGraphics.jl) finds nothing.
Every construction site builds a degenerate `(pos, pos)` caret. So the
**character-range** half of this slice has a data model, a forward-mapped
representation, and a renderer, but no interactive way to create one (no
shift+arrow extend, no mouse-drag select). And the **structural sibling-range**
half — `.children[2..4]` selecting three adjacent subtrees via the kernel's
generic `RangeReferenceStep` (`package/kernel/main/reference/ReferenceStep.jl`)
— is not wired into whole-element tree selection or navigation at all.

What remains:

- **Gesture.** Wire a mouse-drag or Shift+arrow gesture in the Text domain to
  emit a non-degenerate `TextRangeReferenceStep` (or a `TextSpanReferenceStep`,
  depending on which selection style is wanted) instead of only ever emitting
  carets.
- **Plumbing.** Confirm `@reference` / `@reference_case` surface syntax exists
  for constructing/matching the range steps if mappers need it (today they are
  built directly in Julia, not through the DSL).
- **Syntax side.** Define how a sibling-range selection (`.children[s..e]`) is
  stored and mapped forward to a flat range on the parent's `TextBlock` — the
  single-child flat-extent path (`_syntax_to_flat` + `child_char_ranges`) is
  the model to extend, per the original design.

## 2. Wrapped / paragraph text (`ListNode`) highlight ⏳

**⏳ OPEN (verified 2026-08-12):** `_print_listnode`
(`package/text/main/TextToGraphics.jl:787-791`) still
builds its `TextToGraphicsIoMap` with an empty coord map (`Cell(SegCoord[])`)
and emits no highlight/cursor overlay rects — unlike the single-line path
(`cursor_rect` around line 304, the highlight rects built from
`get_highlight_rect` around line 323). No selection chrome renders over
wrapped/paragraph text.

The `ListNode` path (`_print_listnode`) draws **no selection chrome** today and
uses an **empty coord map**, so neither the region box nor the range highlight
renders over wrapped/paragraph text. It needs the same **highlight-layer**
treatment the single-line/flattened path already has: produce per-segment
`SegCoord`s (or an equivalent coord map) for wrapped lines so the highlight
geometry helpers can gather the covered segments and paint into the dedicated
highlight layer.

## Open questions

- **⏳ OPEN (verified 2026-08-12):** **Composition with `ProjectionReferenceStep`**
  (projection-introduced delimiters, the current name for what this plan calls
  `ProjectionReference`; see `package/kernel/main/projection/ProjectionReferenceStep.jl`).
  Likely: an `∅` selection on a projection-introduced node is allowed and renders
  as that delimiter's range. Confirm and add a test. No such test found in
  `package/projectured/test/projection/SyntaxTreeSelectionTest.jl` (no
  `ProjectionReferenceStep` reference there).
- **⏳ OPEN (verified 2026-08-12):** **Wrapper-projection iomaps** (`Dragging`,
  navigation overlays) — confirm they pass an `∅` selection through unchanged.
  The `Dragging` decorator now lives at
  `package/dragging/main/DraggingProjection.jl` with its own
  `DraggingProjectionIoMap` (there is no generic `ContentIoMap` in the dragging
  package). `package/projectured/test/projection/DraggingTest.jl` uses
  `EmptyReference()` only as a path terminator inside a helper reference, not as
  a selection; no test asserts a `∅` *selection* passes through `Dragging`
  unchanged.

## Related

- Foundation (done): [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md),
  [`../done/finish-syntax-tree-navigation.md`](../done/finish-syntax-tree-navigation.md).
- Table-domain analog of selection: [`../done/table-selection.md`](../done/table-selection.md).
