# Plan: `write_pdf` — Save a Projected Document to a PDF File

The PDF analogue of [`write_image`](../done/write-image.md). The caller provides
their own projection; `write_pdf` drives `projection_print`, takes the resulting
`GraphicsCanvas`, and emits a **vector** PDF — rectangles, lines, circles, and
text become PDF path/text operators rather than rasterized pixels. Output is
resolution-independent and the text is selectable/searchable.

Where `write_image` renders the canvas through SDL's software renderer,
`write_pdf` walks the same `GraphicsCanvas` tree directly and translates each
primitive into PDF content-stream operators. **It does not touch SDL at all** —
it is a second, independent backend over the graphics domain.

---

## Design decisions

- **Vector, not raster.** Every `GraphicsRect`/`GraphicsLine`/`GraphicsCircle`
  becomes a PDF path; every `GraphicsText` becomes a `Tj` text show. This is the
  whole point of a PDF backend — crisp at any zoom, copy-pasteable text. (A
  raster fallback that embeds a `write_image` PNG as a full-page XObject is noted
  as a future option but **not** built here.)
- **Zero new dependencies, hand-rolled writer.** Consistent with the project's
  ethos (the SDL backend, anti-aliasing, and downsampling are all hand-rolled —
  see `program/src/backend/Sdl.jl`). We write the PDF byte stream by hand and
  parse just enough TrueType to embed the editor's own fonts. We do **not** pull
  in Cairo/`PDFIO`/`CodecZlib`. (Cairo was considered and rejected: it would add
  a large native dependency and select fonts by fontconfig name rather than by
  the file paths `StyleFont` carries.) Content streams are emitted uncompressed
  (valid, just larger); Flate compression is a future optimization gated on a
  zlib dependency.
- **Fonts are embedded as Type0 / CIDFontType2 composite fonts** with
  `Identity-H` encoding and an `Identity` `CIDToGIDMap`, so CID == glyph id and
  the full Unicode range the editor uses is covered (Latin-1-only "simple" fonts
  would break on non-Latin glyphs). We embed the **entire** TTF/OTF file (no
  subsetting in v1 — subsetting is a later size optimization). The editor only
  uses a handful of fonts (`font/` dir), so per-file embedding is cheap and each
  unique `StyleFont.filename` is embedded once and shared.
- **Coordinate flip.** The graphics domain is top-left origin, y-down; PDF is
  bottom-left origin, y-up. A single `flip_y(y) = page_height - y` centralizes
  the conversion. Glyph-space advances/metrics use PDF's 1000-units-per-em.
- **Page sizing mirrors `write_image`.** Reuse the content-bounds machinery and
  the same two-pass (unbounded → cap-at-max → reflow) sizing so a single page is
  sized to hug the content, capped at `max_width`/`max_height`. Multi-page
  pagination is a future extension; v1 emits **one** page.

---

## Component overview

| Component | Location | Role |
|---|---|---|
| `PdfBackendModule` | `program/src/backend/Pdf.jl` (new) | Self-contained PDF backend |
| `TrueTypeFont` parser | inside `Pdf.jl` | Parse `head`/`hhea`/`hmtx`/`cmap`/`maxp`/`OS/2`; char→GID, advances, bbox, ascent |
| `PdfWriter` builder | inside `Pdf.jl` | Object table, xref, trailer, stream emission |
| canvas → content-stream walker | inside `Pdf.jl` | Mirrors `_render_canvas!`'s offset accumulation, emits operators |
| `write_pdf(canvas, filename; ...)` | `Pdf.jl` | Low-level overload: a canvas you already have |
| `write_pdf(document, projection, filename; ...)` | `Pdf.jl` | Primary entry point: runs the pipeline, sizes the page, writes |
| `GraphicsCanvasToPdfFile` | `Pdf.jl` | Printer-only projection; same effect via pipeline composition |
| `_canvas_content_bounds` (relocated) | `program/src/document/Graphics.jl` | Shared pure bounds walk (see Step 0) |
| Example wrapper `write_pdf_example` | `example/src/Examples.jl` | Convenience next to `write_image_example` |
| Test | `test/src/backend/PdfTest.jl` (new) | File created, non-empty, valid `%PDF` header/`%%EOF` |

