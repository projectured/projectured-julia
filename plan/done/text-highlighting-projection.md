# `TextHighlighting` projection — regex match highlighter

## Goal

A Text → Text primitive projection that restyles the regex **matches** inside a
`TextText` — the "highlight all" of a search box — leaving every line in place.
Where [`TextFiltering`](../../program/src/projection/primitive/TextFiltering.jl)
*drops* non-matching rows, `TextHighlighting` keeps all rows and only paints a
background swatch behind the matched substrings.

It is the structural sibling of
[`WordWrapping`](../../program/src/projection/primitive/WordWrapping.jl): both
split a `TextString` into adjacent sub-spans and need a piecewise offset table
to stay invertible. `TextHighlighting` is `WordWrapping` **minus the inserted
newlines** — it splits a span at match boundaries and restyles the matched
sub-spans, but inserts and removes nothing, so every character of the input
survives exactly once and in order.

| projection      | output vs input          | mapping table                       |
|-----------------|--------------------------|-------------------------------------|
| `TextFiltering` | subset of elements       | `kept::Vector{Int}` (identity chars)|
| `WordWrapping`  | split spans + newlines   | `WrapSeg` (offset table)            |
| `TextHighlighting` | split spans (restyled)| `HighlightSeg` (offset table)       |

## Highlight mechanism — `fill_color` background swatch (+ a small renderer extension)

The highlight is a **background swatch** behind the matched glyphs (the classic
search "highlight all" yellow box), driven by the span's **`fill_color`**. This
requires a one-site extension to the renderer, included in this plan (see
**Extending `TextToGraphics`** below).

