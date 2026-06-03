# Inline images (and icons) in the text domain

Goal: a `TextText` may contain image spans that flow inline with surrounding
`TextString`s. The image is an unbreakable atomic glyph for word wrapping,
contributes its height to the surrounding line height, is hit-testable as a
single cursor position (before/after), and renders via the existing SDL
`GraphicsImage` path.

Icons are not a separate concept: they are images sized small by the caller.

---

## 1. Decisions (already made)

- **Span type — reuse `TextGraphics`.** It already exists at
  [program/src/document/Text.jl:190](../../program/src/document/Text.jl#L190)
  with the right field shape (`content::Document`, plus the standard styling
  fields shared by `TextString`/`TextNewline`/`TextSpacing`). It is currently
  *declared but unused* — no projection handles it. This plan wires it through
  the projection chain and the readers.
- **Content — `ImageDocument`** (`ImageFile` or `ImageMemory`, both from
  [program/src/document/Image.jl](../../program/src/document/Image.jl)).
  Decoding/loading stays in the image domain; `TextGraphics` only references
  it. Other `Document`s (e.g. `GraphicsCanvas`, `GraphicsImage`) are *not*
  rejected at the type level — `content::Document` permits them — but only
  `ImageDocument` is wired in this plan; the rest is future work.
- **Icons share the span type.** Caller picks a small width/height.

What we are *not* doing:

- No separate `TextImage`/`TextIcon` types.
- No automatic recolouring of icons by `font_color` (orthogonal, can be added
  per-`ImageDocument` later).
- No baseline/descent metrics: images sit on the same baseline as the
  surrounding line and the line height is `max(font_h, image_h)`. A real
  baseline-offset field can come later if a consumer needs it.

---

## 2. What needs to change

### 2.1 `TextGraphics` — add explicit size, drop the unused fields

[program/src/document/Text.jl:190](../../program/src/document/Text.jl#L190)
currently carries `font`, `font_color`, `fill_color`, `line_color`, `padding`
inherited by analogy with `TextString`. For an image span, the load-bearing
fields are:

- `content::Cell{ImageDocument}`
- `width::Cell{Int32}` — pixels
- `height::Cell{Int32}` — pixels
- `selection::Reference`
- `padding::Cell{Inset}` — keep, useful for spacing the box from neighbours
- `fill_color`, `line_color` — keep for an optional background/border
- Drop `font` and `font_color` from the struct, *or* leave them and just
  ignore them in the printer. Recommendation: leave the struct alone for
  this iteration to avoid a churn-y `@document` change; the printer simply
  reads `width`/`height` from the embedded `ImageDocument`'s natural size
  unless overridden.

**Decision needed mid-implementation:** does size live on `TextGraphics` or
on the underlying `ImageDocument`? `ImageFile`/`ImageMemory` do not carry
width/height today. Two viable paths:

1. Add `width`/`height` fields to `TextGraphics` (caller-supplied). Simple,
   no image-domain change. Recommended.
2. Add `width`/`height` to `ImageDocument`, populate them on decode. More
   correct long-term but pulls the image domain into this plan.

Go with (1) for v1.

### 2.2 Decode pipeline — `ImageFile` → raw bytes

[program/src/backend/Sdl.jl:466-486](../../program/src/backend/Sdl.jl#L466-L486)
shows `_render_image!` already renders a `GraphicsImage` whose `data` is
either an SDL `Ptr{SDL_Texture}` or a `Vector{UInt8}` (RGBA32, row-major). So
the backend half is done.

The gap: no code today decodes an `ImageFile.filename` into the `.raw` cell.
The hookup needs:

- A small decoder (PNG/JPEG via `FileIO`+`ImageIO`, or stb_image via the
  existing C deps — pick whichever the repo already pulls in) that fills
  `ImageFile.raw` with a `Vector{UInt8}` plus implied (w, h).
- A reactive setter on `ImageFile.raw` keyed off `ImageFile.filename` so a
  path change re-decodes.

This step is what makes the v1 actually render a PNG; it is the only
non-text-domain work in this plan.

### 2.3 `WordWrapping` — treat `TextGraphics` as an unbreakable token

[program/src/projection/primitive/WordWrapping.jl](../../program/src/projection/primitive/WordWrapping.jl)
currently only handles `TextString` (split on word boundaries) and
`TextNewline` (flush + emit). It needs a third branch:

- `elem isa TextGraphics` →
  - Treat the image as a single token of width `elem.width`, height
    `elem.height`.
  - If the current line cursor `cx + image_w > wrap_w`, insert a soft
    `TextNewline` first.
  - Pass the `TextGraphics` through unchanged.
  - Update `cx += image_w`.
  - Record a `WrapSeg` entry so downstream selection mapping can locate the
    image in the output stream.

The `WrapSeg` shape currently assumes a `TextString` sub-range. Either
extend the struct with a variant tag (`:string` vs `:graphics`) or emit a
zero-length `WrapSeg` whose `in_span` points at the `TextGraphics` index.
Lean toward the latter (smaller blast radius).

### 2.4 `TextToGraphics` — emit `GraphicsImage` for an image span

[program/src/projection/primitive/TextToGraphics.jl:214-275](../../program/src/projection/primitive/TextToGraphics.jl#L214-L275)
walks `styled.elements` and only handles `TextNewline` / `TextString`. Add a
third branch for `TextGraphics`:

- Width: `span.width` (Int32); height: `span.height`.
- `line_h = max(line_h, height)` — this is the bit that *makes line height
  follow image height*, which is the user-visible requirement.
- Push a `GraphicsImage(cx, cy, width, height, data)` into `result`. `data`
  is whatever `span.content.raw[]` produces (`Vector{UInt8}` or texture
  pointer once cached).
- Push a `SegCoord`-equivalent entry into `coord_map` marking this span as a
  *single atomic cursor position* — store `(span_idx, char_start=0,
  char_end=1, x=cx, y=cy, font=nothing, text="")`. Two cursor positions are
  legal: "before" (char=0, x=cx) and "after" (char=1, x=cx+width). The line
  rendering can ignore image segments because nothing inside them is a
  character.
- Advance: `cx += width`.

The cursor renderer at line 278 already paints a 2px tall rect of height
`max(cursor_line_h, 1)`. With `line_h` bumped by the image, the cursor next
to an image will visually match the line height.

### 2.5 Selection / hit-testing

The backward map at
[TextToGraphics.jl:512](../../program/src/projection/primitive/TextToGraphics.jl#L512)
turns `(graphics_canvas_index, pixel)` into `(span_idx, char_offset)`. With
image segments in `coord_map`:

- A click with `x < seg.x + width/2` resolves to `(span_idx, 0)` ("before
  the image").
- Otherwise `(span_idx, 1)` ("after the image").

Keyboard: pressing `:right` while the cursor is "before" advances to
"after"; another `:right` advances to the next span. `:left` is symmetric.
Up/down work naturally because the segment occupies a real (x, y) on a real
line.

### 2.6 Reader chain above `TextText`

If `SyntaxToText` or any upstream projection generates the spans, it must be
taught to emit `TextGraphics` where appropriate (or leave it alone — for a
direct text-domain document, the spans come from user code). For v1, only
the text-domain example needs to construct `TextGraphics` directly; no
upstream change is required to *demo* the feature.

---

## 3. Implementation order

1. **Decoder.** Add a way to populate `ImageFile.raw` with a
   `Vector{UInt8}` + carry (w, h). Smallest standalone PR.
2. **TextGraphics size.** Add `width`/`height` to `TextGraphics` (or pick
   path 2 if the decoder already exposes them). Keep the existing
   constructor; add a new one `TextGraphics(content, width, height)`.
3. **TextToGraphics branch.** Render `TextGraphics` as `GraphicsImage`,
   bump `line_h`. Verify visually with a one-shot example: a `TextText`
   containing `TextString`, `TextGraphics(ImageFile(...), 64, 64)`,
   `TextString`. Line should grow to 64px, cursor too.
4. **Hit testing / cursor coord map.** Add an image-segment entry to
   `coord_map`, teach the backward map about it. Keyboard L/R should walk
   on/off the image cleanly.
5. **WordWrapping branch.** Make wrap insert a soft newline before an image
   that overflows. Update `_wrap_string!` neighbours to skip non-string
   spans cleanly.
6. **Example + tests.** See §4.

---

## 4. Examples and tests

### Example document

In [example/src/document/Text.jl](../../example/src/document/Text.jl), add a
second constructor `make_text_with_image_example()` that mixes text and
two `TextGraphics`: one ~64×64 (image) and one ~24×24 (icon, with a
`StyleFont` of size 24 around it so the "follows font size" claim holds
visually). Wire it into [example/src/Projectured.jl] alongside the existing
`text` example.

### Tests

- [test/src/document/TextTest.jl] — structural: build a `TextText` with a
  `TextGraphics`, round-trip via `print`/`show`, assert `length` /
  `getindex` still work.
- [test/src/projection/TextToGraphicsTest.jl] — a `TextText` of `[string,
  graphics(64,64), string]` produces a canvas whose `canvas_h ≥ 64` and
  whose elements include exactly one `GraphicsImage` at the expected (x,
  y, w, h).
- [test/src/projection/WordWrappingTest.jl] — with `available_width = 80`
  and a 64-wide image preceded by a long enough string, the wrapper emits
  a soft newline *before* the image, not splitting it.
- Selection: clicking inside the image left half lands at
  `elements[i].content{0}`; right half lands at `elements[i].content{1}`.
  Pressing `:right` from `{0}` advances to `{1}`; another `:right` lands
  on the next span.

---

## 5. Open questions

- **Baseline.** Real typography aligns the image baseline to the text
  baseline, often with descent. Skip until a consumer asks; line-top
  alignment is fine for v1.
- **`font`/`font_color` on `TextGraphics`.** Keep as-is now, drop in a
  follow-up cleanup once nothing reads them.
- **Icon recolouring.** A monochrome icon that follows `font_color` would
  want a tint pass in `_render_image!`. Out of scope until requested.
- **Animation / multi-frame images.** Out of scope.
- **Caching.** `_render_image!` recreates the SDL texture every frame for
  the `Vector{UInt8}` branch. Once images are in real use this needs to
  cache to a `Ptr{SDL_Texture}`. Track separately.
- **Size source.** Per §2.1, if `ImageDocument` later carries intrinsic
  dimensions, `TextGraphics` should fall back to those when its own width/
  height are unset, mirroring HTML `<img>` semantics.
