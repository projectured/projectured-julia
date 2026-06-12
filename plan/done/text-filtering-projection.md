# `TextFiltering` projection — regex line filter

## Goal

A Text → Text primitive projection that keeps only the lines of a `TextText`
whose text matches a regex, dropping the rest. The grep of the projection
stack: `… → SyntaxToText → TextFiltering → TextToGraphics`. Like `grep`, the
surviving lines are unchanged — same spans, same styling, same character
content — so the projection is invertible with an identity character mapping
and only the element (span) index is remapped.

This is the `TextText`-granularity sibling of the generic
[`FilteringProjection`](../../program/src/projection/generic/Filtering.jl)
(which filters `CellVector` elements by a predicate), built on the same
`kept_indices` idea but operating on the `elements` axis of a `TextText` and
emitting a `TextText`. It follows the module/IoMap conventions of
[`WordWrapping`](../../program/src/projection/primitive/WordWrapping.jl) and
[`TextLineNumbering`](../../program/src/projection/primitive/LineNumbering.jl).

## What a "line" is

`TextText.elements` is a flat sequence of `TextString` / `TextNewline` /
`TextSpacing` / `TextGraphics` (see
[guide/document/text.md](../../guide/document/text.md) and
[program/src/document/Text.jl](../../program/src/document/Text.jl)). A *logical
line* is the run of elements up to and **including** its terminating
`TextNewline`; the trailing line may have no newline. Each line "owns" its
trailing newline.

- The line's **match string** is the concatenation of the `content` of the
  `TextString` elements in the line (non-`TextString` elements — newline,
  spacing, embedded graphics — contribute the empty string).
- A line is **kept** iff `occursin(pattern, match_string)` (XORed with the
  `invert` flag). When a line is kept, **all** of its member elements,
  including its trailing newline, are emitted unchanged. When dropped, the
  whole run including its newline is removed.

Because each line owns its trailing newline, dropping a line never leaves a
stray leading newline or a doubled newline in the output — the output is again
a well-formed `TextText`.

### MVP scope on `\n`

`TextLineNumbering` and `WordWrapping` both also split on `'\n'` characters
embedded **inside** a `TextString`. Splitting a span mid-content breaks the
identity character mapping (it would need a `WrapSeg`-style sub-span offset
table). For the MVP, **lines are delimited by `TextNewline` elements only**;
embedded `\n` inside a span is treated as ordinary line content for matching
purposes and the span is kept/dropped whole. This matches how `SyntaxToText`
and the existing example documents (e.g.
[example/src/document/LineNumbering.jl](../../example/src/document/LineNumbering.jl))
emit text — one span per line, newline as a separate element. Splitting
embedded `\n` is a deferred follow-up (see **Deferred**).

## Files

- **New** `program/src/projection/primitive/TextFiltering.jl` — module
  `TextFilteringModule`, exporting `TextFiltering`, `TextFilteringIoMap`.
- `program/src/Projectured.jl` — `include(...)` next to the other text
  projections (after `WordWrapping.jl`, ~line 108), `using
  .TextFilteringModule: TextFiltering, TextFilteringIoMap`, and an `export`.
- **New** `example/src/document/TextFiltering.jl` and
  `example/src/projection/TextFiltering.jl`, registered in
  `example/src/ProjecturedExample.jl` and `example/src/Examples.jl`
  (mirror the `line_numbering_example` / `word_wrapping_example` wiring).
- **New** `test/src/projection/TextFilteringTest.jl`, included +
  `test_text_filtering()` registered/exported in
  `test/src/ProjecturedTest.jl`.

## Projection struct

Make the pattern a reactive `Cell` so a live search box re-filters for free; a
plain `Regex`/`String` constructor wraps it. An empty / `nothing` pattern means
"keep everything" (pass-through), which is the natural default.

```julia
struct TextFiltering <: Projection
    pattern::Cell    # Cell{Union{Regex,Nothing}} — reactive; nothing = keep all
    invert::Bool     # true = keep NON-matching lines (grep -v)
end

TextFiltering(pattern::Regex; invert::Bool=false) = TextFiltering(Cell(pattern), invert)
TextFiltering(pattern::AbstractString; invert::Bool=false) = TextFiltering(Cell(Regex(pattern)), invert)
TextFiltering(; pattern=nothing, invert::Bool=false) =
    TextFiltering(pattern isa Cell ? pattern : Cell(pattern), invert)
```

(Case-insensitivity, multiline, etc. live in the `Regex` flags the caller
builds — the projection does not interpret them.)

## IoMap

```julia
struct TextFilteringIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    kept::Cell        # Cell{Vector{Int}} — input element index for each output element
end
```

`kept[j]` is the 1-based input `elements` index of the j-th output element.
Character offsets are unchanged, so unlike `WrapSeg` we only need the element
index, not a `(start, length)` per span.

## Print

Mirror `WordWrapping.projection_print`: one thunk computes both the output
element list and the `kept` table so they invalidate together; the output
`TextText.selection` is a `Cell` that forward-maps the input selection so
`TextToGraphics` can still draw the cursor in filtered coordinates.

```julia
function projection_print(p::TextFiltering, recursion, text::TextText, ctx)
    both = Cell(() -> _filter(text, p.pattern[], p.invert))   # (elements, kept)
    elements_cv = CellVector(() -> both[][1])
    kept_cell   = Cell(() -> both[][2])
    out_selection = Cell(() -> _forward_map(kept_cell[], text.selection))
    output = TextText(elements_cv, out_selection)
    TextFilteringIoMap(p, text, output, kept_cell)
end
```

