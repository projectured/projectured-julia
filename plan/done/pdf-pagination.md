# Plan: PDF pagination — flow tall content across multiple pages

> **Status: DONE** (in `program/src/backend/Pdf.jl`). `test_write_pdf()` passes
> 26/26 (10 new pagination assertions); a 60-line canvas paginates to 4 pages
> validated by `pdfinfo` (`Pages: 4`), `mutool clean`, and Ghostscript (all 4
> pages render, with content continuing across the boundary and the straddling
> line cleanly split). Built as planned; no design changes were needed.

`write_pdf` currently emits **one** page sized to the content (or to a fixed
`width × height`, clipping any overflow). This adds **pagination**: when a fixed
page height is requested, content taller than the page flows onto successive
pages of the same size, producing a normal multi-page PDF.

This is the "multi-page pagination" item listed as future work in
[write-pdf.md](../done/write-pdf.md).

---

## Design

### Coordinate model

The graphics domain is top-left / y-down; PDF is bottom-left / y-up. The single
page covers global y `[0, page_height)` via the flip `pdf_y = page_height - y`.

Pagination generalizes this to a **vertical band per page**. Page `k` covers the
global y band `[top + k·H, top + (k+1)·H)` where `H` is the page height and
`top` is the content's top (normally `0`). Page `k`'s flip becomes:

```
pdf_y = page_height - (global_y - y0)      where  y0 = top + k·H
```

So a single `y0` offset (the global y of the current page's top) turns the
existing single-page flip into the per-page flip. This is threaded through one
helper, `_flip(ctx, gy)`, replacing the inline `ctx.page_height - (…)`
expressions in every painter.

### Page count

From the canvas content bounds (`_canvas_content_bounds(canvas, measure)` →
`(minx, miny, maxx, maxy)`):

```
top     = min(0, miny)                 # include slightly-negative content; normally 0
total_h = max(0, maxy - top)
npages  = max(1, cld(total_h, H))      # ceil division
```

### Painting each page

For page `k`, paint the **whole** canvas with `y0 = top + k·H`. Two safeguards
keep each page showing only its band:

1. **Page-level clip.** Wrap the page's content stream in
   `q 0 0 W H re W n … Q` so nothing draws outside the MediaBox (an element
   straddling a page boundary is split cleanly — its top half on one page, its
   bottom half on the next).
2. **Vertical culling.** Each leaf painter early-returns when the element's
   global y-extent lies entirely outside the page band
   (`_on_page(ctx, top, bottom)`), so a 100-page document does not emit every
   element's operators 100 times. Containers (`GraphicsCanvas`, `GraphicsViewport`)
   always recurse — their accumulated offset may bring children into the band —
   but a `GraphicsViewport` whose own box is off-band is skipped.

### Shared resources

Fonts, ExtGStates, and image XObjects are registered into one `PageCtx` shared
across **all** pages, so each embedded font is emitted **once** and every Page
object references the same `/Resources` dict. Only the per-page content streams
and Page objects multiply.

---

## API

A single new keyword, `paginate::Bool = false`, on both `write_pdf` overloads and
`GraphicsCanvasToPdfFile`. Default `false` preserves today's exact behavior.

### `write_pdf(canvas; width, height, paginate=false, …)`

- `paginate = false` → one page of `width × height` (unchanged).
- `paginate = true`  → pages of `width × height`; the canvas content is sliced
  vertically into `npages` bands. `width`/`height` are the **page** size.

### `write_pdf(document, projection; …, paginate=false, …)`

- `paginate = false` → existing content-fit single page.
- `paginate = true`:
  - **Page height** = `height` if given, else a default of `792` (US-Letter
    height at 72 dpi). This is the band size; the layout is **not** constrained
    to it.
  - **Page width** = `width` if given (the projection reflows to it), else the
    content's natural width capped at `max_width` (same width handling as the
    non-paginated path). The layout is printed with the vertical axis
    **unbounded** so the full height is produced, then sliced.

`max_height` is irrelevant in paginate mode (height is the page band, not a cap)
and is ignored there.

---

## Implementation steps (all in `program/src/backend/Pdf.jl`)

### 1. `PageCtx` gains band fields

```julia
mutable struct PageCtx
    page_height::Float64
    y0::Float64          # global y of the current page's top (0 for single page)
    band_lo::Float64     # global y band for culling [band_lo, band_hi]
    band_hi::Float64
    buf::IOBuffer
    fonts::Dict{String,FontReg}
    gstates::Dict{UInt8,String}
    images::Vector{Any}
end
```

