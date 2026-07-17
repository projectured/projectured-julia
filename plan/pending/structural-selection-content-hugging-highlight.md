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

- [ ] 1. Add `_compute_span_rows(coord_map, span_flat_offsets, hl_start, hl_stop, p)` →
      `Vector{NTuple{4,Int}}` (per-row content-hugging rects), reusing the overlap +
      `_seg_cursor_x` math from `_compute_span_geo`.
- [ ] 2. `_layout_overlay` returns `highlight` as a `Vector{NTuple{4,Int}}` (empty when
      no box selection) via `_compute_span_rows`.
- [ ] 3. Replace the single `highlight_rect` in `print_document` with a highlight
      **sub-canvas** whose element `CellVector` builds one persistent `GraphicsRect`
      per rect in `overlay[].highlight`. Keep `top_elements` a fixed 3-slot vector
      `[highlight_canvas, lines_stack, cursor_rect]` (so it never regenerates; the
      per-selection churn is isolated to the sub-canvas). `highlight_offset` stays 1
      (one leading highlight element).
- [ ] 4. Keep `_compute_span_geo` only if still referenced; otherwise remove it. Add a
      per-row unit test mirroring the existing `_compute_column_geo` test.
- [ ] 5. Verify: JSON `address` selection now hugs content; run `test_text_to_graphics`
      / relevant visual tests; smoke the JSON example.

## Notes / discoveries

(filled in during implementation)
