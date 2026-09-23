# Graphics domain

> **Kind:** design · **Status:** current · **Stands on:** [style.md](../style/style.md), [devices-and-backends.md](../kernel/devices-and-backends.md), [text.md](../text/text.md)

`ProjecturedGraphics` holds the drawing primitives that every chain of projections ends in: text, boxes, lines, curves, canvases and viewports, each a reactive document. A backend paints them, and a hit test finds the primitive under the pointer. This document says how a canvas is built and tested, how a click leaves the graphics stage, and how a canvas is saved to a file.

<img width="396" alt="Graphics image example" src="../../../asset/image/example/graphics-image.png">

## How it works

| Document | What it draws |
| --- | --- |
| `GraphicsText` | `text` at `x`, `y` in a `font` and a `color` |
| `GraphicsRect` | a box `x`, `y`, `w`, `h` with a `color`, a radius for each corner and an optional border |
| `GraphicsLine` | a line between two points, solid or dashed |
| `GraphicsCircle` | a filled circle with an optional border |
| `GraphicsPolyline` | connected straight segments with optional arrowheads; the connector of a graph |
| `GraphicsPolygon` | a closed filled shape |
| `GraphicsSpline` | a smooth curve through or along points |
| `GraphicsCanvas` | a list of `elements` at `x`, `y`, `w`, `h`; a canvas can hold canvases |
| `GraphicsViewport` | one canvas clipped to a box, with an `AffineTransform` |
| `GraphicsImage` | pixel `data` in a box |
| `GraphicsFence` | nothing; a mark in the element list, described below |

Every field is a reactive cell, so a change of one coordinate repaints only what reads it. A colour is a `StyleColor` and a font is a `StyleFont`, both from [style.md](../style/style.md). Each backend converts a `StyleColor` to its own device encoding when it draws. Coordinates are `Int32` pixels, and a box names its size `w` and `h`. Elements draw in order, so a later element is on top.

The spline and arrowhead geometry is computed here, by `tessellate_spline` and `build_polyline_arrowhead`, so each backend draws the same points. The backends draw only the translation and the scale of a viewport transform.

### The canvas and the hit test

`GraphicsCanvas.elements` is a `CellVector` or a `ListNode`. A `ListNode` can be a list without an end in either direction; see [collection.md](../collection/collection.md). `layout` names the axis along which the canvas can grow without an end: `layout_none`, `layout_horizontal` or `layout_vertical`. A backend stops painting such a list when the elements are past the visible edge.

`hit_element_at(canvas, x, y)` returns the offset of the first element that contains the point, or `nothing`. Every caller in `source/` tests only for `nothing`. The test for each shape:

- A box, a viewport and a line use their bounding box. A circle uses its radius.
- A text uses the height of its font and has no right edge, so it takes every point to the right of its start.
- A polyline and a spline take a band of `max(3, width + 2)` pixels around the path. A polygon takes its whole interior.
- A canvas tests its own elements, with the point moved into its frame.

A canvas with a `w` or `h` that is not zero first clips the point to its own box. This clip is what keeps a text on the left of a row from taking the clicks of its right neighbour. An auto-sized canvas, with `w` and `h` zero, does not clip.

**The producer declares that elements do not overlap, and nothing checks it.** With `overlapping_elements = false` and a `layout`, the renderer and the hit test stop at the first element past the visible edge or past the point. A `GraphicsFence` in the element list states that the elements before it and after it do not overlap on the layout axis. It draws nothing, and both the renderer and the hit test skip it. A canvas that declares no overlap and has overlapping elements misses hits.

### Selection and clicks

`make_selection_ring(bounds)` returns one border-only `GraphicsRect` whose geometry cells read `bounds()`. When `bounds()` returns `nothing`, the ring has zero size and draws nothing. A layout or a widget container keeps the ring in its element list at all times. So a selection move changes four cells of the ring, and the element list keeps its shape.

`PointReferenceStep(x, y)` names a pixel inside an element, written `.point(x, y)` in `@reference`. The reader of `GraphicsCanvasToGraphicsImage`, below, makes a click into `ElementReferenceStep(i)` followed by a `PointReferenceStep`, and `TextToGraphics` in [text.md](../text/text.md) turns that into a character offset. The kernel reference layer never names the step.

`GraphicsCaching(; render)` is a dispatching projection over canvases. A finite canvas that holds no canvas and no viewport goes to `GraphicsCanvasToGraphicsImage`. The other canvases, the viewports and the collections are copied, so the recursion reaches their children. **`GraphicsCanvasToGraphicsImage` does not rasterize, although its name says so.** It returns a canvas, not a `GraphicsImage`. It puts a pale checkerboard behind the elements, so each cached region shows in a different colour. Its reader resolves a click to a `GraphicsRect` that contains the point. If no box contains it, the reader takes the `GraphicsText` on the same line with the largest `x` at or left of the point. `run_example(...; caching = true)` adds it to a chain.

