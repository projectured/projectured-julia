# PDF export

> **Kind:** design · **Status:** current · **Stands on:** [graphics.md](../graphics/graphics.md), [style.md](../style/style.md), [devices-and-backends.md](../kernel/devices-and-backends.md)

`ProjecturedPdf` writes a `GraphicsCanvas` as a vector PDF: a shape becomes a PDF path, and a text becomes selectable text in an embedded font. It is a file export and not a `Backend`, and it needs neither SDL nor a third-party package. This document says how the writer maps a canvas to PDF, how it sizes and cuts the pages, and what it does not support.

## How it works

### A file export

A `Backend` drives devices and reads events; this package has neither. It has three entry points, in the form of `write_image` of `ProjecturedSdl`, and each returns `ImageFile(filename)`:

- `write_pdf(canvas, filename; width, height, paginate)` writes a canvas that the caller already has.
- `write_pdf(document, projection, filename; …)` prints the projection and writes its output. The output must be a `GraphicsCanvas`, or the call raises an error.
- `GraphicsCanvasToPdfFile(filename; …)` is a projection with a printer only, for the end of a chain. Its output is the `ImageFile`, and its reference mappers return `nothing`.

[graphics.md](../graphics/graphics.md#saving-to-a-file) shows the calls with their keywords. [devices-and-backends.md](../kernel/devices-and-backends.md) lists the file exports beside the backends.

### Measure

The export measures text with `measure_truetype_text` of `ProjecturedStyle`, which reads the advance widths from the font file and needs no display; see [style.md](../style/style.md#measurement-without-a-display). The writer uses its `measure` keyword only to find the bounds of the content. The projection that makes the canvas takes its own `measure`, and `measure_truetype_text` there keeps the whole export free of SDL. The same font files are embedded in the PDF, so a PDF reader places each glyph with the advance that the layout measured.

### The page

One PDF point is one logical pixel. Without `paginate`, the page size comes from two passes, as in `write_image`:

1. The printer runs with no available size on each axis that has no `width` or `height`, and `get_canvas_content_bounds` measures the result.
2. When the content is larger than `max_width` or `max_height`, the printer runs again with that limit as the available size.

With `paginate = true`, the layout gets an unbounded height, and the page width is `width` or else the width of the content, at most `max_width`. `height` is the page height, 792 by default, the height of US Letter at 72 dpi. The writer cuts the content into bands of that height and writes one page for each band. Each page clips to its media box, so an element across a border is cut between two pages. The painters skip an element that is outside the band of the page.

### Drawing

The canvas has its origin at the top left with y down, and PDF has its origin at the bottom left with y up. One function, `_flip`, converts each y coordinate when the painter writes it, and it adds the offset of the band of the page. The painters follow the painters of the SDL backend, one for each graphics type:

- A rectangle with round corners and a circle become Bézier paths. A spline is cut into line segments first, as the SDL backend does.
- A `GraphicsViewport` becomes a clip, with its axis-aligned transform as a PDF matrix.
- An image becomes an image object with an RGB stream and a grey soft mask for the alpha.
- A `GraphicsFence` paints nothing.

Each alpha value gets one `ExtGState` resource. A text becomes a `Tj` show of glyph identifiers in hexadecimal.

### Fonts

Each font file is embedded once and shared by every page and every size. It is a Type0 font over a `CIDFontType2`, with the encoding `Identity-H` and the map `CIDToGIDMap /Identity`. So a character identifier is the glyph identifier, and every Unicode character of the font is available. The writer embeds the whole file as `/FontFile2` and writes a `/W` array only for the glyphs that the document uses. A `ToUnicode` map lets a copy from the PDF give the real text. The TrueType reader is `TrueType.jl` of `ProjecturedStyle`.

The writer itself, `PdfWriter`, is a small PDF 1.7 writer: it numbers the objects, records the byte offset of each one, and ends with the cross-reference table and the trailer. The content streams are not compressed.

## How it fits

`ProjecturedPdf` depends on `ProjecturedGraphics` for the canvas and `get_canvas_content_bounds`, on `ProjecturedStyle` for the colours, the fonts and the TrueType reader, and on the kernel for the projection and the IoMap. It needs no third-party package, so the umbrella `Projectured` holds it. It registers nothing. `write_example_pdf(name)` in `ProjecturedExample` writes a registered example.

## Design decisions

- **Vector, not raster.** A PDF of a document must stay sharp at any zoom, and its text must be selectable. An image of the page embedded in a PDF was left as an option and not built. See `plan/done/write-pdf.md`.
- **No new dependency.** Cairo was rejected: it adds a large native library, and it selects a font by a fontconfig name, not by the file path that `StyleFont` holds. A compression library was rejected too, so the streams stay uncompressed.
- **Composite fonts with `Identity-H`.** A simple PDF font covers only 256 characters, and the editor uses more.
- **The whole font file is embedded.** The editor uses a few fonts, and each file is embedded once. Subsetting would make the file smaller and was left for later.
- **The page size comes from the same bounds as `write_image`.** `get_canvas_content_bounds` is in `ProjecturedGraphics`, so both exports use one walk.
- **Pages cut one layout into bands.** The layout runs once at the page width, and pagination does not lay out each page again. See `plan/done/pdf-pagination.md`.

## Usage

```julia
write_pdf(document, projection, "snapshot.pdf")                            # one page, sized to the content
write_pdf(document, projection, "book.pdf"; paginate = true, height = 792)  # pages of 792 points
write_pdf(canvas, "canvas.pdf"; width = 800, height = 600)                  # a canvas in hand
projection = ChainingProjection(make_graphics_image_projection_example(),
                                GraphicsCanvasToPdfFile("out.pdf"; width = 1200, height = 800))
write_example_pdf("json", "json.pdf")
```

- Test: `test_write_pdf()` in `test/projectured/backend/PdfTest.jl` checks the file envelope, the content-fit size, every primitive with an embedded font, the projection form, and the page count of pagination. The package has no test suite of its own.

## Limits

- A character that the font does not have is written as glyph 0 of that font. `measure_truetype_text` measures such a character in a fallback font, but the writer embeds no fallback font.
- The painter writes a text at `font.size`, and `measure_truetype_text` measures it at `font_logical_size(font)`, which includes the font zoom. With a font zoom other than 1, the text and its layout differ in size.
- Every font is embedded as `/FontFile2`, the TrueType form. An `.otf` font with CFF outlines, such as `Inconsolata.otf`, needs `/FontFile3`, which the writer does not write.
- An image in the form of an SDL texture pointer paints nothing; only an RGBA buffer paints.
- The streams are not compressed, and the fonts are not subset, so a file is larger than it must be.
