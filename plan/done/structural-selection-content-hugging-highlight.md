# Content-hugging highlight for structural selections

## Problem

A structural (whole-node) syntax selection is projected down to the text domain as a
single contiguous flat range `TextSpanReference(s, e)` (`SyntaxToText.jl:402-408`),
running from the node's first glyph through its last, crossing every newline/indent
decoration span in between.

The text→graphics layer draws that range as **one bounding box** (`_compute_span_geo`
in `TextToGraphics.jl`): the min/max x/y over every segment overlapping `[s, e)`,
painted as a single rounded rect. That rectangle over-covers:

- indentation whitespace on the more-indented interior lines (its left edge sits at
  the least-indented content column, so interior lines get their leading indent
  highlighted);
- empty space to the right of short lines (its right edge sits at the widest line's
  end, so the `{`/`}` lines get trailing empty space highlighted, incl. past the
  node-final `}`).

## Goal (three properties, one rule)

Draw the selection as **per-row content-hugging rects** instead of one bounding box.
Per row: consider only the in-range segment pieces that contain a non-whitespace
character; the rect runs `[min px_left … max px_right]` of those, at the row's y with
the row's font height. Rows whose only in-range content is whitespace produce no rect.

This yields exactly the requested behavior:

- **First line** — nothing highlighted before the node's first char (its leading
  indent sits at flat `< s`, already outside the range).
- **Last line** — nothing highlighted after the node's last char (trailing
  separator/`,` sits at flat `>= e`, outside the range; and per-row rects remove the
  empty box to the right of `}`).
- **Interior lines** — start at the indentation level (the node's own indent spans
  *are* inside `[s, e)` but are whitespace, so they don't anchor the left edge).

## Consistency

The selection **model is unchanged** — a structural selection still maps to the same
`TextSpanReference(s, e)`. Only the *geometry of how that flat range is drawn* changes,
entirely inside `TextToGraphics`. No reference, mapper, reader, or projection contract
is touched. This reinforces the "text/graphics layers stay dumb; geometry lives here"
split.

## Design decisions

- **Per-line disconnected rects** (not a unified notched polygon). Matches the ask;
  the polygon is deferred as future polish.
- **The `∅` whole-block case** (`_highlight_char_range` maps a bare `EmptyReferencePath`
  to "highlight the whole block, `(0, ∞)`") now also content-hugs per row. Deliberate,
  accepted — it's an improvement for that case too.
- **Whitespace detection is local**: `SegCoord` carries `.text`; a piece is skipped for
  anchoring iff its highlighted sub-range is all whitespace (`all(isspace, …)`), which
  catches indent spans, newline spans, and zero-width indent slots.

## Implementation steps

- [x] 1. Added `_compute_span_rows(coord_map, span_flat_offsets, hl_start, hl_stop, p)`
      → `Vector{NTuple{4,Int}}` (per-row content-hugging rects), reusing the overlap +
      `_seg_cursor_x` math from the old `_compute_span_geo`. Blank pieces (indent /
      newline / zero-width slots) are skipped for anchoring via `_hl_piece_blank`.
- [x] 2. `_layout_overlay` now returns `highlight` as a `Vector{NTuple{4,Int}}` (empty
      when no box selection) via `_compute_span_rows`.
- [x] 3. Replaced the single `highlight_rect` with a highlight **sub-canvas** whose
      element `CellVector` builds one persistent `GraphicsRect` per rect in
      `overlay[].highlight` (`get_highlight_rect(k)`, keyed + evicted by row index).
      `top_elements` stays the fixed 3-slot vector `[highlight_canvas, lines_stack,
      cursor_rect]`; per-selection churn is isolated to the sub-canvas.
      `highlight_offset` stays 1 (one leading highlight element).
- [x] 4. `_compute_span_geo` is removed (only `_layout_overlay` used it). Added a
      per-row unit test mirroring the `_compute_column_geo` test.
- [x] 5. Verified end-to-end: rendered `json_example` with `entries[4]` (the whole
      `address` entry) selected → the PNG shows content-hugging (first line hugs
      `"address": {`, interior lines start at their indent, `},` shows only `}`).
      `test_text_to_graphics()` green (all testsets, incl. the new one). Broad
      `test_visual()` sweep: 47104 pass / 1 broken (pre-existing) / 0 fail / 0 error
      — zero regressions across the shared seam.

## Notes / discoveries

- The selection reaches `TextToGraphics` correctly as a box: `set_selection!(doc,
  @reference(doc, entries[4]))` forward-maps to `TextSpanReference(57, 149)` at the
  text layer, and `_highlight_char_range` returns `(57, 149)`. So the model already
  did the right thing; only the *geometry* was wrong. Confirms the change is a pure
  view refinement.
- The whole `address` entry (`entries[4]`) highlights the key too, matching the
  screenshot; the whole `address` value (`entries[4].value`) starts at `{`.
- Interior member separators (`, ` between object members) sit *inside* the range and
  are correctly hugged; only the separator *after* `}` (between address and scores)
  is outside the range and stays unhighlighted — exactly the requested last-line rule.