---

## Step 0: Relocate content-bounds helpers to `GraphicsModule`

The page-sizing pass needs the bounding box of everything the canvas draws.
That logic already exists in `Sdl.jl` as `_canvas_content_bounds` /
`_accumulate_bounds!` / `_bounds_elem!` (`program/src/backend/Sdl.jl:1483-1541`).
It is **pure geometry over a measure callback** — nothing SDL-specific — so move
it into `GraphicsModule` (`program/src/document/Graphics.jl`) and export
`_canvas_content_bounds`. Both backends then share it.

- The `measure` callback signature stays `measure(text, font) -> (w, h)`.
- `Sdl.jl` keeps calling `_canvas_content_bounds(canvas; measure = sdl_measure_text)`
  (now imported from `GraphicsModule` instead of defined locally).
- `Pdf.jl` calls it with its own metrics-based measure (Step 4) so the PDF
  backend stays SDL-free, **or** with `sdl_measure_text` when the caller wants
  byte-for-byte the same layout SDL produced. Default: pass `sdl_measure_text`
  from the example wrapper for layout parity with the on-screen/`write_image`
  view; let `Pdf.jl`'s internal default be its own metric measure so the module
  has no SDL dependency.

This is a refactor with no behavior change — verify `write_image` still works
after the move.

---

## Step 1: Minimal TrueType parser (`Pdf.jl`)

A small, read-only parser over the raw font bytes. Cached per file path
(`const _TTF_CACHE = Dict{String,TrueTypeFont}()`), parsed once.

```julia
struct TrueTypeFont
    bytes::Vector{UInt8}     # the whole file, for FontFile2
    units_per_em::Int        # head.unitsPerEm
    num_glyphs::Int          # maxp.numGlyphs
    advances::Vector{Int}    # hmtx advanceWidth per glyph (in font units)
    cmap::Dict{UInt32,UInt16}# Unicode codepoint -> glyph id
    ascent::Int; descent::Int# hhea (font units)
    bbox::NTuple{4,Int}      # head xMin,yMin,xMax,yMax (font units)
    cap_height::Int          # OS/2 sCapHeight if present, else ascent
    italic_angle::Float64    # post.italicAngle if present, else 0
    is_fixed_pitch::Bool
end
```

Parse the SFNT table directory, then:
- **`head`** → `unitsPerEm`, `xMin..yMax`, `indexToLocFormat` (not needed since
  we embed wholesale, but read the bbox).
- **`maxp`** → `numGlyphs`.
- **`hhea`** → `ascender`, `descender`, `numberOfHMetrics`.
- **`hmtx`** → `advanceWidth[0..numberOfHMetrics-1]`; glyphs past that reuse the
  last advance (monospace fonts have `numberOfHMetrics == 1`).
- **`cmap`** → pick the best Unicode subtable: format 12 (segmented coverage,
  full Unicode) if present, else format 4 (BMP). Build codepoint→GID.
- **`OS/2`** (optional) → `sCapHeight`, fixed-pitch flag; **`post`** (optional)
  → `italicAngle`. Provide defaults when absent.

`.otf` (CFF outlines, e.g. `Inconsolata.otf`) embeds via `FontFile3`
(`Subtype /OpenType` / `/Type1C`) rather than `FontFile2`. Detect by the SFNT
version tag (`OTTO` ⇒ CFF). v1 may restrict to TrueType-outline files and map
`Inconsolata.otf` callers to a `.ttf` fallback, or implement the `FontFile3`
branch — note this as the one font-format edge case to settle during
implementation. (All the editor's *default* example fonts — UbuntuMono,
DejaVu, Liberation — are TrueType `.ttf`.)

Helpers:
```julia
glyph_id(f, c::Char)            -> UInt16          # cmap lookup, 0 = .notdef
advance_1000(f, gid)           -> Int              # advance * 1000 ÷ units_per_em
text_width(f, size, s::String) -> Float64          # Σ advance, scaled to `size` px
ascent_px(f, size)             -> Float64           # ascent * size ÷ units_per_em
```

