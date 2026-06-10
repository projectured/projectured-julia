# Syntax Tree Selection — remaining slices

The whole-element syntax selection **foundation shipped** — the `∅` (empty-path)
data model, forward/backward mapping, the region-box rendering
(`TextRectangularReference`), and the keyboard + mouse interaction. That work is
recorded in [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md).

This file tracks the two **deferred stretch slices** and the remaining open
questions. Neither is started.

## 1. Range / multi-element text selection ⏳

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

The `ListNode` path (`_print_listnode`) draws **no selection chrome** today and
uses an **empty coord map**, so neither the region box nor a future range polygon
renders over wrapped/paragraph text. It needs the same **highlight-layer**
treatment the single-line/flattened path already has: produce per-segment
`SegCoord`s (or an equivalent coord map) for wrapped lines so `_selection_range`
can gather the covered segments and paint into the dedicated highlight layer.

## Open questions

- **Composition with `ProjectionReference`** (projection-introduced delimiters).
  Likely: an `∅` selection on a projection-introduced node is allowed and renders
  as that delimiter's range. Confirm and add a test.
- **`ContentIoMap` wrappers** (`Dragging`, navigation overlays) — confirm they pass
  an `∅` selection through unchanged.

## Related

- Foundation (done): [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md),
  [`../done/finish-syntax-tree-navigation.md`](../done/finish-syntax-tree-navigation.md).
- Table-domain analog of selection: [`table-selection.md`](table-selection.md).
