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

- [x] 1. Added `_layout_line(p, group)` (extracted from `_layout_text`'s per-span
  inner loop: TextString embedded-`\n`, TextGraphics, fill, placements, coord_map)
  in coordinates **relative** to the line origin. No cursor/highlight (those stay
  global). `group.spans` carries `(global_elem_idx, span)` so `SegCoord.span_idx`
  stays in the input element index space; an all-empty group falls back to the
  terminating newline's font height.
- [x] 2. Restructured `projection_print` non-`ListNode` path:
  - `lines_cell` groups `styled.elements` by `TextNewline` (reads element
    identities/types only — never `.content`).
  - lazy per-line `line_layout`, `line_h`, `line_y` (cumulative chain) cells built
    once per line index (`get_line_cells`), reused across recomputes.
  - per-line persistent sub-canvas at `y = line_y`, its element `CellVector`
    reading only `line_layout[L]`; segs are persistent GraphicsText/Rect keyed by
    `(span_oid, occ, li)` (the existing `_persistent_graphic!`).
  - kept the global selection-driven `overlay` → `cursor_rect` + `highlight_rect`.
  - top canvas (`layout_none`) = `[highlight_rect, vertical line-stack, cursor_rect]`;
    the line-stack is `layout_vertical`, non-overlapping for early-stop.
  - `char_to_coord` = concat of per-line coord maps shifted by `line_y` (absolute,
    reader-only — identical SegCoords to before).
  - `highlight_offset` kept at `1` (legacy `_translate_click` path is now
    unreachable for these non-leaf canvases but preserved).
- [x] 3. Verified locality with a headless probe: editing the last line marks only
  that line's segs stale; the line-list / stack backings stay `isuptodate`;
  coord_map y-values are unchanged (0,24,…,168). Middle-line edit reflows lines
  below via the y chain (expected).
- [x] 4. Tests — text examples (`plain_text`/`text`/`text_with_image`) printer +
  reader + nav + repl: **3035 pass**. `test_text_to_graphics()`: **67 pass**
  (helpers updated to flatten nested sub-canvases to absolute coords). Full
  `test_printers()`+`test_readers()` sweep: **197448 pass, 0 fail**.
  `test_text_navigations()`+`test_repls()`: only 5 pre-existing seed failures
  (natural/filesystem/navigator/rotating_vector/conversation_editor — identical on
  `main`). `plain_text` `check_reaches_all` 420/7 = same as `main` baseline.
- [x] 5. Added a font-free dirty-rect test (`DirtyRectTest.jl`) mirroring the
  per-line output: editing the last line's width yields a rect bounded to that
  line (`y 38..60`), not the whole document. **20 pass** (was 14).

## Risks / notes (as implemented)

- **Segment `.y` is now relative** to its line sub-canvas (absolute = sub-canvas
  `y` + segment `y`). Rendering / bounds / coord_map all account for this; only
  direct tests inspecting `GraphicsText.y` needed updating (done, via a flatten
  helper).
- Embedded-`\n`-only pipelines (SyntaxToText `TextString("\n")` separators, no
  `TextNewline` elements) collapse into one line group → stay whole-block dirty
  exactly as before. No improvement, no regression (already non-local via
  SyntaxToText flattening).
- Middle-line edits reflow lines below (height chain) — acceptable, matches the
  ListNode spine behaviour. Editing the **last** line is tight (nothing below).
- Granularity is **per-line** (chosen with the user): a single-span line still
  dirties its full width, not just the appended glyph — inherent to one
  GraphicsText per line. Sub-line "from-cursor" tightening was explicitly out of
  scope.
- Rasterized text (opt-in `scrolling`/`introspection` wrappers via GraphicsCaching)
  now sees a non-leaf text canvas and recurses instead of rasterizing the whole
  block; not covered by the registered-example suite — flagged for follow-up if it
  matters.