`text_width`/`ascent_px` are what the SDL-free `measure` callback (Step 4) and
the text baseline placement use.

---

## Step 2: `PdfWriter` — object/xref/stream emission (`Pdf.jl`)

A tiny builder that assigns object numbers, records byte offsets, and writes the
file. PDF structure produced:

```
%PDF-1.7
%<binary comment bytes>
<obj 1> Catalog        -> Pages
<obj 2> Pages          -> [Page]
<obj 3> Page           MediaBox [0 0 W H], Resources, Contents 4
<obj 4> Contents       stream (the operator list)
<obj …> per font: Type0 font, CIDFontType2, FontDescriptor, FontFile2 stream, ToUnicode
<obj …> per distinct alpha: ExtGState << /ca a /CA a >>
<obj …> per image: XObject (Step 6)
xref
trailer << /Root 1 /Size N >>
startxref
%%EOF
```

```julia
mutable struct PdfWriter
    io::IOBuffer
    offsets::Vector{Int}     # byte offset of each object (1-based by obj number)
end
new_object!(w) -> objnum     # reserve a number
write_object!(w, objnum, body::AbstractString)
write_stream!(w, objnum, dict::String, data::Vector{UInt8})   # << dict /Length n >> stream … endstream
finish!(w, root_objnum) -> Vector{UInt8}   # xref + trailer + startxref + %%EOF
```

Colors: `rg`/`RG` take 0–1 floats (`UInt8/255`). Numbers formatted with a fixed,
locale-independent helper (`@sprintf("%.3f", x)`), no thousands separators.

---

## Step 3: Canvas → content-stream walker (`Pdf.jl`)

Mirror `_render_canvas!` / `_dispatch_render_elem!` (`Sdl.jl:825-905`) including
its offset accumulation through nested canvases, but emit operators into an
`IOBuffer` instead of drawing. Skip `GraphicsFence`. (The early-stop layout
optimization is irrelevant for a one-shot file export — just walk everything.)

A `PageCtx` carries `page_height`, the `IOBuffer`, the per-font registry
(`StyleFont → (objnum, fontresname, TrueTypeFont)`), the per-alpha ExtGState
registry, and the image registry. `flip_y(y) = page_height - y`.

Per primitive:

- **`GraphicsRect`** — fill at `(x, flip_y(y+h), w, h)`.
  - Square corners (all radii 0): `x y' w h re f`.
  - Rounded corners: build a path with `m`/`l` for the straight edges and `c`
    (cubic Bézier, kappa = 0.5523 × radius) for each corner, then `f`. Per-corner
    radii are independent (matches `GraphicsRect.radius_tl..bl`), clamped to
    `min(w,h)/2` exactly as `_fill_rounded!` does.
  - Border (`border_width>0`): mirror SDL's strategy — fill the outer rounded
    rect in the border color, then fill the inset rounded rect (radii − bw) in
    the fill color. Keeps a single primitive's "rounded fill + outline" idiom.
- **`GraphicsLine`** — set line width `w`, stroke color, `x1 y1' m x2 y2' l S`.
  Axis-aligned lines may instead be emitted as a filled `re f` span to match
  SDL's crisp 1px rule, but a stroked path is acceptable in vector output.
- **`GraphicsCircle`** — 4-Bézier circle path centered at `(cx, flip_y(cy))`,
  radius `r`, `f`. Border via outer disc (border color) + inner disc
  (radius − bw, fill color), mirroring `_render_circle!`.
- **`GraphicsText`** — register the font (Step 5), then:
  ```
  BT /F<k> <size> Tf  <r> <g> <b> rg  <x> <baseline> Td <HEXGIDS> Tj ET
  ```
  where `baseline = flip_y(y + ascent_px(font))` (the texture top sits at
  `elem.y` in SDL; PDF positions the baseline, so offset down by the ascent).
  `HEXGIDS` is the string encoded as **big-endian 2-byte glyph ids**
  (`<00480065…>`) via `glyph_id`. Record each used GID for the font's `W` array
  and `ToUnicode` map. Empty text → skip.
