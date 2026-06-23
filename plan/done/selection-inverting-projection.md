# SelectionInverting: encode text selection into the Text domain via color inversion

> **✅ FULLY IMPLEMENTED (verified 2026-06-23).** Every phase below is done in the
> current codebase. Projection: `package/domain/src/projection/primitive/SelectionInverting.jl`
> (module `SelectionInvertingModule`, struct `SelectionInverting <: Projection`,
> exports `SelectionInverting, SelectionInvertingIoMap, SelSeg`). Shared helper:
> `text_selection_flat` / `_text_cursor_flat` in `package/domain/src/document/Text.jl:606-636`.
> Registered: `package/domain/src/ProjecturedDomain.jl:132`. Console wired & inline
> reverse-video removed: `package/domain/src/backend/Console.jl` (doc comments at
> :32-34, :165-169, :215). Pipeline insertion: `package/example/src/projection/Json.jl:28`.
> Tests: `package/test/src/projection/SelectionInvertingTest.jl` (registered at
> `package/test/src/ProjecturedTest.jl:62`). NOTE: paths below say `program/src/...`;
> code now lives under `package/<subpackage>/src/...` after the repo restructure.

A domain-preserving **`Text → Text`** projection that reads the input
`TextText`'s selection and bakes it into the spans as **inverse video** — swapping
`font_color` ↔ `fill_color` over the selected character range (and widening a
zero-width caret to a one-character block). Because the selection becomes ordinary
span color, any backend that renders the Text domain shows it — in particular the
**console backend**, which renders `TextText` straight to the terminal and has no
separate cursor/highlight layer like `TextToGraphics` does.

> Note on the title: "text to tex" = **Text → Text** (a domain-preserving
> projection, like `LineNumbering` / `WordWrapping` / `TextFiltering` /
> `TextHighlighting`), output staying in the Text domain.

## Why

The SDL/web pipeline draws the caret/selection as a separate `GraphicsRect` layer
inside `TextToGraphics` (reading the selection at the graphics stage). The
**console backend stops at the Text domain** — there is no graphics layer to add a
cursor rect — so today `Console.jl` re-implements selection rendering inline:
`_selection_flat` / `_text_cursor_flat` resolve the selection to a flat range and
the renderer emits `\e[7m` reverse-video for the affected slice, widening a
zero-width caret to a one-char block (`Console.jl:139–285`).

That logic is correct but **trapped in the backend**: it is not reusable, not
composable, and not bidirectional. This plan lifts it into a proper projection so:

1. Selection rendering for Text-domain backends is a **composable projection**, not
   backend code.
2. The console backend becomes dumb again — render span colors, nothing else.
3. The transform is **bidirectional** (selection moves and edits map back through
   it), exactly like `TextHighlighting`.

## Design

`SelectionInverting` is the structural twin of `TextHighlighting`
([TextHighlighting.jl](../../program/src/projection/primitive/TextHighlighting.jl)):
both split `TextString`s at boundaries and restyle the resulting sub-spans
**without inserting or removing any character**, so the selection/reader mapping is
a piecewise offset table (`HighlightSeg`/`WrapSeg` → `SelSeg`). The differences:

| | `TextHighlighting` | `SelectionInverting` |
|---|---|---|
| Trigger | regex `pattern` cell | the input's own `selection` |
| Restyle | set `fill_color` swatch | **swap** `font_color` ↔ `fill_color` (inverse video) |
| Caret | n/a | zero-width caret widened to a 1-char block |
| Idle | `nothing` pattern ⇒ pass-through | no/absent selection ⇒ pass-through |

### Selecting the range

Reuse the resolution already written in `Console.jl`:
- `_selection_flat(text)` → `(start, stop, is_cursor)` half-open flat char range
  over the concatenated stream (handles `.elements[i].content{a:b}` text cursors;
  returns `nothing` when there is no renderable selection).
