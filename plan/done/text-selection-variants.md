# Text selection variants — three geometries, cleanly separated

**Status:** DONE — T1–T4 landed with the flat-cursor work (squashed into `eb475113`,
"Flat text caret (TextRangeReference) + variants + console lowering"). T5 (the stream
render for a multi-line character selection) is deferred by design; it is tracked by
[text-range-reference-flat-cursor.md](../done/text-range-reference-flat-cursor.md) and
has no producer yet (see **Outcome** below).

## Goal

Define **three** text-domain selection variants as first-class, sibling reference
step types — even though only two are exercised right away. All three are
reserved in the codebase (type + render path) so the third can be wired to a
gesture later without re-plumbing.

The trigger was the question "how many different text range selections should we
have?" The answer only becomes clean once two things the phrase "text range
selection" conflates are pulled apart:

- **Meaning** — *what* is selected (the reference's identity). Only two things can
  be selected: **characters** in a text leaf, or a **whole subtree**.
- **Geometry** — *how* the selection is painted. Three distinct shapes: stream,
  column box, bounding box.

These do not map 1:1, which is exactly why a single "range" concept felt wrong for
a selected node. The taxonomy below assigns each variant its own reference type,
geometry, cursor behaviour, and producer.

## The three variants

| # | Type (target name) | Geometry | Cursor behaviour | Selects | Produced by | Status |
|---|---|---|---|---|---|---|
| 1 | `TextRangeReference` | **stream** — follows the flow through newlines/indentation; ragged first & last line, one rect per line | *is* the character cursor; char motion navigates within it. `start == stop` = caret | characters in a text leaf | text cursor nav / click; forward-projection of a leaf char selection | **DONE** (mechanics owned by [text-range-reference-flat-cursor.md](../done/text-range-reference-flat-cursor.md)); multi-line *stream* render still a single bbox — see T5 |
| 2 | `TextColumnReference` | **column box** — left edge = column of `start`, right edge = column of `stop`, painted on every row in the span (a true rectangle regardless of glyph content) | block / multi-caret mode; edits lower to a per-row `CompoundOperation` | a rectangular block of text across lines | a future column-select gesture (e.g. Alt+drag) | **RESERVED** — type + `_compute_column_geo` render land (unit-tested); no producer yet |
| 3 | `TextSpanReference` | **bounding box** — a single rect enclosing *all* glyphs in the flat span (min-x…max-x, top…bottom) | structural: char motion declines and exits to tree navigation | a whole subtree | lowered from the ∅ structural node selection at the syntax→text seam | **DONE** — renamed from `TextRectangularReference`; behaviour unchanged |

All three are siblings of the same shape:

```julia
@cell_struct struct Text<Variant>Reference <: ReferenceStep
    start::Int   # flat 0-based offset into the TextBlock's concatenated stream
    stop::Int
end
ReferenceModule.step_kind(::Text<Variant>Reference) = :structural   # terminal, non-descending
ReferenceModule.evaluate_step(step, block) = (step.start, step.stop)
```

They differ **only** in render geometry and cursor behaviour — never in the data
they carry — which is why dispatch is on the *type*, consistent with the existing
range-vs-box split rationale in the flat-cursor plan ("distinct type because the
two route to opposite behaviours").

## Why not one type with a `mode` field

Considered and rejected. A `mode::Symbol` box would force every render and reader
site to branch on the field, and would defeat the type-checked invariant that a
*structural node highlight* (variant 3) can never be mistaken for a *character
cursor* (variant 1) or a *block edit* (variant 2). The codebase already dispatches
selection behaviour on step type (`_is_structural_selection`, the forward maps,
the highlight extractor); three types keep that uniform. The shared
`(start, stop)` shape is small enough that duplication costs nothing.

## Naming decision — RESOLVED (retire the ambiguous name)

The old `TextRectangularReference` actually drew the **glyph bounding box** (the
extractor accumulates one min/max rect over every overlapping segment) — *not* a
column box. Meanwhile "rectangular selection" universally means the **column** box
(Sublime/VS Code column select, Emacs `rectangle-mark`). The name was ambiguous:
both a bounding box and a column box are rectangles.

**Resolution adopted — retire the ambiguous name; use three maximally-distinct,
self-describing names:**

- `TextRangeReference` — stream / linear (new; flat-cursor plan).
- `TextColumnReference` — column / block box (new; reserved).
- `TextSpanReference` — bounding box (a **pure rename** of the old
  `TextRectangularReference`; same geometry, same behaviour, same call sites).

`TextRectangularReference` was **not** reused for the column box (reusing a just-
vacated name is a review footgun) — it is retired entirely.

## Render geometry — three functions

The text-to-graphics layer gets one geometry function per variant.

- **stream** (variant 1) — `_compute_stream_geo` → a *vector* of per-row rects,
  ragged on the first and last row, full on interior rows. **NOT built** (T5,
  deferred). The gap: the caret currently reuses the single-bbox `_compute_span_geo`,
  which is correct for a caret (degenerate) and for a node, but boxes the whole
  region for a *multi-line character* selection. Net-new render work; no producer
  makes a multi-line character selection today, so it is deferred, not blocking.
- **bounding box** (variant 3) — the existing extractor, **renamed
  `_compute_highlight_geo` → `_compute_span_geo`** (T2). **DONE.**
- **column box** (variant 2) — `_compute_column_geo` → per-row rects clipped to
  `[col(start), col(stop)]`, one per row in the span. **BUILT** as a reserved code
  path with no producer (T3), asserted by a hand-built-selection unit test.

## Relationship to the flat-cursor plan

[text-range-reference-flat-cursor.md](../done/text-range-reference-flat-cursor.md) is
the implementation vehicle for **variant 1** (the flat character cursor, its motion,
its `ReplaceTextRangeOperation`, and the S1–S8 migration). This plan does **not**
duplicate that work; it:

1. Owns the **taxonomy** (meaning vs geometry; the three-variant table).
2. Owns the **rename** of variant 3 (`TextRectangularReference` → `TextSpanReference`).
3. Owns **reserving** variant 2 (`TextColumnReference` type + `_compute_column_geo`).
4. Flags the **stream-geometry render gap** that the flat-cursor plan implicitly
   assumes away (the caret reuses the bbox `_compute_span_geo`, fine for a caret,
   insufficient for a multi-line stream selection).

The rename (T1) landed **before** the flat-cursor migration so that work built on
the final names.

## Staged implementation — all committed scope complete

Each stage was one commit; the narrowest test ran after each.

- [x] **T1 — rename variant 3.** `TextRectangularReference.jl` →
  `TextSpanReference.jl`; module, type, `show`, and all call sites renamed. Pure
  rename, no behaviour change. Verified by `test_syntax_tree_selection` and a real
  `using ProjecturedVisual`.
- [x] **T2 — rename the render fn.** `_compute_highlight_geo` → `_compute_span_geo`
  (3 sites in `TextToGraphics.jl`). No behaviour change.
- [x] **T3 — reserve variant 2.** Added `TextColumnReference` (type + module +
  `include` in `ProjecturedVisual.jl` + the two `ProjecturedDomain.jl` aliases +
  the visual/kernel doc mentions) and `_compute_column_geo`. Wired into the
  highlight extractor so a `TextColumnReference` selection *renders* as a column
  box. No gesture produces it yet — asserted with a hand-built selection in
  `TextToGraphicsTest.jl` ("TextColumnReference reserves the column-box geometry
  (variant 2)").
- [x] **T4 — behaviour hooks.** `_is_structural_selection` treats both
  `TextSpanReference` **and** `TextColumnReference` as structural, so char motion
  declines rather than corrupting a column selection. The block-edit reader for
  variant 2 is documented future work.
- [ ] **T5 — variant 1 (stream).** DEFERRED. `_compute_stream_geo` (ragged per-row
  rects) is unbuilt; a multi-line character selection still renders as the single
  `_compute_span_geo` bbox. No producer creates a multi-line character selection
  today, so this is a latent render gap, not a live bug. Owned by the flat-cursor
  plan; pick it up when a shift+arrow (or drag) multi-line character selection is
  actually wired.

## Outcome (what actually landed)

- Three sibling reference-step files under `package/visual/main/text/`:
  `TextRangeReference.jl`, `TextColumnReference.jl`, `TextSpanReference.jl` — each
  `@cell_struct struct … <: ReferenceStep` with `start::Int`/`stop::Int`,
  `step_kind = :structural`, `evaluate_step = (start, stop)`, and a distinct `show`
  glyph. All three `using ..CellStructModule` (the cell-layer restructure that
  `main` picked up moved `@cell_struct` there).
- `TextToGraphics.jl`: `_compute_span_geo` (bbox, renamed) and `_compute_column_geo`
  (per-row column rects, new/reserved).
- `Text.jl`: `_is_structural_selection` routes both box variants structurally.
- Domain/test wiring: `ProjecturedDomain.jl` aliases, `ProjecturedVisual.jl`
  include, `ProjecturedVisualTest.jl` inventory entry, and the column-render unit
  test all present and green (`test_visual` 47137 / 0 fail at merge).
- **Doc cleanup done while finishing this plan** (the T1 touch-list missed them):
  the living architecture/reference docs `package/kernel/doc/architecture.md`,
  `package/kernel/doc/reference.md`, and `documentation/architecture.md` named the
  retired `TextRectangularReference` as if current — updated to the sibling trio.
  `plan/done/*` mentions of the old name are historical records and were left as-is.

## Deferred / future work

- **Variant 2 producer.** What gesture creates a column selection (Alt+drag?
  Ctrl+Alt+arrows?) and how its edits lower (per-row `CompoundOperation` of
  `ReplaceTextRangeOperation`s sharing one input string, else decline). The type +
  render exist so this is additive, not structural.
- **Variant 1 stream render (T5).** `_compute_stream_geo` for a multi-line character
  selection, wired in place of the bbox for a non-degenerate multi-line
  `TextRangeReference`. Tracked with the flat-cursor plan.