`_filter` scans `text.elements`, groups them into logical lines (cutting after
each `TextNewline`), builds the per-line match string, and for each kept line
appends its member elements to the output list and their input indices to
`kept`. A `nothing` pattern keeps every line (identity filter, `kept = 1:n`).

## Selection / reference mapping

The path shape is identical to `WordWrapping`'s and `LineNumbering`'s:
`elements[span].content{char}` (a `ConcreteReferencePath` of
`FieldReference("elements")` → `RangeReference` → `FieldReference("content")` →
`RangeReference`). **Reuse the `_parse_text_elem_path` / `_text_elem_path`
helpers verbatim** — only the element index is remapped; the char offset passes
through unchanged.

- `map_reference_forward(p, iomap, ref)` — parse `(in_span, char)`; find
  `j = findfirst(==(in_span), iomap.kept[])`; `nothing` if the line was
  filtered out (selection has no image in the output); else
  `_text_elem_path(j, char)`.
- `map_reference_backward(p, iomap, ref)` — parse `(out_span, char)`; return
  `_text_elem_path(iomap.kept[][out_span], char)` (bounds-checked).
- `projection_read(p, iomap, op::ReplaceSelectionOperation)` and
  `projection_read(p, iomap, op::StringReplaceRangeOperation)` — backward-map
  the element index, keep the char offset/range, rebuild the op (mirror
  `WordWrapping`). Char ranges stay within a single span, so no cross-span
  rejection is needed.
- `projection_read(::TextFiltering, ::TextFilteringIoMap, op) = op` — forward
  every other event (KeyDown/KeyPress/…) upstream.

## Edge cases

- **No line matches** → empty `TextText` (`kept = []`). Downstream must tolerate
  an empty text (it already does for empty documents).
- **Selected line gets filtered after an edit.** Editing a kept line so it no
  longer matches makes it vanish on the next reactive recompute, and
  `map_reference_forward` for that selection returns `nothing` (no image). MVP
  behavior: the forward selection is dropped (cursor not drawn) until the user
  selects a still-visible line; document this. A "sticky cursor" that clamps to
  the nearest surviving line is a possible follow-up but adds policy.
- **Empty / blank lines.** Match string is `""`; kept only if the pattern
  matches empty (or, with `invert`, only if it does *not*). Expected `grep`
  semantics.
- **`nothing` pattern** → pass-through; `kept = collect(1:n)`; selection is
  identity. Lets the projection sit permanently in a pipeline with the filter
  "off" until a pattern is set on the `Cell`.

## Pipeline wiring (example)

`TextFiltering` is Text → Text, so it slots anywhere a `TextText` flows, before
`WordWrapping`/`TextToGraphics`:

```julia
function make_text_filtering_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        TextFiltering(r"o"),                  # keep lines containing an 'o'
        TextToGraphics(measure=measure),
    )
end
```

Interaction with `LineNumbering` is worth a note in the example:
- `LineNumbering` **before** `TextFiltering` → surviving lines keep their
  **original** line numbers (grep -n style; numbers become discontinuous).
- `LineNumbering` **after** `TextFiltering` → output is **renumbered**
  contiguously (1..k).
Pick per use case; the example should demonstrate the grep -n ordering since
that is the more useful one and exercises filtering of projection-inserted
prefix spans.

## Tests (`test/src/projection/TextFilteringTest.jl`)

1. **Keeps matching lines, drops the rest** — a multi-line `TextText`, assert
   the output spans are exactly the matching lines (and their newlines), in
   order.
2. **`invert=true`** — keeps exactly the complementary set.
3. **`nothing` pattern is pass-through** — output element list `==` input.
4. **Selection round-trip** — for a cursor on a kept line, forward → backward
   returns the original `(span, char)`; for a cursor on a filtered line,
   forward returns `nothing`.
5. **Reader remap** — a `ReplaceSelectionOperation` / `StringReplaceRangeOperation`
   on an output span backward-maps to the correct input span index with the
   char offset/range preserved.
6. **Reactive re-filter** — mutate `pattern[]` (or input span content) and
   assert the output element list and `kept` recompute (force the cells; see
   [guide/reactive-cells.md](../../guide/reactive-cells.md)). Optionally use
   `perf_counters()` to assert only the filter/layout cells invalidate.

Run the narrow scope while iterating: `test_text_filtering()`, and the standard
text-layer sweep (`test_text_to_graphics()` / the chained example) once green.
Use `walk_printer_output` / `explore_selections` on the new example for
low-noise iteration per [CLAUDE.md](../../CLAUDE.md) / [guide/testing.md](../../guide/testing.md).

## Deferred / out of scope

- **Embedded-`\n` line splitting.** Splitting a `TextString` that contains
  `'\n'` into multiple filterable lines (needs a `WrapSeg`-style sub-span
  offset table and non-identity char mapping). MVP delimits on `TextNewline`
  elements only.
- **Sticky cursor** when the selected line is filtered out (see edge cases).
- **Match highlighting** (styling the matched substring on kept lines) — a
  separate styling pass, not this projection.
- **Reactive search box UI** — this projection already accepts a `Cell`
  pattern; wiring a widget/text-field that drives it is a workbench task.
- **Context lines** (grep `-A`/`-B`/`-C`) — would keep non-matching neighbors;
  out of scope for the first cut.

## Open questions

- Should `pattern[] === nothing` mean "keep all" (proposed) or "keep none"?
  Proposed keep-all so the projection is a no-op when idle. Confirm before
  implementing.
- Should the match string include a representation of `TextGraphics` /
  `TextSpacing` (e.g. an object-replacement char) so a line that is only an
  image can be matched? MVP treats them as empty; revisit if a consumer needs
  to filter image-only lines.