- Move this (and `_text_cursor_flat`) into a shared helper — either in the Text
  domain or imported by both the projection and the backend — so there is one
  source of truth. `TextToGraphics._text_selection_range`
  ([TextToGraphics.jl:163](../../program/src/projection/primitive/TextToGraphics.jl))
  is the same computation at the graphics stage; align the three on one helper.

### The inversion

For each output sub-span inside `[start, stop)`:
- `new.font_color = old.fill_color_or_default_bg`
- `new.fill_color = old.font_color`

where `default_bg` is a concrete background color (e.g. a solarized background
constant) used when the input span's `fill_color` is `nothing` — inversion needs an
explicit background, unlike the terminal's `\e[7m` which swaps against the default.
This makes the highlight **render identically across all backends** (console, SDL,
web, PDF) as inverted text, not just as a terminal attribute.

For a zero-width caret (`is_cursor`, `start == stop`): widen to a one-character
block by inverting the single character at `start` (the next glyph), matching the
console's current "block cursor" behaviour. At end-of-text, invert a synthesized
trailing space so the caret is still visible.

### Invertibility (reader)

`SelSeg(out_index, in_span, in_char_start, length)` — one entry per emitted output
`TextString` sub-span, identical in shape to `HighlightSeg`. `map_reference_*`
translate output `elements[i].content{k}` ↔ input `elements[j].content{m}` through
the table; `StringReplaceRangeOperation` and `ReplaceSelectionOperation` map back
unchanged (no characters added/removed). Copy `TextHighlighting`'s reader and
mapping wholesale — only the *segmentation source* differs (selection range vs
regex matches).

---

## Phase 1 — The projection

**✅ DONE (verified):** Implemented at `package/domain/src/projection/primitive/SelectionInverting.jl`. Struct, options (`default_bg`/`default_fg`/`block_cursor=true`), `projection_print`, `_invert`/`_invert_string!`/`_invert_span`, `SelSeg` table, `map_reference_forward`/`map_reference_backward`/`projection_read`, and module export are all present. Registered (`include`) at `ProjecturedDomain.jl:132`.

### File: `program/src/projection/primitive/SelectionInverting.jl`

- `SelectionInverting <: Projection` — options: `default_bg::StyleColor`,
  `default_fg::StyleColor` (fallbacks for `nothing` colors), `block_cursor::Bool`
  (default `true`). No pattern cell — the trigger is the input's own selection, so
  the projection is stateless beyond its style options.
- `projection_print(p, recursion, text::TextText, ctx)`:
  1. resolve `(start, stop, is_cursor)` via the shared selection-flat helper;
     `nothing` ⇒ pass-through (output structurally equals input; identity iomap).
  2. walk spans, splitting any span overlapping `[start, stop)` at the boundaries
     and emitting inverted sub-spans for the in-range portion; build the `SelSeg`
     table.
  3. widen a zero-width caret to a one-char block when `block_cursor`.
  4. return a `SelectionInvertingIoMap` carrying the segment table.
- `map_reference_forward` / `map_reference_backward` / `projection_read` — ported
  from `TextHighlighting`.

### Register in `Projectured.jl`

`include` the file; `using .SelectionInvertingModule: SelectionInverting`; export.

---

## Phase 2 — Wire the console backend to use it

**✅ DONE (verified):** `SelectionInverting()` is inserted at the end of the console pipeline (`package/example/src/projection/Json.jl:28`, in `make_json_console_projection_example`). The backend's inline selection/reverse-video rendering is removed — `Console.jl` has no `_ANSI_REVERSE`, `reverse` flag, or `_selection_flat` call left (only doc comments at :32-34, :165-169, :215 explaining the new arrangement). The shared `text_selection_flat`/`_text_cursor_flat` helper lives in the Text domain (`Text.jl:606-636`) and is consumed by both projection and (formerly) backend — one source of truth.

### File: `program/src/backend/Console.jl`

