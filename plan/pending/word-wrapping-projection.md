# Move word wrapping out of `TextToGraphics` into `WordWrapping`

## Goal

Make `WordWrapping` the **single** place word wrapping happens, and make
`TextToGraphics` a pure layout/render pass that **never wraps**. After this
change:

- `WordWrapping` (a `Text → Text` projection) inserts `TextNewline`
  elements at exactly the boundaries `TextToGraphics` computes today —
  pixel-accurate, measure-driven, honouring the same word-boundary rules.
- `TextToGraphics` lays spans out left-to-right and only ever breaks the
  line at an explicit `TextNewline` (or embedded `\n`). It no longer reads
  `max_width` and has no wrap arithmetic.

The pipeline becomes `… → SyntaxToText → WordWrapping → TextToGraphics`.

## Current state

### `TextToGraphics` wraps, in pixels, in two places

`TextToGraphics` carries `max_width`, `start_x`, `start_y`, `measure`
([TextToGraphics.jl:65-74](../../program/src/projection/primitive/TextToGraphics.jl#L65-L74))
and wraps using `measure(candidate, font)` against `max_width`:

- **Eager `CellVector` path** — the wrap test at
  [TextToGraphics.jl:267](../../program/src/projection/primitive/TextToGraphics.jl#L267)
  inside the big layout thunk
  ([TextToGraphics.jl:199-337](../../program/src/projection/primitive/TextToGraphics.jl#L199-L337)).
- **Lazy `ListNode` path** — `_wrap_paragraph`
  ([TextToGraphics.jl:474-527](../../program/src/projection/primitive/TextToGraphics.jl#L474-L527))
  and `_paragraph_height`
  ([TextToGraphics.jl:534-561](../../program/src/projection/primitive/TextToGraphics.jl#L534-L561)),
  driven by `_print_listnode` / `_build_paragraph_node`
  ([TextToGraphics.jl:349-465](../../program/src/projection/primitive/TextToGraphics.jl#L349-L465)).

Both paths also build the `char_to_coord` table of `SegCoord`s
([TextToGraphics.jl:40-61](../../program/src/projection/primitive/TextToGraphics.jl#L40-L61))
and the cursor rect, which the reader uses for keyboard navigation and
click translation
([TextToGraphics.jl:88-177](../../program/src/projection/primitive/TextToGraphics.jl#L88-L177),
[TextToGraphics.jl:607-633](../../program/src/projection/primitive/TextToGraphics.jl#L607-L633)).

### `WordWrapping` exists but is column-based and unused

`WordWrapping` wraps by **character columns** (`width::Int`, default 80),
splits `TextString`s, inserts `TextNewline`, and **drops** leading spaces
after a wrap and trailing spaces before a wrap
([WordWrapping.jl:20-99](../../program/src/projection/primitive/WordWrapping.jl#L20-L99)).
It returns a plain `SimpleIoMap`
([WordWrapping.jl:48](../../program/src/projection/primitive/WordWrapping.jl#L48)),
so it inherits the default reference mapping
([Projection.jl:30-75](../../program/src/common/Projection.jl#L30-L75)) —
which is wrong for a projection that splits spans and inserts elements.

It is included and exported
([Projectured.jl:104](../../program/src/Projectured.jl#L104),
[Projectured.jl:257](../../program/src/Projectured.jl#L257)) but **not** part
of the live SDL pipeline, which goes straight to `TextToGraphics`
([Sdl.jl:686-690](../../backend/Sdl.jl#L686-L690)).

## Why this is more than moving a loop

`TextToGraphics` reads its input `TextText`'s `selection` to draw the cursor
and emits `ReplaceSelectionOperation`s addressed as
`elements[span].content{char}` against that same input
([TextToGraphics.jl:565-573](../../program/src/projection/primitive/TextToGraphics.jl#L565-L573)).

Today that input is the **original** text, so those coordinates are the
source-of-truth coordinates. Once `WordWrapping` sits in front,
`TextToGraphics` sees the **wrapped** text — its spans are split and renumbered
— so:

- the cursor it draws must be placed using a **wrapped-space** selection, and
- every op it emits is in **wrapped-space** and must be translated **back** to
  original-space before reaching the editor / upstream projections.

So the real work is giving `WordWrapping` a correct, total, bidirectional
reference mapping. This is the bulk of the plan.

## Target design

### 1. `WordWrapping` becomes pixel/measure-based and context-aware

Replace the column field with measure-driven pixel wrapping that mirrors the
exact rules in `TextToGraphics._wrap_paragraph` (split on spaces, always place
at least one word per line, break when `cx + word_width > max_width`):

```julia
struct WordWrapping <: Projection
    max_width::Int        # pixel fallback when context carries no available width
    measure::Function     # (text, font) -> (w, h); same measurer TextToGraphics uses
end

WordWrapping(; max_width::Int = 800, measure::Function) =
    WordWrapping(max_width, measure)
```

Wrap width is taken from the context first, falling back to `max_width`:

```julia
wrap_w = get_property(ctx, :available_width, p.max_width)
```

This is the `:available_width` channel from
[projection-context.md](../tentative/projection-context.md) and
[widget-layout.md](widget-layout.md): the scroll pane / layout above hands the
editor its content width, and a resize re-wraps reactively. When no context
width is present (snapshot/headless use) the constructed `max_width` applies.

### 2. Wrapping preserves every character (no dropped spaces)

The current `WordWrapping` deletes spaces at wrap points
([WordWrapping.jl:81-82](../../program/src/projection/primitive/WordWrapping.jl#L81-L82)).
That breaks a 1:1 character correspondence and would make reference mapping
lossy. The new wrap pass is **structural only**: it may *split* a `TextString`
into adjacent sub-spans and *insert* `TextNewline`s between them, but it never
removes or adds a character. Concatenating all output `TextString` contents (in
order, ignoring `TextNewline`s) reproduces the original text exactly.

A space that lands at a wrap boundary stays as the last character of the
visual line (it renders as harmless trailing whitespace). This guarantees the
mapping below is a clean piecewise-linear offset translation.

### 3. A mapping table in a dedicated IoMap

Replace `SimpleIoMap` with a `WordWrappingIoMap` holding a reactive table
built during the wrap pass:

```julia
struct WrapSeg
    out_index::Int     # 1-based element index in the OUTPUT TextText
    in_span::Int       # 1-based element index in the INPUT (original) TextText
    in_char_start::Int # 0-based char offset of this sub-span within in_span
    length::Int        # chars in this sub-span
end

struct WordWrappingIoMap <: IoMap
    projection::Any
    input::TextText
    output::TextText
    segs::Cell         # Cell{Vector{WrapSeg}}  (inserted TextNewlines have no entry)
end
```

`segs` is rebuilt by the same thunk that rebuilds the output element list, so
it stays consistent with the wrapped output and invalidates together with it.

### 4. Bidirectional selection mapping

**Backward (output → input), used by the reader.** A wrapped-space cursor
`elements[ws].content{wc}` maps to the original via the segment at output
index `ws`:

```
original = elements[seg.in_span - 1].content{ seg.in_char_start + wc }
```

Implement `map_reference_backward(::WordWrapping, iomap, ref)` plus a
`projection_read(::WordWrapping, iomap, op::ReplaceSelectionOperation)`
that rewrites the op's path using `segs`. (Note the 0-based `elements{s}` in
references vs 1-based element indices — mirror `_cursor_position` /
`_build_selection_path` at
[TextToGraphics.jl:565-573](../../program/src/projection/primitive/TextToGraphics.jl#L565-L573).)

**Forward (input → output), used at print time to place the cursor.** The
output `TextText.selection` is a computed cell that forward-maps the input
selection so `TextToGraphics` can draw the cursor in wrapped coordinates:

```julia
out_selection = Cell(() -> forward_map(segs[], input.selection))
```

`forward_map` finds the sub-span with `in_span == os` and
`in_char_start ≤ oc < in_char_start + length`, yielding
`elements[out_index-1].content{ oc - in_char_start }`. At a wrap boundary
(cursor exactly between two sub-spans) prefer the **start of the next visual
line**, matching `TextToGraphics`'s existing boundary-duplicate convention
([TextToGraphics.jl:117](../../program/src/projection/primitive/TextToGraphics.jl#L117),
[TextToGraphics.jl:132](../../program/src/projection/primitive/TextToGraphics.jl#L132)).

### 5. `TextToGraphics` stops wrapping

- Drop `max_width` from the struct/constructor; keep `start_x`, `start_y`,
  `measure` (still needed for positioning, cursor x, click hit-testing).
- **Eager path**: delete the wrap branch
  ([TextToGraphics.jl:267-298](../../program/src/projection/primitive/TextToGraphics.jl#L267-L298));
  lay each `\n`-delimited line out as one advancing run, break the line only on
  embedded `\n` and on `TextNewline` elements (the existing carriage-return
  handling at
  [TextToGraphics.jl:213-217](../../program/src/projection/primitive/TextToGraphics.jl#L213-L217)
  and [TextToGraphics.jl:228-250](../../program/src/projection/primitive/TextToGraphics.jl#L228-L250)
  stays).
- **Lazy path**: `_wrap_paragraph` → a line-layout helper with the wrap test
  removed; `_paragraph_height` → "max span height on the line". Paragraph
  splitting on `TextNewline` is unchanged — since `WordWrapping` now emits
  a `TextNewline` per visual line, each `ListNode` "paragraph" is one visual
  line.
- `char_to_coord`, the cursor rect, and the entire reader
  ([TextToGraphics.jl:88-177](../../program/src/projection/primitive/TextToGraphics.jl#L88-L177),
  [TextToGraphics.jl:607-633](../../program/src/projection/primitive/TextToGraphics.jl#L607-L633))
  are unchanged in shape; they now operate over wrapped spans, and the
  ops they emit are translated back by `WordWrapping` (§4).

### 6. Newline semantics after the split

Soft (wrap) and hard (`\n` / source `TextNewline`) breaks become
indistinguishable to `TextToGraphics` — both are `TextNewline`. This is fine
for layout and for **visual-line** cursor navigation (up/down/home/end keep
working, since `char_to_coord` still has one y-row per visual line). The cost:
the **logical-line** vs visual-line distinction is lost at the graphics layer.
If a future feature needs it (e.g. "go to end of logical line"), add a
`soft::Bool` flag to `TextNewline` set by `WordWrapping`; out of scope here.

## Pipeline wiring

Insert `WordWrapping` immediately before `TextToGraphics`, sharing the same
measurer ([Sdl.jl:686-690](../../backend/Sdl.jl#L686-L690)):

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    WordWrapping(measure = sdl_measure_text),   # NEW: was the wrap inside TextToGraphics
    TextToGraphics(measure = sdl_measure_text),      # now layout-only
)
```

`SequentialProjection` already walks the reader backward through every step
([Sequential.jl:78-92](../../program/src/projection/higherorder/Sequential.jl#L78-L92)),
so a `ReplaceSelectionOperation` produced by `TextToGraphics` passes through
`WordWrapping.projection_read` and gets translated to original-space before
reaching `SyntaxToText`. Update the snapshot/example pipelines in
`Sdl.jl` and the docstrings in `Sequential.jl` / `TypeDispatching.jl`
accordingly.

## Implementation steps

### Step 1 — Pixel wrap engine in `WordWrapping`
- Add `max_width` + `measure` fields; port the word-boundary loop from
  `TextToGraphics._wrap_paragraph` but emit `TextString` sub-spans +
  `TextNewline`s instead of `GraphicsText`. Preserve all characters (§2).
- Read `wrap_w = get_property(ctx, :available_width, p.max_width)`.

### Step 2 — `WordWrappingIoMap` + `segs`
- Build the `Vector{WrapSeg}` in the same thunk that builds the output
  elements; store both in the IoMap.

### Step 3 — Reference mapping + reader
- Implement `map_reference_forward`, `map_reference_backward`, and
  `projection_read(::WordWrapping, iomap, ::ReplaceSelectionOperation)`
  over `segs` (§4), including the boundary convention.
- Set the output `TextText.selection` to the forward-mapped cell (§4).

### Step 4 — De-wrap `TextToGraphics`
- Remove `max_width`; delete wrap branches in both paths (§5); keep newline
  handling, `char_to_coord`, cursor, reader.

### Step 5 — Wire the pipeline
- Add `WordWrapping(measure=…)` before `TextToGraphics` in `Sdl.jl`;
  update example/docstring pipelines.

### Step 6 — Tests
- **Wrap parity**: for a corpus of spans + a `max_width`, assert the visual
  line breaks produced by `WordWrapping`+`TextToGraphics` match the old
  `TextToGraphics`-only output (same `GraphicsText` x/y, same `canvas_w/h`).
- **Character preservation**: concatenated output spans == original text.
- **Selection round-trip**: for every original `(span,char)`, `forward` then
  `backward` is the identity; and a click/`_translate_click` op in wrapped
  space maps back to the expected original `(span,char)`.
- **Reactivity**: changing `:available_width` re-wraps and invalidates only the
  wrap/layout cells (check with `perf_counters()`,
  [reactive-cells.md:58-63](../../guide/reactive-cells.md#L58-L63)); editing a
  span re-wraps only the affected output.
- **Keyboard nav** across soft-wrapped lines (left/right/up/down/home/end)
  lands on the same characters as before.

## What is intentionally NOT here

- **No change to `TextNewline`'s structure.** Soft and hard breaks share the
  type; the optional `soft::Bool` flag is deferred (§6).
- **No grapheme/bidi/hyphenation work.** Word boundaries stay "split on
  spaces", exactly as today.
- **No per-glyph wrap inside an unbreakable word.** Like today, a word wider
  than `max_width` overflows on its own line (the "always place at least one
  word" rule).
- **No removal of `WordWrapping`'s column mode as a feature** — it is
  replaced by pixel mode; if a column-based consumer exists elsewhere it must
  migrate (none in the live pipeline today).

## Limitations / risks

- **Reference mapping is the load-bearing piece.** If `segs` and the output
  element list ever drift, the cursor lands wrong. They must be built by one
  thunk so they invalidate together.
- **Trailing-space rendering.** Preserving boundary spaces (§2) means a visual
  line can end in a space; visually invisible, but `canvas_w` for that line
  includes it. Acceptable; note it in tests.
- **Two measurers.** `WordWrapping` and `TextToGraphics` must use the
  *same* `measure` or break points won't match positioning. Constructed
  together in the pipeline; document the invariant.
- **Double layout cost.** Wrapping measures words once to choose breaks;
  `TextToGraphics` measures again to position. This duplicates measurement
  relative to the fused version. Cheap per frame and reactive, but real;
  measure with `perf_counters()` on large documents.

## Open questions

- **Should `:available_width` be the *content* width (minus the editor's
  padding) or the raw viewport width?** Must match whatever `TextToGraphics`
  uses as `start_x`; settle when wiring the scroll-pane context
  (see [widget-layout.md](widget-layout.md)).
- **Boundary cursor convention.** "Start of next line" is proposed (§4); verify
  it matches user expectation against the current behaviour at
  [TextToGraphics.jl:117](../../program/src/projection/primitive/TextToGraphics.jl#L117).
- **Does the `ListNode` (lazy paragraph) path still earn its keep** once
  wrapping is external and every visual line is its own `TextNewline`-delimited
  paragraph? Possibly simplify to the eager path; evaluate separately.

## Relationship to existing architecture

| Concern | Today | After this plan |
|---|---|---|
| Where wrapping happens | Inside `TextToGraphics` (pixels) | `WordWrapping` (`Text→Text`, pixels) |
| Wrap width source | `TextToGraphics.max_width` (construction) | `:available_width` from context, else `max_width` |
| `TextToGraphics` role | Wrap + layout + cursor + reader | Layout + cursor + reader (no wrap) |
| `WordWrapping` | Column-based, unused, `SimpleIoMap` | Pixel-based, in pipeline, `WordWrappingIoMap` with mapping table |
| Selection coordinates seen by `TextToGraphics` | Original text | Wrapped text; mapped back by `WordWrapping` |
| Character identity through wrap | Lossy (spaces dropped) | Preserved (structural split only) |

This is additive on the projection side (one richer projection + one pipeline
step) and a deletion on `TextToGraphics`'s side. Its one cross-cutting
dependency is the `:available_width` context channel shared with
[widget-layout.md](widget-layout.md) and
[projection-context.md](../tentative/projection-context.md).
</CodeContent>
<parameter name="EmptyFile">false
