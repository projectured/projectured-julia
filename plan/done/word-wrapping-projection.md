# Move word wrapping out of `TextToGraphics` into `WordWrapping`

## Outcome

`WordWrapping` is now the single place word wrapping happens. `TextToGraphics`
is a pure layout/render pass that never wraps. The pipeline for prose-like
content is `… → SyntaxToText → WordWrapping → TextToGraphics`.

## What was implemented

### 1. `WordWrapping` is pixel/measure-based and context-aware

[`program/src/projection/primitive/WordWrapping.jl`](../../program/src/projection/primitive/WordWrapping.jl)

```julia
struct WordWrapping <: Projection
    max_width::Int        # pixel fallback when no available_width on context
    measure::Function     # (text, font) -> (w, h)
end
```

Wrap width comes from the context first:

```julia
ctx.available_width !== nothing ?
    Cell(() -> max(1, Int(ctx.available_width[]))) :
    Cell(p.max_width)
```

The scroll pane / layout above hands the editor its content width via
`with_available_size`, and a resize re-wraps reactively. When no context
width is present (snapshot/headless use), the constructed `max_width` applies.

### 2. Character preservation (no dropped spaces)

The wrap pass is structural only: it splits `TextString`s into adjacent
sub-spans and inserts `TextNewline`s between them, but never removes or adds
a character. A space that lands at a wrap boundary stays as the last
character of the previous visual line. Embedded `\n` in span content is
preserved and resets the column counter (TextToGraphics still honours
embedded `\n`).

Tested by `WordWrapping characters preserved` in
[`test/src/projection/WordWrappingTest.jl`](../../test/src/projection/WordWrappingTest.jl).

### 3. Mapping table in a dedicated IoMap

```julia
struct WrapSeg
    out_index::Int     # 1-based output element index
    in_span::Int       # 1-based input element index
    in_char_start::Int # 0-based char offset within in_span
    length::Int        # chars in this sub-span
end

struct WordWrappingIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    segs::Cell         # Cell{Vector{WrapSeg}}
end
```

`segs` is rebuilt by the same thunk that rebuilds the output element list,
so it stays consistent with the wrapped output and invalidates together.

### 4. Bidirectional selection mapping

- `map_reference_backward` rewrites a wrapped `elements[ws].content{wc}` to
  `elements[seg.in_span].content{seg.in_char_start + wc}`.
- `map_reference_forward` finds the sub-span containing the input cursor;
  at the exact boundary between two sub-spans of the same input span,
  prefers the **start of the next visual line** (matches the boundary-
  duplicate convention in `TextToGraphics`'s left/right reader).
- `projection_read(::WordWrapping, iomap, ::ReplaceSelectionOperation)`
  uses `map_reference_backward` so downstream selection ops produced by
  `TextToGraphics` flow back to original-space.
- The output `TextText.selection` is a `Cell` that forward-maps the input
  selection, so `TextToGraphics` can draw the cursor in wrapped coordinates.

Tested by `WordWrapping selection round-trip` in
[`test/src/projection/WordWrappingTest.jl`](../../test/src/projection/WordWrappingTest.jl).

### 5. `TextToGraphics` no longer wraps

[`program/src/projection/primitive/TextToGraphics.jl`](../../program/src/projection/primitive/TextToGraphics.jl)

- `max_width` removed from the struct and constructor.
- Eager path: the wrap branch was deleted; each `\n`-delimited line is laid
  out as one advancing run, breaking only on embedded `\n` and `TextNewline`.
- ListNode path: `_wrap_paragraph` is now `_layout_paragraph` (no wrap
  test); `_paragraph_height` is the max span height across the paragraph.
- `char_to_coord`, the cursor rect, and the entire keyboard reader are
  unchanged in shape; they operate over wrapped spans and the ops they
  emit are translated back by `WordWrapping`.

## Pipeline wiring

`WordWrapping(measure=measure)` is inserted immediately before
`TextToGraphics(measure=measure)` in pipelines that render prose-like or
overflow-prone text:

- [`example/src/projection/Text.jl`](../../example/src/projection/Text.jl)
- [`example/src/projection/Book.jl`](../../example/src/projection/Book.jl)
- [`example/src/projection/WordWrapping.jl`](../../example/src/projection/WordWrapping.jl)
- [`example/src/projection/Workbench.jl`](../../example/src/projection/Workbench.jl) — uses two
  variants: `text_to_graphics` (wrapped) for book/json/xml/text/primitive/
  conversation/object, and `text_to_graphics_no_wrap` for the workspace and
  filesystem trees where wrap would break the tree layout.
- [`example/src/projection/Assistant.jl`](../../example/src/projection/Assistant.jl)
- [`example/src/projection/Wrapper.jl`](../../example/src/projection/Wrapper.jl)
- [`example/src/Examples.jl`](../../example/src/Examples.jl) — the `TextText` fallback for
  the introspection-decorator dispatch.

Structured-data examples (json, xml, mixed, table, syntax, navigator,
filesystem, julia, math, collection/filter/sort/reverse, primitive, etc.)
skip wrapping: line breaks come from the element structure, and
mid-element wrap would break the visual structure.

## Tests

Added [`test/src/projection/WordWrappingTest.jl`](../../test/src/projection/WordWrappingTest.jl):

- **WordWrapping characters preserved** — concatenated output spans equal
  the original input; at least one soft `TextNewline` inserted.
- **WordWrapping no-wrap fits on one line** — generous width keeps the
  single span intact.
- **WordWrapping selection round-trip** — every position in every emitted
  sub-span round-trips forward → backward and backward → forward.
- **WordWrapping reads available_width from context** — context width
  wins over a generous `max_width` fallback.

Updated [`test/src/projection/TextToGraphicsTest.jl`](../../test/src/projection/TextToGraphicsTest.jl)
to drop `max_width` from `TextToGraphics(...)`. The "basic wrapping" test
now chains `SequentialProjection(WordWrapping(...), TextToGraphics(...))`
to exercise the same path the live pipeline takes.

Suite result after the refactor: **661 passing**. The two `julia`
selection failures are a pre-existing `LineNumbering`-into-Julia-chain
issue (verified independently by reverting that working-tree edit).

## Visual verification

Snapshot of `make_workbench_document_example` at 1280×720 confirms the
book paragraph now wraps at the editor pane's actual width instead of the
old fixed 800 px.

## Newline semantics

Soft (wrap) and hard (`\n` / source `TextNewline`) breaks are
indistinguishable to `TextToGraphics` — both are `TextNewline`. This is
fine for layout and for **visual-line** cursor navigation. A `soft::Bool`
flag on `TextNewline` is deferred (see remaining-work doc).

## What is intentionally NOT here

- **No change to `TextNewline`'s structure.** Soft and hard breaks share
  the type.
- **No grapheme/bidi/hyphenation work.** Word boundaries stay "split on
  spaces", exactly as before.
- **No per-glyph wrap inside an unbreakable word.** A word wider than
  `max_width` overflows on its own line (the "always place at least one
  word" rule).
- **The old column-based `WordWrapping(width=N)` API is gone.** It is
  replaced by pixel mode; the `example/src/projection/WordWrapping.jl`
  example was migrated to `max_width`.