**Why this is safe / why it needs the extension (verified):** the current text
renderer colors glyphs only — in
[`TextToGraphics`](../../program/src/projection/primitive/TextToGraphics.jl) the
only span style consumed is `span.font_color`
([:387](../../program/src/projection/primitive/TextToGraphics.jl#L387),
[:604](../../program/src/projection/primitive/TextToGraphics.jl#L604)); a span's
`fill_color` is not rendered today and `GraphicsText` has no background field. But
`TextString.fill_color` **defaults to `nothing`**
([Text.jl](../../program/src/document/Text.jl#L154)), so it is a ready-made
sentinel: render a background rect **only when `fill_color !== nothing`**. Every
existing span keeps `fill_color === nothing`, so the extension changes nothing for
current documents — it only lights up spans that a projection (this one) opts in
by setting a fill.

`TextHighlighting` therefore sets `fill_color` (not `font_color`) on matched
sub-spans; glyph color is left untouched so matched text stays readable on the
swatch.

## What a "match" is

A match is a non-overlapping `Regex` hit found by `eachmatch` **within a single
`TextString`'s `content`** (per span). For each input span the content is split
into alternating *unmatched* / *matched* sub-spans:

- matched sub-spans get a new `TextString` with the original style but
  `fill_color` set to the highlight color (a background swatch);
- unmatched sub-spans copy the original style verbatim;
- a span with **no** matches is emitted **unchanged** (reuse the original
  object — no allocation, identity char mapping);
- `TextNewline` / `TextSpacing` / `TextGraphics` pass through untouched.

### MVP scope

Matching is **per span**, mirroring the span-delimited-line simplification in
`TextFiltering` and `WordWrapping`. For the common one-span-per-line text emitted
by `SyntaxToText` and the example documents this is identical to per-line
matching. A match that would **cross a span boundary** (matching the concatenated
line) needs splitting one match across spans and is deferred.

## Extending `TextToGraphics` to render `fill_color`

Make the renderer paint a background rect behind any span whose `fill_color` is
set. Backward-compatible because the default is `nothing`.

Both span-layout sites must be updated:

1. **Eager path** — the per-line segment around
   [TextToGraphics.jl:418-424](../../program/src/projection/primitive/TextToGraphics.jl#L418-L424),
   where `seg_x`, `cy`, `seg_w`, `seg_h` are already in hand. Before the
   `push!(result, _make_sdl(line, seg_x, cy, …))`, add:

   ```julia
   fill = span.fill_color            # cell value: StyleColor or nothing
   if fill isa StyleColor
       fr, fg, fb, fa = _rgba(fill)
       push!(result, GraphicsRect(seg_x, cy, seg_w, seg_h, fr, fg, fb, fa))
   end
   ```

   Pushing the rect **before** the text makes it paint behind (the canvas is
   `layout_none`, painter's order = list order). `GraphicsRect` is already
   imported and used (cursor), so no new wiring.

2. **Paragraph path** — `_layout_paragraph`
   ([:595-616](../../program/src/projection/primitive/TextToGraphics.jl#L595-L616))
   has the same shape (`col = span.font_color` at
   [:604](../../program/src/projection/primitive/TextToGraphics.jl#L604)); add the
   same rect-before-text there.

Points to verify during implementation:

- **Hit-testing is unaffected.** Clicks resolve through `coord_map`
  (`SegCoord`, built only from text/image segments), not the `result` draw list,
  so non-interactive background rects do not perturb selection mapping.
- **`overlapping_elements` flag.** The canvas is built with
  `overlapping_elements=false`
  ([:466](../../program/src/projection/primitive/TextToGraphics.jl#L466)); a rect
  beneath text is an intentional overlap. Confirm the flag does not cull or
  reorder the rect under `layout_none`; set it `true` if rendering drops the
  swatch.
- **Swatch box.** Use the measured segment box `seg_w × seg_h` at `(seg_x, cy)`.
  Optional `radius` / `padding` on the swatch is a follow-up.

This extension is independently useful (any document can now give a span a
background) and is the only renderer change `TextHighlighting` needs.

## Files

- `program/src/projection/primitive/TextToGraphics.jl` — render `fill_color` as a
  background `GraphicsRect` (the extension above).
- **New** `program/src/projection/primitive/TextHighlighting.jl` — module
  `TextHighlightingModule`, exporting `TextHighlighting`, `TextHighlightingIoMap`,
  `HighlightSeg`.
- `program/src/Projectured.jl` — `include(...)` next to `TextFiltering.jl`
  (~line 109), `using .TextHighlightingModule: TextHighlighting,
  TextHighlightingIoMap, HighlightSeg`, and an `export`.
- **New** `example/src/document/TextHighlighting.jl` +
  `example/src/projection/TextHighlighting.jl`, registered in
  `example/src/ProjecturedExample.jl` and `example/src/Examples.jl`
  (mirror the `text_filtering_example` wiring).
- **New** `test/src/projection/TextHighlightingTest.jl`, included +
  `test_text_highlighting()` registered/exported in
  `test/src/ProjecturedTest.jl`.

## Projection struct

Reactive pattern in a `Cell` (live highlighting; `nothing` = no highlights =
pass-through), plus the highlight color. Mirror `TextFiltering`'s constructors.

```julia
struct TextHighlighting <: Projection
    pattern::Cell           # Cell{Union{Regex,Nothing}} — reactive; nothing = no highlights
    color::StyleColor       # fill_color (background swatch) applied to matched substrings
end

TextHighlighting(pattern::Cell; color::StyleColor=color_yellow) = TextHighlighting(pattern, color)
TextHighlighting(pattern::Regex; color::StyleColor=color_yellow) = TextHighlighting(Cell(pattern), color)
TextHighlighting(pattern::AbstractString; color::StyleColor=color_yellow) = TextHighlighting(Cell(Regex(pattern)), color)
TextHighlighting(; pattern=nothing, color::StyleColor=color_yellow) =
    TextHighlighting(pattern isa Cell ? pattern : Cell(pattern), color)
```

## IoMap

`HighlightSeg` is `WrapSeg` renamed — reuse its shape and the forward/backward
logic verbatim:

```julia
struct HighlightSeg
    out_index::Int      # 1-based output element index
    in_span::Int        # 1-based input element index
    in_char_start::Int  # 0-based char offset within in_span
    length::Int         # chars in this sub-span
end

struct TextHighlightingIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    segs::Cell          # Cell{Vector{HighlightSeg}}
end
```

One `HighlightSeg` per emitted output `TextString` sub-span (matched **and**
unmatched, and the full span when unsplit). Pass-through non-text elements get no
seg, exactly as in `WordWrapping`.

## Print

Mirror `WordWrapping.projection_print`: one thunk builds both the output element
list and `segs`; the output `TextText.selection` is a `Cell` that forward-maps
the input selection so `TextToGraphics` still draws the cursor.

```julia
function projection_print(p::TextHighlighting, recursion, text::TextText, ctx)
    pattern_cell = p.pattern
    color = p.color
    both = Cell(() -> _highlight(text, pattern_cell[], color))   # (elements, segs)
    elements_cv = CellVector(() -> both[][1])
    segs_cell = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(segs_cell[], text.selection))
    output = TextText(elements_cv, out_selection)
    TextHighlightingIoMap(p, text, output, segs_cell)
end
```

`_highlight` walks `text.elements`. For a `TextString` it runs `eachmatch`,
splitting `content` into alternating unmatched/matched runs, appending a sub-span
+ `HighlightSeg` for each (matched runs use a `_make_span` helper that copies the
original style but sets `fill_color = color`; this is `WordWrapping._make_span`
with a fill-color parameter). A `nothing` pattern, or a span with no matches,
emits the span unchanged with one full-length seg. Non-text elements pass through.

## Selection / reference mapping

The path shape (`elements[span].content{char}`) and the seg-offset arithmetic are
**identical to `WordWrapping`** — copy `_forward_map`, `map_reference_forward`,
`map_reference_backward`, the two `projection_read` methods
(`ReplaceSelectionOperation`, `StringReplaceRangeOperation`, which shift the char
range by `in_char_start` for sub-spans starting mid-span), the event pass-through
`projection_read(...) = op`, and the `_parse_text_elem_path` / `_text_elem_range`
/ `_text_elem_path` helpers. The only behavioral difference from `WordWrapping` is
that there are no inserted newlines between sub-spans, but the boundary-duplicate
convention (prefer the start of the next sub-span at an exact boundary) carries
over unchanged.

## Edge cases

- **Empty / zero-width matches** (`r"x*"`, `r""`, `r"(?=foo)"`). `eachmatch`
  yields zero-length matches; **skip** them — never emit a zero-length sub-span
  (it would be an invisible, un-clickable span) and make sure the scan advances so
  there is no infinite loop. The companion guard is the one `WordWrapping` already
  trusts: every emitted sub-span has `length ≥ 1`.
- **No-match span / `nothing` pattern** → span emitted unchanged (object reused),
  selection mapping is identity for it.
- **Whole-span match** → a single highlighted sub-span (new object, filled).
- **Adjacent / back-to-back matches** → handled by the alternating walk; no empty
  unmatched run is emitted between them.
- **Cursor on a highlighted match still edits the original text** — the read ops
  remap the (split) output span + offset back to the single input span, so typing
  over a highlighted match flows upstream correctly.

## Pipeline wiring (example)

```julia
function make_text_highlighting_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        TextHighlighting(r"dolor"),     # yellow swatch behind every "dolor"
        TextToGraphics(measure=measure),
    )
end
```

Composition notes (the seg tables compose through `SequentialProjection`):

- **Highlight before wrap:** `… → TextHighlighting → WordWrapping → TextToGraphics`
  — highlight is semantic (match the source text), wrap is visual; wrapping a
  highlighted span just splits it further (the swatch follows each piece).
- **Grep with highlighted hits:** `TextFiltering(p) → TextHighlighting(p)` with
  the *same* pattern keeps only matching lines **and** highlights the match within
  them — the natural search experience. Sharing one `Cell` pattern across both
  makes a single search box drive filter + highlight together.

## Tests (`test/src/projection/TextHighlightingTest.jl`)

1. **Highlights matches** — span `"alpha beta alpha"`, `r"alpha"` → output
   sub-spans `["alpha", " beta ", "alpha"]`; assert the 1st and 3rd have
   `fill_color == color`, the middle keeps `fill_color === nothing`.
2. **No-match span is unchanged** — output is the single original span object
   (`fill_color === nothing`).
3. **`nothing` pattern is pass-through** — output element list `==` input.
4. **Selection round-trip** — every position in every emitted sub-span
   round-trips forward → backward and back (the `WordWrapping` seg-table test,
   minus the newline cases).
5. **Reader remap** — a `StringReplaceRangeOperation` on a matched sub-span that
   starts mid-span backward-maps to the right input span with the char range
   shifted by `in_char_start`.
6. **Empty-match guard** — `r"a*"` over `"banana"` neither hangs nor emits a
   zero-length sub-span (every seg `length ≥ 1`).
7. **Reactive re-highlight** — mutate `pattern[]` and assert the output spans /
   segs recompute (force the cells; optionally `perf_counters()`).
8. **Renderer: `fill_color` draws a background rect** (in `TextToGraphicsTest`).
   A span with `fill_color` set emits a `GraphicsRect` (same x/y/w/h as its
   `GraphicsText`, the matching RGBA) positioned **before** the text in the draw
   list; a span with `fill_color === nothing` emits **no** rect. Guards the
   backward-compatibility claim.

Iterate with `test_text_highlighting()` + `test_text_to_graphics()`, and the
chained example through `test_printer` / `test_selection`; use
`walk_printer_output` / `explore_selections` for low-noise checks per
[CLAUDE.md](../../CLAUDE.md) / [guide/testing.md](../../guide/testing.md).

## Deferred / out of scope

- **Cross-span / per-line matching** (a match spanning more than one input span).
  MVP matches per span.
- **Multiple patterns / colors** (e.g. different colors per capture group or per
  pattern). MVP is one pattern, one color.
- **Glyph restyle in addition to the swatch** (bold or recolored matched text).
  Recoloring `font_color` is trivial to add later; `font`/bold would change glyph
  metrics and interact with `WordWrapping`'s measurer, so defer that.
- **Rounded / padded swatch** (`radius`, inset). The renderer extension uses the
  tight measured box; corner radius and padding are a follow-up.
- **Sticky cursor under live re-highlight** — filling never drops a character, so
  unlike `TextFiltering` the selection always has an image; no special handling
  expected, but verify in test 7.

## Open questions

- **Default highlight color.** Proposed `color_yellow` (classic search swatch;
  readable with the default black glyphs on top). Confirm, or prefer a softer
  solarized accent.
- **Swatch height — glyph box vs. full line height.** Proposed the measured
  segment box (`seg_h`); using `line_h` would give a gap-free full-line bar when a
  line mixes span heights. Pick when a mixed-height line use case appears.
