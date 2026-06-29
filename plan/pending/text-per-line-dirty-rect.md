# Per-line dirty rectangle for TextToGraphics

## Problem

In `plain_text_example` / `text_example` with `partial_render=true, debug_dirty=true`,
typing a character into any line marks the **whole document** dirty, not just the
edited line.

## Root cause (confirmed empirically)

The SDL dirty-walk (`_compute_dirty_rect` in
[ProjecturedSdl.jl](../../package/sdl/src/ProjecturedSdl.jl)) is correct. The
problem is in the printer
[TextToGraphics.jl](../../package/domain/src/projection/primitive/TextToGraphics.jl).

The non-`ListNode` path builds a **single monolithic `layout` cell** whose thunk
reads *every* span's content (`_layout_text` iterates `styled.elements`). Every
persistent per-segment `GraphicsText` reads `layout[]` via `_plget`. Because the
reactive engine is **write-driven, not value-driven**
([reactive-cells.md](../../documentation/reactive-cells.md)), editing one line
invalidates `layout`, which transitively invalidates **all** segments' field
cells. The dirty-walk then correctly reports the whole canvas dirty.

Probe (typing `X` into the last line of `plain_text_example`): all 10 output
elements (`highlight + 8 spans + cursor`) go `STALE` before the next render.

The recently-landed `d808248 persistent per-segment graphics (dimension C)` got
output-object *identity* reuse, but not dependency-graph **locality** — every
segment still depends on the shared `layout` cell.

## Goal

Editing one line invalidates only that line's segment cells, so the dirty rect
covers just that line (granularity: **per-line**, chosen with the user — a
single-span line still dirties its full width, which is inherent to one
GraphicsText per line). Editing the **last** line dirties only the last line.

## Design — per-line sub-canvases (flat reader/backend untouched)

Decompose the layout per visual line, where lines are delimited by `TextNewline`
**elements** (structural, content-independent). Each line becomes its own
reactive sub-canvas; the *list of line sub-canvases* depends only on the element
structure (which spans, which newlines), so a content edit never invalidates the
top-level membership — the dirty-walk descends and finds only the edited line's
sub-canvas stale.

Confinement principle: a line sub-canvas's element list reads only **that line's**
content. Embedded `\n` inside a span (e.g. SyntaxToText's `TextString("\n")`
separators, where there are no `TextNewline` elements) collapses to one big line
group → that path stays whole-document dirty exactly as today (no regression;
those pipelines are already non-local via SyntaxToText flattening).

### Output tree

```
top canvas (layout_none, overlapping=true)
├── highlight_rect          (global overlay, selection-driven, absolute coords)
├── line sub-canvas 1  at (0, y1)   elements = persistent segs of line 1
├── line sub-canvas 2  at (0, y2)   ...
├── …
└── cursor_rect             (global overlay, selection-driven, absolute coords)
```

- **Line list** = `CellVector` whose backing thunk reads `lines_cell` (grouping
  by `TextNewline`) — **content-independent**. Sub-canvas objects are persistent
  (reused across recomputes), keyed by line index.
- **Line `y`** = cumulative height of prior lines (a chain). Editing line L
  invalidates L's height → L+1…N's `y` (reflow below); editing the **last** line
  invalidates nothing below. ✓ the user's case is tight.
- **Per-line layout** `line_layout[L] = Cell(() -> _layout_line(spans_L, …))`
  reads only line L's spans' content → only line L's segs go stale on an edit.
- **Cursor/highlight** stay a single selection-driven `overlay` (absolute coords)
  so a pure caret move still dirties only the caret slivers (dimension A
  preserved — `overlay` does not read `layout`/per-line cells, only the spans for
  positioning + the selection).
- **coord_map** (`char_to_coord`, reader-only, not in the rendered tree) is
  assembled from the per-line layouts in absolute coords, so the `MousePress` /
  key-nav reader is byte-for-byte unchanged. `_translate_click` /
  `highlight_offset` (the rasterized-image path) are not exercised by the bare
  text examples; keep them working for the flat case.

Coordinates stay **absolute and identical** to today (seg at `(seg_x, y_L)`), so
the reader and downstream consumers see the same SegCoords.

## Steps

- [ ] 1. Extract `_layout_line(p, spans, start_y, base_flat; collect_spans)` from
  `_layout_text`'s per-span inner loop (TextString embedded-`\n`, TextGraphics,
  fill, placements, coord in absolute coords). No cursor/highlight (those stay
  global). Returns `(spans=placements, by_key, coord_map, width, height,
  flat_len)`.
- [ ] 2. Restructure `projection_print` non-`ListNode` path:
  - `lines_cell` groups `styled.elements` by `TextNewline` (structure only).
  - per-line `line_layout`, `line_height`, `line_y` (cumulative) cells.
  - per-line persistent sub-canvas with a content-independent element `CellVector`
    keyed by line index; segs are persistent GraphicsText/Rect keyed by
    `(span_oid, occ, li)` reading `line_layout[L]`.
  - keep global `overlay` → `cursor_rect` + `highlight_rect`.
  - top canvas `[highlight_rect, line sub-canvases…, cursor_rect]`.
  - `char_to_coord` = concat of per-line coord maps (absolute).
- [ ] 3. Verify locality with the headless probe (only the edited line's segs
  stale; line-list backing stays uptodate; editing last line → nothing below
  stale).
- [ ] 4. Tests (narrowest first): `test_printer(plain_text_example)`,
  `test_reader(plain_text_example)`,
  `test_text_navigation(plain_text_example; check_reaches_all=true)`,
  `test_repl(plain_text_example)`; then `text_example`, then
  `test_dirty_rect()`, then a broader `test_syntax_to_text()` /
  `test_printers()` sweep for regressions.
- [ ] 5. Add a dirty-rect test asserting per-line behaviour for plain_text (edit
  last line → rect bounded to the last line; edit middle line → reflow below).

## Risks / notes

- Embedded-`\n`-only pipelines (SyntaxToText) collapse to one line group → no
  improvement, no regression. Documented as expected.
- Middle-line edits reflow lines below (height chain) — acceptable and matches
  the ListNode spine behaviour.
- Keep `_render_canvas!` recursion / bounds (already handle nested canvases).