Constructor seeds `y0 = 0`, `band_lo = 0`, `band_hi = height` (single-page
defaults; `_render_pages` overwrites them per page).

### 2. Flip + cull helpers

```julia
_flip(ctx, gy) = ctx.page_height - (gy - ctx.y0)
_on_page(ctx, top, bottom) = bottom >= ctx.band_lo && top <= ctx.band_hi
```

### 3. Thread `_flip` + culling through painters

Replace each inline `ctx.page_height - (…)` with `_flip(ctx, …)` and add an
`_on_page` early-return using each primitive's global y-extent:

| painter | flip arg | cull extent (global y) |
|---|---|---|
| `paint_rect!`   | `_flip(ctx, y + h)`               | `y … y + h` |
| `paint_circle!` | `_flip(ctx, oy + cy)`             | `cyG − rad − bw … cyG + rad + bw` |
| `paint_line!`   | `_flip(ctx, oy + y1/​y2)`          | `min(y1,y2) − w … max(y1,y2) + w` |
| `paint_text!`   | `_flip(ctx, oy + y + ascent)`     | `oy + y … oy + y + size` |
| `paint_image!`  | `_flip(ctx, oy + y + h)`          | `oy + y … oy + y + h` |
| `paint_viewport!` | `_flip(ctx, vy + vh)`           | `vy … vy + vh` (skip whole viewport if off-band) |

`GraphicsCanvas`/`GraphicsViewport` recursion is unchanged (always descends,
except the viewport's own-box cull).

### 4. Factor page rendering + document writing

- `_render_pages(canvas, page_w, page_h, npages, top, background) -> (ctx, contents)`
  — builds the shared `PageCtx`, loops `k = 0:npages-1` resetting `buf`/`y0`/band,
  emits page clip + background + `paint_canvas!`, collects `Vector{Vector{UInt8}}`.
- `_write_pdf_document(filename, contents, ctx, page_w, page_h) -> ImageFile`
  — the object/xref assembly currently inlined in `write_pdf(canvas, …)`,
  generalized to N content streams + N Page objects under one Pages node, with
  fonts/gstates/images written once and one shared `/Resources` string.

### 5. Rewrite `write_pdf(canvas, …)` over the new helpers

```julia
function write_pdf(canvas, filename; width, height, paginate=false,
                   background=DEFAULT_BG, measure=pdf_measure_text)
    # .pdf extension check
    page_w, page_h = Int(width), Int(height)
    top, npages = 0, 1
    if paginate
        _, miny, _, maxy = _canvas_content_bounds(canvas, measure)
        top = min(0, miny)
        npages = max(1, cld(max(0, maxy - top), page_h))
    end
    ctx, contents = _render_pages(canvas, page_w, page_h, npages, top, background)
    _write_pdf_document(filename, contents, ctx, page_w, page_h)
end
```

### 6. Extend `write_pdf(document, projection, …)` with `paginate`

Add the `paginate` branch described under **API** (unbounded vertical layout,
width handling reused, default page height 792), then delegate to the canvas
overload with `paginate=true`.

### 7. `GraphicsCanvasToPdfFile` gains `paginate`

Add a `paginate::Bool` field (default `false`), thread it through the keyword
constructor and `projection_print`.

### 8. Tests (`test/src/backend/PdfTest.jl`)

Add a `_page_count(filename)` helper (count `"/Type /Page /Parent"` occurrences)
and testsets:

- **paginated canvas** — a tall stack of text lines + `width × height` smaller
  than the content height ⇒ `_page_count > 1`, file is a valid PDF.
- **paginated document/projection** — `write_pdf(doc, proj, f; paginate=true,
  height=H)` with a tall example ⇒ multiple pages.
- **non-paginated default unchanged** — `_page_count == 1`.

### 9. Guide

Extend the "Saving to PDF" section in `guide/document/graphics.md`: the
`paginate=true` keyword, page-size semantics, and that the single-page default is
unchanged. Drop "single page (no pagination)" from the v1-limitations list.

---

## Validation

- `test_write_pdf()` (extended) is green.
- Manually: a paginated example renders in `pdfinfo` as `Pages: N (N>1)`,
  `mutool clean` succeeds, and Ghostscript renders every page, with each page's
  band of content correctly placed (top of page 2 continues where page 1 ended).
