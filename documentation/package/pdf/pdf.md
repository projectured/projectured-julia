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

The export finds the bounds of the content with `get_canvas_content_bounds`, which measures from the font files with a `FontFileMeasure()` and needs no display; see [style.md](../style/style.md#measurement-without-a-display). `write_pdf` takes no `measure` keyword: it draws from the font files, so only a `FontFileMeasure` can size its pages. The projection that makes the canvas keeps its own `measure`, and a `FontFileMeasure` there keeps the whole export free of SDL. The same font files are embedded in the PDF, so a PDF reader places each glyph with the advance that the layout measured. The painter writes a text at `font_logical_size(font)`, the size that the layout measures at, so a font zoom changes the text and its layout together. It writes the baseline at the same place the layout computed it, `y` plus the ascent of `compute_text_extent`, and the kerning between the glyphs of one run in the `TJ` array.

### The page

One PDF point is one logical pixel. Without `paginate`, the page size comes from two passes, as in `write_image`:

1. The printer runs with a free range on each axis that has no `width` or `height`, and `get_canvas_content_bounds` measures the result.
2. When the content is larger than `max_width` or `max_height`, the printer runs again with that limit as an exact range.

With `paginate = true`, the layout gets an unbounded height, and the page width is `width` or else the width of the content, at most `max_width`. `height` is the page height, 792 by default, the height of US Letter at 72 dpi. The writer cuts the content into bands of that height and writes one page for each band. Each page clips to its media box, so an element across a border is cut between two pages. The painters skip an element that is outside the band of the page.

### Drawing

The canvas has its origin at the top left with y down, and PDF has its origin at the bottom left with y up. One function, `_flip`, converts each y coordinate when the painter writes it, and it adds the offset of the band of the page. The painters follow the painters of the SDL backend, one for each graphics type:

- A rectangle with round corners and a circle become Bézier paths. A spline is cut into line segments first, as the SDL backend does.
- A `GraphicsViewport` becomes a clip, with its axis-aligned transform as a PDF matrix.
- An image becomes an image object with an RGB stream and a grey soft mask for the alpha.
- A `GraphicsFence` paints nothing.

Each alpha value gets one `ExtGState` resource. A text becomes one text object, with a `Tj` show of glyph identifiers in hexadecimal for each run of one font.

### Fonts

Each font file is embedded once and shared by every page and every size. It is a Type0 font over a `CIDFontType2`, with the encoding `Identity-H` and the map `CIDToGIDMap /Identity`. So a character identifier is the glyph identifier, and every Unicode character of the font is available. The writer embeds the whole file as `/FontFile2` and writes a `/W` array only for the glyphs that the document uses. A `ToUnicode` map lets a copy from the PDF give the real text. The TrueType reader is `TrueType.jl` of `ProjecturedStyle`.

A text can need more than one font. For a character that the font of the text does not have, `find_glyph_font_file` of `ProjecturedStyle` names the font that has it: DejaVu Sans Mono, then Noto Emoji. A `FontFileMeasure` measures the character in that font, and `paint_text!` draws it in that font too. It splits the text into runs of consecutive characters in one font and embeds each font that a run uses. Each run selects its font with `Tf` and shows its glyphs with a `TJ`, which also carries the kerning between the glyphs of the run. A `TJ` moves the text position by the advances of its glyphs and by the kerning, so a run starts where the run before it ends, on the baseline of the text. A presentation selector, U+FE0E or U+FE0F, has no width, and the painter drops it, as the measurer does.

The writer itself, `PdfWriter`, is a small PDF 1.7 writer: it numbers the objects, records the byte offset of each one, and ends with the cross-reference table and the trailer. The content streams are not compressed.

## How it fits

`ProjecturedPdf` depends on `ProjecturedGraphics` for the canvas and `get_canvas_content_bounds`, on `ProjecturedStyle` for the colours, the fonts and the TrueType reader, and on the kernel for the projection and the IoMap. It needs no third-party package, so the umbrella `Projectured` holds it. It registers nothing. `write_example_pdf(name)` in `ProjecturedExample` writes a registered example.

## Design decisions

- **Vector, not raster.** A PDF of a document must stay sharp at any zoom, and its text must be selectable. An image of the page embedded in a PDF was left as an option and not built. See [plan/done/write-pdf.md](../../../plan/done/write-pdf.md).
- **No new dependency.** Cairo was rejected: it adds a large native library, and it selects a font by a fontconfig name, not by the file path that `StyleFont` holds. A compression library was rejected too, so the streams stay uncompressed.
- **Composite fonts with `Identity-H`.** A simple PDF font covers only 256 characters, and the editor uses more.
- **The whole font file is embedded.** The editor uses a few fonts, and each file is embedded once. Subsetting would make the file smaller and was left for later.
- **The page size comes from the same bounds as `write_image`.** `get_canvas_content_bounds` is in `ProjecturedGraphics`, so both exports use one walk.
- **Pages cut one layout into bands.** The layout runs once at the page width, and pagination does not lay out each page again. See [plan/done/pdf-pagination.md](../../../plan/done/pdf-pagination.md).

## Usage

```julia
write_pdf(document, projection, "snapshot.pdf")                            # one page, sized to the content
write_pdf(document, projection, "book.pdf"; paginate = true, height = 792)  # pages of 792 points
write_pdf(canvas, "canvas.pdf"; width = 800, height = 600)                  # a canvas in hand
projection = ChainingProjection(make_graphics_image_projection_example(),
                                GraphicsCanvasToPdfFile("out.pdf"; width = 1200, height = 800))
write_example_pdf("json", "json.pdf")
```

- Test: `test_write_pdf()` in `test/projectured/backend/PdfTest.jl` checks the file envelope, the content-fit size, every primitive with an embedded font, the projection form, the page count of pagination, the text size under a font zoom, the kerning of a run, that texts of different fonts share one baseline, and the runs of a text in a fallback font. The package has no test suite of its own.

## Limits

- A fallback font that the writer can not embed is skipped, and its character is drawn as glyph 0 of the font of the text, while the measure sizes it in the fallback font. A font with CFF outlines is such a font, because it needs `/FontFile3`. The fallback fonts in `asset/font` are TrueType, so none is skipped.
- Every font is embedded as `/FontFile2`, the TrueType form. An `.otf` font with CFF outlines, such as `Inconsolata.otf`, needs `/FontFile3`, which the writer does not write.
- An image in the form of an SDL texture pointer paints nothing; only an RGBA buffer paints.
- The streams are not compressed, and the fonts are not subset, so a file is larger than it must be.
