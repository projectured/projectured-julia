"""
    PdfBackendModule

A second, SDL-free backend over the graphics domain: it walks a `GraphicsCanvas`
tree and emits a **vector** PDF — rectangles, lines, circles become PDF path
operators and text becomes selectable `Tj` text shows. The editor's own fonts
(`font/`) are embedded as Type0 / CIDFontType2 composite fonts (`Identity-H`),
so the full Unicode range the editor uses is covered.

Entry points mirror `write_image` in `ProjecturedSdl`:

- `write_pdf(canvas, filename; width, height, paginate=false)` — a canvas you
  already have. With `paginate = false` (default), the result is a single page
  and taller content is clipped; with `paginate = true`, content taller than
  `height` flows onto successive `width × height` pages.
- `write_pdf(document, projection, filename; ...)` — runs the pipeline, sizes a
  single page to the content (same two-pass fit as `write_image`) when
  `paginate = false`, or flows the content across multiple pages when
  `paginate = true`, and writes.
- `GraphicsCanvasToPdfFile` — printer-only projection for pipeline composition.

The PDF writer and a minimal read-only TrueType parser are hand-rolled, so the
backend pulls in no new dependencies (no Cairo, no zlib). Content streams are
emitted uncompressed; Flate compression and font subsetting are future
optimizations. The graphics domain is top-left/y-down; PDF is bottom-left/y-up,
so a single `page_height - y` flip is applied at the moment each coordinate is
written.
"""
module PdfBackendModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document

export write_pdf, GraphicsCanvasToPdfFile


include("Pdf.jl")

end # module
