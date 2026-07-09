# Graphics Domain

<img width="396" alt="Graphics Image example" src="../../image/example/graphics-image.png">

The graphics domain provides the backend-agnostic rendering primitives. It represents visual elements as reactive documents that can be projected to the screen, and is consumed by both the SDL2 backend (native windows) and the web backend (which serializes the same primitives to a JSON draw-list the browser paints — see the [devices and backends guide](../../../package/kernel/doc/devices-and-backends.md#web-backend)).

## Types

- **GraphicsText**: Rendered text with position and styling
- **GraphicsRect**: Rectangle for cursor, selection, or decoration
- **GraphicsCanvas**: Container holding a collection of graphics elements

## Examples

```julia
# Create graphics text: (text, x, y, font, r, g, b, a)
gtext = GraphicsText("Hello", 10, 20, font_ubuntu_monospace_regular_24, 255, 255, 255, 255)

# Create a rectangle: (x, y, w, h, r, g, b, a)
rect = GraphicsRect(100, 50, 2, 20, 255, 0, 0, 255)

# Create an empty canvas
canvas = GraphicsCanvas()

# Create a canvas from a vector of elements
canvas = GraphicsCanvas([gtext, rect])

# Create a canvas with a layout direction
canvas = GraphicsCanvas(CellVector([Cell(gtext), Cell(rect)]), layout_vertical)

# Access and modify (transparent via @document macro — no [] needed)
gtext.x = 50
gtext.text = "World"
```

## Coordinates

Graphics use pixel coordinates:
- `x` — horizontal position
- `y` — vertical position
- `w` — element width (`GraphicsRect` names the size fields `w`/`h`, not `width`/`height`)
- `h` — element height

## Styling

- `font` — font family and style
- `color` — text or fill color
- All styling fields are reactive Cells

## Key Features

- Reactive rendering — changes update automatically
- Canvas can hold mixed graphics elements
- Coordinates are reactive for animations
- Integrates with the SDL2 and web backends for display

## Saving to a file

`write_image` renders a projected document to a BMP file without opening a
window. Provide the same projection you would use for `run_example`:

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_image(doc, proj, "snapshot.bmp"; width=1200, height=800)
```

If you already have a `GraphicsCanvas` in hand, pass it directly:

```julia
write_image(canvas, "snapshot.bmp"; width=800, height=600)
```

To compose the save step into a pipeline, use `GraphicsCanvasToImageFile` as
the final projection — its output is an `ImageFile` document:

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("snapshot.bmp"; width=1200, height=800),
)
iomap = print_document(proj, doc)
# iomap.output isa ImageFile
```

`GraphicsCanvasToImageFile` has no reader — it is a write-only, side-effecting
projection.

File formats: `write_image` supports both `.bmp` (built into SDL2) and `.png`
(via `IMG_SavePNG` from SDL2_image); other extensions error.

## Saving to PDF

`write_pdf` is the vector counterpart of `write_image`: same call shape, a
`.pdf` filename. Instead of rasterizing the canvas through SDL, it walks the
`GraphicsCanvas` tree and emits PDF path/text operators, so shapes stay crisp at
any zoom and the text is selectable and searchable. Fonts are embedded
(Type0 / CIDFontType2, `Identity-H`), so output is self-contained.

```julia
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_pdf(doc, proj, "snapshot.pdf")                         # one page, sized to content
write_pdf(doc, proj, "snapshot.pdf"; width=1200, height=800) # fixed page size
```

A given canvas writes directly, and the save step composes into a pipeline via
`GraphicsCanvasToPdfFile` (printer-only, output is an `ImageFile`, no reader):

```julia
write_pdf(canvas, "snapshot.pdf"; width=800, height=600)

proj = ChainingProjection(
    make_graphics_image_projection_example(),
    GraphicsCanvasToPdfFile("snapshot.pdf"; width=1200, height=800),
)
print_document(proj, doc)   # writes snapshot.pdf
```

Unlike `write_image`, `write_pdf` is **SDL-free** — it never opens a renderer.
It measures text for page sizing from the embedded font metrics via
`pdf_measure_text` (an `(Int, Int)` measure, drop-in for `sdl_measure_text`). The
projection that *produces* the canvas still chooses its own `measure`: pass
`pdf_measure_text` to keep the whole export SDL-free, or `sdl_measure_text` for
byte-for-byte parity with the on-screen layout (which requires SDL to be up — the
`write_example_pdf` helper initializes it for you).

### Pagination

By default the output is a single page. Pass `paginate=true` to flow content
taller than the page across multiple pages — `height` becomes the page height and
the content is sliced into `height`-tall bands (an element straddling a page
boundary is split cleanly between the two pages). The embedded fonts are shared
across all pages, so only the per-page content streams add to the file size.

```julia
# Multi-page: each page is 612 × 792 pt (US Letter); content reflows to 612 wide.
write_pdf(doc, proj, "book.pdf"; paginate=true, width=612, height=792)

# Canvas you already have, three 300×400 pages if it is ~1000 pt tall:
write_pdf(canvas, "book.pdf"; width=300, height=400, paginate=true)
```

In `write_pdf(document, projection, …)` paginate mode, `width` is the page width
(given, or content-fit capped at `max_width`); `height` defaults to `792`. For
the document overload, `GraphicsCanvasToPdfFile` also takes `paginate=true`.

v1 limitations: uncompressed content streams, `GraphicsImage` supported only in
its RGBA-buffer form (raw SDL texture pointers are skipped), and TrueType
(`.ttf`) outline fonts only — CFF/`.otf` embedding (`Inconsolata.otf`) is not yet
implemented.