- **Alpha** (`a < 255`, or `border_a`): emit `/GS<k> gs` before the paint op,
  registering an ExtGState `<< /ca a/255 /CA a/255 >>`. Reset is implicit per
  `q`/`Q` if used; simplest is to set `gs` before each alpha'd op and rely on the
  next op resetting color/alpha. Fully transparent (`a == 0`) → skip the paint.
- **`GraphicsViewport`** — clip: `q  x y' w h re W n` … render `vp.content` with
  accumulated offset … `Q`. Content coordinates are viewport-relative exactly as
  `_render_viewport!` accumulates them.
- **`GraphicsCanvas`** (nested) — recurse, accumulating `+x,+y` offset, same as
  the renderer.
- **`GraphicsImage`** — Step 6 (deferred/minimal).

Offsets accumulate in the **top-left** space; `flip_y` is applied only at the
moment an absolute coordinate is written, using the final accumulated position.

---

## Step 4: SDL-free text measure for page sizing (`Pdf.jl`)

```julia
pdf_measure_text(text, font::StyleFont) =
    (text_width(_load_ttf(font.filename), font.size, String(text)), font.size)
```

This lets `_canvas_content_bounds` (Step 0) size the page without SDL. Default
the `measure` kwarg of the internal sizing to `pdf_measure_text`; the example
wrapper may override with `sdl_measure_text` for exact parity with the on-screen
layout. (In practice the canvas's element coordinates are already absolute and
fixed by the projection that produced it; `measure` only affects how far the
bounds extend past the last text's origin, so small metric differences are
cosmetic.)

---

## Step 5: Font registration + embedding (`Pdf.jl`)

A registry keyed by `StyleFont` (or by `(filename, size)` — but size only scales
at show time via `Tf`, so key by `filename` and reuse one embedded font across
sizes). For each distinct font file, on first use:

1. `_load_ttf(filename)` → `TrueTypeFont` (cached).
2. Assign a resource name `/F<k>` and reserve object numbers for: the `Type0`
   font dict, the `CIDFontType2` descendant, the `FontDescriptor`, the
   `FontFile2` stream (raw bytes, `/Length1` = byte count), and a `ToUnicode`
   CMap stream.
3. Track the set of used GIDs to emit a `W` array (advances in 1000-em units)
   and a `ToUnicode` mapping (GID → original codepoint, for copy/paste/search).

Objects written at `finish!` time:

- **Type0:** `<< /Type/Font /Subtype/Type0 /BaseFont/<name> /Encoding/Identity-H
  /DescendantFonts [<cid>] /ToUnicode <tu> >>`
- **CIDFontType2:** `<< /Type/Font /Subtype/CIDFontType2 /BaseFont/<name>
  /CIDSystemInfo<< /Registry(Adobe)/Ordering(Identity)/Supplement 0 >>
  /FontDescriptor <fd> /CIDToGIDMap /Identity /DW <defaultwidth> /W [<used widths>] >>`
- **FontDescriptor:** `Flags`, `FontBBox` (bbox × 1000 ÷ unitsPerEm), `ItalicAngle`,
  `Ascent`, `Descent`, `CapHeight`, `StemV` (a reasonable constant, e.g. 80),
  `FontFile2 <stream>`.
- **FontFile2:** raw TTF bytes, `<< /Length1 <n> >>`.
- **ToUnicode:** a minimal CMap stream mapping the used GIDs back to codepoints.

`Flags`: symbolic (4) is the safe choice with `Identity-H`; OR in fixed-pitch (1)
and serif (2) bits when known. `BaseFont` name: derive from the filename
(spaces/illegal chars stripped); exactness doesn't matter for embedded fonts.

---

## Step 6: `GraphicsImage` (minimal / deferred)

`GraphicsImage.data` is an SDL texture pointer or an RGBA byte buffer
(`Sdl.jl:785-801`). In the export path the document is freshly printed, so image
data is most often a decoded `(buf, nw, nh)` RGBA tuple. Emit it as an image
XObject: an RGB `/DeviceRGB` `Do` with an `/SMask` for the alpha channel,
positioned via a `cm` transform into `(x, flip_y(y+h), w, h)`.

