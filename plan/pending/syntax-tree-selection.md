# Syntax Tree Selection — remaining slices

The whole-element syntax selection **foundation shipped** — the `∅` (empty-path)
data model, forward/backward mapping, the region-box rendering
(`TextRectangularReference`), and the keyboard + mouse interaction. That work is
recorded in [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md).

This file tracks the two **deferred stretch slices** and the remaining open
questions. Neither is started.

## 1. Range / multi-element text selection ⏳

**⏳ OPEN (verified 2026-06-23):** `TextRangeReference` does not exist anywhere
under `package/` (grep returns no matches). The foundation it builds on still
exists — `TextRectangularReference` (`package/kernel/src/reference/Reference.jl`,
exported line 27; rendered in `package/domain/src/projection/primitive/TextToGraphics.jl`)
and the flat→pixel machinery (`_text_selection_range`,
`package/domain/src/document/Text.jl:522`). None of the renderer / plumbing /
syntax-side sub-items below are built.

A *range* over adjacent siblings — e.g. `.children[2..4]` selects three adjacent
subtrees — and the ragged cross-span **character** range that is its text-layer
sibling. Named in the original design (§3, "stretch") but not built. The
whole-element marker design was kept extensible so this slice can land without
reworking it.

Text-domain representation — the planned sibling of the built
`TextRectangularReference`, **identical payload, the type selects the geometry**:

```
TextRangeReference(start, end)   # → ragged text-flow polygon (cross-span char range)
```

What it needs:

- **Renderer.** Reuse `TextToGraphics`'s existing flat→pixel conversion
  (`_selection_range` already turns flat offsets into per-segment pixels for the
  box), but paint a **ragged per-line polygon** instead of the bounding box. It
  should read **distinct from the structural box** (different colour) — a char
  range is not a structural pick.
- **Plumbing.** `set_selection!` must treat `TextRangeReference` as **terminal**
  (don't navigate into a child, like `PositionReference` / `ProjectionReference` /
  `TextRectangularReference`). The `@reference` builder and `@reference_case` need
  surface syntax for it if mappers are to construct/match it.
- **Syntax side.** Define how a sibling-range selection (`.children[s..e]`) is
  stored and mapped forward to a flat `[start, end)` on the parent's `TextText`
  (the box slice already proved the single-child flat-extent path via
  `_syntax_to_flat` + `child_char_ranges`).

This is the cross-span character-selection feature; it is otherwise unrelated to
whole-element selection and only shares the flat→pixel machinery.

## 2. Wrapped / paragraph text (`ListNode`) highlight ⏳

**⏳ OPEN (verified 2026-06-23):** `_print_listnode`
(`package/domain/src/projection/primitive/TextToGraphics.jl:412-417`) still
builds its `TextToGraphicsIoMap` with an empty coord map (`Cell(SegCoord[])`)
and emits no highlight/cursor overlay rects — unlike the single-line path
(`highlight_rect` / `cursor_rect`, same file ~lines 238-248). No selection
chrome renders over wrapped/paragraph text.

The `ListNode` path (`_print_listnode`) draws **no selection chrome** today and
uses an **empty coord map**, so neither the region box nor a future range polygon
renders over wrapped/paragraph text. It needs the same **highlight-layer**
treatment the single-line/flattened path already has: produce per-segment
`SegCoord`s (or an equivalent coord map) for wrapped lines so `_selection_range`
can gather the covered segments and paint into the dedicated highlight layer.

## Open questions

- **⏳ OPEN (verified 2026-06-23):** **Composition with `ProjectionReference`**
  (projection-introduced delimiters).
  Likely: an `∅` selection on a projection-introduced node is allowed and renders
  as that delimiter's range. Confirm and add a test. No such test found in
  `package/test/src/projection/SyntaxTreeSelectionTest.jl` (no `ProjectionReference`
  reference there).
- **⏳ OPEN (verified 2026-06-23):** **`ContentIoMap` wrappers** (`Dragging`,
  navigation overlays) — confirm they pass an `∅` selection through unchanged.
  `DraggingTest.jl` only uses `EmptyReferencePath` as a path terminator in a
  helper (line 31); no test asserts a `∅` *selection* passes through `Dragging`/
  `ContentIoMap` unchanged.

## Related

- Foundation (done): [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md),
  [`../done/finish-syntax-tree-navigation.md`](../done/finish-syntax-tree-navigation.md).
- Table-domain analog of selection: [`table-selection.md`](table-selection.md).