`GraphicsToGraphics()` is the natural projection of a graphics document: its output is its input. `NaturalToGraphics` uses it, so a shape that a person makes, for example in the evaluator, draws as the shape and not as a tree of its fields. Its reader forwards an operation and declines a gesture, because a shape answers no key and no press.

### Measuring

This package calls no font backend. A function that needs the width of a text takes `measure(text, font) -> (width, height)` as an argument. `get_canvas_content_bounds(canvas, measure)` returns the box of everything that a canvas draws. `get_graphics_size(document, measure)` returns the size of one primitive. `measure_truetype_text` of [style.md](../style/style.md) needs no display, and `measure_sdl_text` of the SDL backend gives the same widths as the screen.

### Saving to a file

Two functions write a canvas to a file without a window. Each takes a canvas, or a document and a projection that makes one.

```julia
proj = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                          RecursiveProjection(SyntaxToText()),
                          TextToGraphics(measure = measure_truetype_text))
write_image(document, proj, "snapshot.png"; width = 1200, height = 800)
write_pdf(document, proj, "snapshot.pdf")                                   # one page, sized to the content
write_pdf(document, proj, "book.pdf"; paginate = true, width = 612, height = 792)
```

- `write_image` is in the SDL backend. It draws through an offscreen SDL renderer and writes `.bmp` or `.png`; another extension raises an error. With no size, the image fits the content up to 1200 by 800.
- `write_pdf` is in `ProjecturedPdf` and needs no SDL. It writes each primitive as a PDF path or text operator and embeds the fonts as Type0 fonts, so the text is selectable. With `paginate = true`, `height` is the page height, and the content is cut into bands of that height across pages. `measure` defaults to `measure_truetype_text` and sets the page size; the projection that makes the canvas keeps its own `measure`.
- `GraphicsCanvasToImageFile` and `GraphicsCanvasToPdfFile` are the same steps as the last stage of a chain. Their output is an `ImageFile`, and they have no reader.

[devices-and-backends.md](../kernel/devices-and-backends.md) describes the backends that paint a canvas on a screen.

## How it fits

The code is in `source/graphics/`. `ProjecturedGraphics` depends on the kernel, `ProjecturedCollection`, `ProjecturedProjection` and `ProjecturedStyle`. `TextToGraphics` produces most canvases. Layouts, widgets, graphs, charts and sequence charts produce shapes directly. [screen.md](../screen/screen.md) holds the window documents whose content is a canvas. The SDL backend, the web backend and the PDF writer paint canvases.

It registers nothing and has no `__init__`.

## Design decisions

- **A colour is a `StyleColor`, not four bytes.** SDL, PDF and the web backend each need a different device encoding, so each backend converts at draw time. A converted cache in the document would fit only one of them. See `plan/done/graphics-stylecolor-and-coordinate-normalization.md`.
- **Every coordinate is `Int32`.** The canvas uses the same type as the primitives. The same plan holds the change.
- **The measure is an argument.** The package and `TextToGraphics` above it then need neither SDL nor a PDF library, and a test measures with `measure_truetype_text`.
- **A fence is an element, not a flag.** No primitive needs an extra field, and the renderer and the hit test skip it with one `isa` check.
- **Non-overlap is declared, not computed.** The producer, for example a table that stacks its rows, sets `overlapping_elements = false` or puts a fence where it can guarantee it.

## Usage

```julia
label  = GraphicsText("Hello", 10, 20; font = font_ubuntu_monospace_regular_24, color = color_white)
caret  = GraphicsRect(100, 50, 2, 20, color_red)
card   = GraphicsRect(0, 0, 120, 24, color_white, 4; border_width = 1, border_color = color_black)
edge   = GraphicsLine(0, 0, 100, 40; color = color_black, width = 2, dash = (4, 2))
canvas = GraphicsCanvas([label, caret]; w = 400, h = 100)
column = GraphicsCanvas(CellVector(Cell[Cell(label), Cell(caret)]), layout_vertical)
label.x = 50                          # writes through the cell
hit_element_at(canvas, 60, 25)        # the offset of the element, or nothing
```

- Example: `graphics_image_example` draws a JSON document through the text chain; `make_graphics_image_projection_example()` builds the chain.
- Tests: `test_graphics()` in `test/substrate/document/GraphicsDocumentTest.jl`. `GraphicsLayoutTest.jl` beside it covers the layout projections.

## Limits

- `GraphicsCanvasToGraphicsImage` does not rasterize, and no plan tracks the rasterizing cache.
- A `GraphicsText` in a canvas with no size takes every point to its right.
- The PDF writer does not compress its content streams or subset its fonts. It draws a `GraphicsImage` only when `data` is an RGBA byte buffer; an SDL texture has no pixels that it can read.
- A viewport transform can not rotate or shear its content.