For v1, **skip raw texture-pointer images** (can't read pixels back without SDL)
and handle only the RGBA-buffer form; texture-pointer images are rare in a
print-from-document export. Document the limitation. (Most example canvases have
no `GraphicsImage` at all, so this is low-priority.)

---

## Step 7: Public functions (`Pdf.jl`)

```julia
"""
    write_pdf(canvas::GraphicsCanvas, filename; width, height,
              background=(0xfd,0xf6,0xe3,0xff), measure=pdf_measure_text) -> ImageFile

Low-level overload. Emit `canvas` as a single-page vector PDF. `width`/`height`
are the page size in points (== logical px). Returns an `ImageFile(filename)`.
"""
function write_pdf(canvas::GraphicsCanvas, filename::AbstractString;
                   width::Integer, height::Integer,
                   background::NTuple{4,UInt8} = (0xfd,0xf6,0xe3,0xff))
    lowercase(splitext(filename)[2]) == ".pdf" ||
        error("write_pdf: unsupported format (only .pdf is supported)")
    # build writer, page ctx (page_height=height), paint background rect,
    # walk canvas → content stream, register/emit fonts, finish! → write bytes.
    ...
    ImageFile(filename)
end
```

```julia
"""
    write_pdf(document, projection, filename; width=nothing, height=nothing,
              max_width=1200, max_height=800, background=(0xfd,0xf6,0xe3,0xff),
              measure=pdf_measure_text) -> ImageFile

Run `projection_print(projection, document)` to get a `GraphicsCanvas`, size the
page (same two-pass content-fit logic as `write_image`), and write the PDF.
Throws if the projection output is not a `GraphicsCanvas`.
"""
```

The document/projection overload reuses `write_image`'s sizing structure
verbatim (lift the shared `print_canvas`/pass-1/pass-2 logic — consider
factoring a `_fit_canvas(document, projection; width, height, max_width,
max_height, measure)` helper in `GraphicsModule` that both `write_image` and
`write_pdf` call, returning `(canvas, out_w, out_h)`). Returning `ImageFile`
keeps parity with `write_image` (the existing "a file on disk" document type);
no new `PdfFile` document is introduced.

```julia
struct GraphicsCanvasToPdfFile <: Projection
    filename::String; width::Int; height::Int; background::NTuple{4,UInt8}
end
# projection_print(p, canvas::GraphicsCanvas, recursion, reference) ->
#   SimpleIoMap(p, canvas, write_pdf(canvas, p.filename; ...))
# map_reference_forward/backward -> nothing   (printer-only, no reader)
```

---

## Step 8: Module wiring

- **`program/src/backend/Pdf.jl`** — new `module PdfBackendModule`. Imports:
  `GraphicsModule` (the element types + `_canvas_content_bounds`), `FontModule`
  (`StyleFont`), `ImageModule` (`ImageFile`), `ProjectionApiModule`
  (`projection_print`, `Projection`), `IoMapModule` (`SimpleIoMap`),
  `ProjectionApiModule` reference-map fns. Uses `Printf`. Exports `write_pdf`,
  `GraphicsCanvasToPdfFile`, `pdf_measure_text`.
- **`program/src/Projectured.jl`** — `include` `backend/Pdf.jl` after `Sdl.jl`;
  `using .PdfBackendModule: write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text`
  and re-export them. (Confirm `Printf` is available — it is a stdlib; add to
  `program/Project.toml` `[deps]` if not already transitively present.)

---

## Step 9: Example wrapper

In `example/src/Examples.jl`, next to `write_image_example`
(`example/src/Examples.jl:466`):

```julia
function write_pdf_example(example::Example, filename;
                          width=nothing, height=nothing,
                          max_width=1800, max_height=1200, kwargs...)
    write_pdf(example.document, example.projection, filename;
              width=width, height=height,
              max_width=max_width, max_height=max_height,
              measure=sdl_measure_text, kwargs...)   # parity with on-screen layout
end

write_pdf_example(name::AbstractString="json", filename=tempname()*".pdf"; kwargs...) =
    write_pdf_example(examples[findfirst(ex->ex.name==name, examples)], filename; kwargs...)
```

Export `write_pdf_example` from `example/src/ProjecturedExample.jl` alongside
`write_example_image`. No new `Example` entry is needed — every existing example
whose projection ends in a graphics canvas (json, syntax, text, widget, …) can be
exported to PDF directly.

---

## Step 10: Test

**New file:** `test/src/backend/PdfTest.jl`, registered in
`test/src/ProjecturedTest.jl`.

```julia
@testset "write_pdf" begin
    @testset "document/projection overload" begin
        doc  = make_json_document_example()
        proj = make_graphics_image_projection_example()   # the JSON→…→graphics pipeline
        f = tempname()*".pdf"
        img = write_pdf(doc, proj, f; width=400, height=300)
        @test img isa ImageFile
        @test isfile(f) && filesize(f) > 0
        bytes = read(f)
        @test startswith(String(bytes[1:8]), "%PDF-1.")     # header
        @test occursin("%%EOF", String(bytes[max(1,end-32):end]))  # trailer
        rm(f)
    end
    @testset "canvas overload" begin
        f = tempname()*".pdf"
        write_pdf(GraphicsCanvas(), f; width=100, height=80)
        @test isfile(f) && filesize(f) > 0
        rm(f)
    end
    @testset "GraphicsCanvasToPdfFile projection" begin
        doc = make_json_document_example()
        f = tempname()*".pdf"
        proj = SequentialProjection(make_graphics_image_projection_example(),
                                    GraphicsCanvasToPdfFile(f; width=400, height=300))
        iomap = projection_print(proj, doc)
        @test iomap.output isa ImageFile
        @test isfile(f) && filesize(f) > 0
        rm(f)
    end
    @testset "unsupported extension errors" begin
        @test_throws ErrorException write_pdf(GraphicsCanvas(), tempname()*".png"; width=10, height=10)
    end
end
```

Stretch verification (manual, not in CI): open a generated PDF in a viewer and
confirm text is selectable and shapes are crisp; optionally shell out to
`qpdf --check` / `mutool clean` if available to validate structure.

Run the narrowest test during development:
`julia --project=test -e 'using ProjecturedTest; include(".../PdfTest.jl")'`
(per repo convention — do **not** default to `test_all`).

---

## Step 11: Guide

Add a "Saving to PDF" subsection to `guide/document/graphics.md` next to the
existing `write_image` notes: same call shape, `.pdf` extension, vector output
with selectable text, fonts embedded, one page sized to content (capped at
`max_*`). Note the v1 limitations: single page (no pagination), no content-stream
compression, `GraphicsImage` limited to RGBA-buffer form, and the `.otf`/CFF font
caveat from Step 1.

---

## Implementation order (incremental, each independently verifiable)

1. **Step 0** — relocate `_canvas_content_bounds` to `GraphicsModule`; confirm
   `write_image` unaffected (`test/.../GraphicsToFileTest.jl` still green).
2. **Steps 1–2** — TrueType parser + `PdfWriter`; unit-test `glyph_id`/
   `advance_1000`/`text_width` against a known font, and that `finish!` produces
   a parseable `%PDF … %%EOF` skeleton.
3. **Steps 3,5,7** — walker + font embedding + `write_pdf(canvas, …)`; render a
   hand-built canvas with one rect + one text span; open it, eyeball it.
4. **Step 7 cont.** — document/projection overload + `_fit_canvas` sizing;
   `GraphicsCanvasToPdfFile`.
5. **Steps 8–11** — wiring, example wrapper, tests, guide.
6. **Steps 4 & 6** polish — SDL-free measure default; `GraphicsImage` RGBA path.

---

## Open questions to settle during implementation

- **`.otf`/CFF fonts** (`Inconsolata.otf`): implement the `FontFile3` embedding
  branch, or restrict v1 to TrueType-outline fonts and remap. (All default
  example fonts are `.ttf`, so this does not block the example/tests.)
- **Axis-aligned lines:** stroked path vs. filled `re` span — pick whichever
  matches SDL's crisp rules more faithfully on a side-by-side.
- **Return type:** reuse `ImageFile` (chosen, for `write_image` parity) vs. a new
  `PdfFile` document. Revisit only if a downstream consumer needs to distinguish.