- Insert `SelectionInverting` at the **end** of the console projection pipeline
  (after whatever produces the `TextText`), so the backend receives a `TextText`
  whose selected spans are already inverted.
- Replace the inline selection rendering: drop `_ANSI_REVERSE` / the `reverse`
  flag plumbing and the per-frame `_selection_flat` call in the renderer. The span
  renderer now just emits `_sgr_foreground` + `_sgr_background` per span
  (`Console.jl:146–148`) — the inversion is already in the colors.
- Keep one shared copy of `_selection_flat` / `_text_cursor_flat` (now used by the
  projection); the backend no longer computes selection itself.

This is the "proper text navigation in the console backend": the caret/selection is
produced by a principled, tested projection rather than ad-hoc backend code, and
multi-span range selections fall out of the same machinery.

---

## Phase 3 — Tests

**✅ DONE (verified):** `package/test/src/projection/SelectionInvertingTest.jl` (registered at `ProjecturedTest.jl:62`) covers: pass-through `nothing` selection, range inverts exactly `[start,stop)`, span split at both boundaries, `fill_color=nothing` → `default_bg`, caret widening mid-span / offset 0 / end-of-text synthesized block, `block_cursor=false` zero-width caret, selection round-trip (`map_reference_backward`∘`map_reference_forward`), reader char-range shift, and multi-span out-of-range untouched.

Per [testing.md](../testing.md) / CLAUDE.md, targeted helpers (not `test_all`):

- **Inversion** — a caret in the middle of a span inverts exactly one character;
  a range selection inverts exactly `[start, stop)`; spans are split at the right
  boundaries; out-of-range spans are untouched; `nothing` selection ⇒ output equals
  input.
- **Defaults** — a span with `fill_color = nothing` gets `default_bg` as the
  inverted foreground's background (no transparent inversion).
- **Caret edges** — caret at offset 0, mid-span, span boundary, and end-of-text
  (synthesized trailing block).
- **Invertibility** — `map_reference_backward(map_reference_forward(r)) == r` for
  cursor and range references that straddle a split (reuse the `TextHighlighting`
  round-trip test shape).
- **Console** — `test_repl` / a console-render snapshot shows the selected slice
  inverted and the caret as a block; navigation moves the inverted block.

---

## Implementation order

**✅ DONE (verified):** All four ordered steps are complete — shared helper extracted (`Text.jl:606-636`), projection built, console pipeline wired & inline rendering deleted, tests written.

1. Extract `_selection_flat` / `_text_cursor_flat` into a shared helper (no
   behaviour change; console keeps working).
2. Phase 1 — `SelectionInverting` projection (copy `TextHighlighting`'s segment/
   reader scaffolding; swap the segmentation source and the restyle).
3. Phase 2 — wire it into the console pipeline; delete the backend's inline
   selection rendering.
4. Phase 3 — tests (inversion math first, then invertibility, then console).

## Risks / caveats

- **Mostly extraction, not green-field.** The selection-resolution and reverse-video
  behaviour already exist in `Console.jl`; the work is generalizing them into a
  bidirectional projection and removing the backend special case. Honest scope:
  one new projection file + a console refactor + a shared helper.
- **Don't double up on SDL/web.** Those pipelines already draw a cursor rect in
  `TextToGraphics`; `SelectionInverting` is for Text-domain backends (console) and
  is *opt-in* elsewhere. Inserting it into a graphics pipeline would render both an
  inverted run *and* a cursor rect.
- **Explicit background required.** Inversion needs a concrete `default_bg` where
  the input span has none; pick a theme background constant so console and graphics
  agree.
- Keep the three selection-flat computations (`Console`, `TextToGraphics`, this
  projection) on **one** helper to avoid drift.

## Outcome

Selection becomes ordinary span color via a small, bidirectional `Text → Text`
projection. The console backend renders it for free and loses its bespoke
selection code, and any Text-domain renderer gains a portable, inverse-video
selection highlight.
</content>
