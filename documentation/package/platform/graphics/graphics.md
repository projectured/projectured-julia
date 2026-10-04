# Graphics domain

> **Kind:** design · **Status:** current · **Stands on:** [style.md](../style/style.md), [devices-and-backends.md](../../kernel/devices-and-backends.md), [text.md](../text/text.md)

The graphics slice of `ProjecturedPlatform` holds the drawing primitives that every chain of projections ends in: text, boxes, lines, curves, canvases and viewports, each a reactive document. A backend paints them, and a hit test finds the primitive under the pointer. This document says how a canvas is built and tested, how a click leaves the graphics stage, and how a canvas is saved to a file.

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
| `GraphicsPointerShape` | nothing; a region where the pointer takes a shape, described below |

Every field is a reactive cell, so a change of one coordinate repaints only what reads it. A colour is a `StyleColor` and a font is a `StyleFont`, both from [style.md](../style/style.md). Each backend converts a `StyleColor` to its own device encoding when it draws. Coordinates are `Int32` pixels, and a box names its size `w` and `h`. Elements draw in order, so a later element is on top.

`y` of a `GraphicsText` is the top of its box, and the baseline is `y` plus the ascent that [`compute_text_extent`](../style/style.md) gives for `text` and `font`. The box is the ascent plus the descent high. Every backend draws the baseline there, and a layout that puts texts of different fonts on one baseline sets each `y` to the baseline minus that text's own ascent.

The spline and arrowhead geometry is computed here, by `tessellate_spline` and `build_polyline_arrowhead`, so each backend draws the same points. The backends draw only the translation and the scale of a viewport transform.

### The canvas and the hit test

`GraphicsCanvas.elements` is a `CellVector` or a `ListNode`. A `ListNode` can be a list without an end in either direction; see [collection.md](../collection/collection.md). `layout` names the axis along which the canvas can grow without an end: `layout_none`, `layout_horizontal` or `layout_vertical`. A backend paints only the elements between the edges of its clip. On a `CellVector` canvas with a layout and elements that do not overlap, it starts at `compute_first_visible_index(canvas, edge)`, a binary search for the last element that starts at or before the near edge, and it stops at the first element past the far edge. A `ListNode` is walked both ways from its head to the edges. The backend does not read the content of an element that it does not paint. The dirty walk and `hit_element_at` follow the same rule.

`hit_element_at(canvas, x, y)` returns the offset of the first element that contains the point, or `nothing`. Every caller in `source/` tests only for `nothing`. The test for each shape:

- A box, a viewport, an image and a line use their bounding box. A circle uses its radius.
- A text uses its box: the width, the ascent and the descent of [`compute_text_extent`](../style/style.md).
- A polyline and a spline take a band of `max(3, width + 2)` pixels around the path. A polygon takes its whole interior.
- A canvas tests its own elements, with the point moved into its frame.

A canvas with a `w` or `h` that is not zero first clips the point to its own box. This clip is what keeps a text on the left of a row from taking the clicks of its right neighbour. An auto-sized canvas, with `w` and `h` zero, does not clip.

**The producer declares that elements do not overlap, and nothing checks it.** With `overlapping_elements = false` and a `layout`, the renderer and the hit test stop at the first element past the visible edge or past the point. A `GraphicsFence` in the element list states that the elements before it and after it do not overlap on the layout axis. It draws nothing, and both the renderer and the hit test skip it. A canvas that declares no overlap and has overlapping elements misses hits.

`has_declared_extent(canvas)` is true for a canvas with a layout, elements that do not overlap, and `w > 0` and `h > 0`. Such a canvas declares its extent: `get_graphics_size` and the dirty bounds take its box and do not walk its elements, so a size query reads no element of a long list.

### The shape of the pointer

`GraphicsPointerShape(x, y, w, h, shape)` is a region where the pointer takes `shape`. It draws nothing. A part puts one into what it draws where a press does something: the edge of a column, the divider of a split pane, a text that a person edits. `shape` is one of nine symbols, named by the picture and kept in `POINTER_SHAPES`: `arrow`, `ibeam`, `double_arrow_horizontal`, `double_arrow_vertical`, `pointing_hand`, `open_hand`, `closed_hand`, `crossed_circle` and `hourglass`. A backend maps each one to a cursor of its own, and shows the arrow for a shape it does not know.

`find_pointer_shape(canvas, x, y)` finds the shape at a point of `canvas`, the root canvas of a window: the `shape` of the last region that holds the point, in the order of the drawing, or `default` where no region holds it. The walk follows the drawing of a backend:

- The root canvas is at the origin of the window.
- A nested canvas moves its elements by its place and clips nothing.
- A viewport clips the regions inside it to its box, and moves them by its content and its transform.
- A canvas that lays out its elements without overlap walks only the elements at the point, from the first one that reaches it, as `hit_element_at` does: a list of rows that the viewport does not show is not walked.
- A canvas that declares its extent and does not hold the point is not walked either.

Where regions overlap, the last one in the order of the drawing wins.

**A region in a laid-out canvas is an element of the order.** A canvas that lays out its elements without overlap reads a region the same way it reads any other element: put a region there only where its place keeps the order of the elements, or put it in a canvas with no layout.

### Selection and clicks

`make_selection_ring(bounds)` returns one border-only `GraphicsRect` whose geometry cells read `bounds()`. When `bounds()` returns `nothing`, the ring has zero size and draws nothing. A layout or a widget container keeps the ring in its element list at all times. So a selection move changes four cells of the ring, and the element list keeps its shape.

`GraphicsTheme` holds the color, the width and the corner radius of the ring, the color of the band under a selected row of a list, a tree or a table, the gap between the blocks of a collection drawn as a stack, and the font and the color of the mark that `FaultToGraphics` draws. The ring and the band are each a role of the colour theme, `selection_ring::StyleColor = ColorRole(:selection_ring)` and `selection_band::StyleColor = ColorRole(:selection_band)`, so the colour settings of the appearance choose them; [style.md](../style/style.md#colours) describes a role and how it resolves to a colour. The graphics and the layouts lie below every other slice that draws, so they take these styles from this theme and from no other. A container holds the values of the theme as one field, which `make_theme_values_field(GraphicsTheme, theme)` makes: a cell that reads a scaled theme at each read, or the plain values of the default theme for `nothing`. `make_selection_ring(bounds, style)` takes those values. `LayoutToGraphics(; theme)` gives them to each layout, and the widgets read the graphics theme of the appearance of their own theme.

`find_first_baseline(iomap)` answers the baseline of the first line of text that the output of `iomap` draws, in pixels from the top of that output, or `nothing` when it draws no text. A wrapper answers what it wraps: a chain the IoMap of its last stage, a barrier its content, and a container of placed children its first child that has one, offset by the place of that child. A `HorizontalLayout` with `vertical_align = :baseline` reads it from each child, so a label beside a text of another font or line spacing stands on the same baseline; [layout.md](../layout/layout.md) describes it.

`PointReferenceStep(x, y)` names a pixel inside an element, written `.point(x, y)` in `@reference`. The reader of `GraphicsCanvasToGraphicsImage`, below, makes a click into `ElementReferenceStep(i)` followed by a `PointReferenceStep`, and `TextToGraphics` in [text.md](../text/text.md) turns that into a character offset. The kernel reference layer never names the step.

`RegionReferenceStep(x, y, width, height)` names a box in the frame of the node before it, which no node of its own draws. A forward map answers it after the smallest node that holds all of the image of a part, when that image is no node and no range of one text, such as a text range across segments ([reference.md](../../kernel/reference.md), "The place of a part").

`shift_event_position(event, dx, dy)` moves a pointer event or gesture into the frame of a child, and `shift_operation_position` moves the answer of the child back. A widget reads a point in the frame of its own canvas, so a container moves the event by the place of the child before it hands it down.

### The part under the pointer

Every move of the pointer, with a button held or not, names the part under the pointer, and every container gives it to two children: first to the child that the pointer leaves, then to the child that it is on. Three functions serve every container, in the layout, the widget, the graph and the screen packages:

- `read_child_move(child_iomap, move)` is the answer of the child under the pointer. When the child names no part under the pointer, its own backward map of the point names it, and a child that maps the point to no part is the part itself. So a list names its row, and a text names the place of the point, with no code of their own.
- `compute_part_at_point(iomap, x, y)` is that backward map: the path of the part at the point, with the types that the map gives it. A point step at the end of the path is dropped.
- `read_child_leave(child_iomap, event, dx, dy)` is the answer of the child that the pointer leaves, whose frame lies at `(dx, dy)`. The child gets the move at `(-1, -1)` of its own frame, a point off it and off each part in it, because a part that a pane clips, or a child under another child, can be at the real point. So the child names no part. It gives the move on to the part that it holds, and each part on the old path answers the leave: a button clears `pressed`.
- `get_child_frame_offset(entry)` is the place of the frame of a child, from the `(x, y, child_iomap)` entry that a container keeps.

The container finds the child that the pointer leaves from its own mouse target (`get_mouse_target` of the kernel), and joins the two answers with `join_move_answers`, the answer of the child that the pointer leaves first.

### A route moves the point

A change with a route ([projection-system.md](../../kernel/projection-system.md#the-intent-the-reader-threads)) that reaches a container whose children sit in frames of their own gets the point of a pointer gesture moved into the frame of the child the route names, the same move the container gives a gesture it hands to that child at a point. `read_child_by_route(projection, recursion, change, iomap, child)` is the hook: the kernel's default reads `child` with `change` unchanged, and a container that draws its children in frames of their own adds a method for its own projection.

- `map_event_position(event, move)` returns `event`, a pointer event or gesture, with its position replaced by `move(x, y) -> (x, y)`; an event with no position comes back unchanged. A container whose placement scales a child, such as a zoom, uses it.
- `read_routed_child_in_frame(recursion, change, child; move_in, move_out)` moves the point of a pointer gesture into the frame of `child` with `move_in`, reads `child`, and moves every position of the answer back with `move_out`. A change that already carries an operation, or a gesture with no point, goes to `child` unchanged.
- `read_routed_entry_child(recursion, change, child; entries)` is the same, for a container that keeps each child as an `(x, y, child_iomap)` entry: it finds the offset of `child` with `get_child_frame_offset` and builds `move_in` and `move_out` from it.

So a part that a route reaches, such as the part whose drag is on, gets the point of its `DragMove` and its `DragEnd` in its own frame, wherever the container has placed it; see [dragtracking.md](../dragtracking/dragtracking.md).

### A dwell and a right click

A dwell goes by its position, as a click does: each container gives it to the child at its point, in the frame of that child, and the readers decide. A reader can deny a dwell with an answer that ends the walk, such as `DoNothingOperation`. Then the gesture tables answer, from the part under the point outward (decision D64 of the events plan). Three functions serve every container:

- `is_outward_gesture(gesture)` is true for a dwell and for a click of the right button.
- `read_child_part_gesture(child_iomap, gesture)` is the answer of the documents inside a child that did not answer: the backward map of the point names the part, and the documents on that path read the gesture with their tables, the part first. `read_child_event` of the layout package calls it, and the window calls it for its content. So a text, which draws a whole document as one leaf, gives a dwell to the part of the document under the pointer.
- `read_container_gesture(answer, gesture, document; steps)` is the answer of a container after the child at the point answered: the documents of its own stretch, from the one above the child up to its input, read the gesture with their tables. It calls `read_gesture_outward` of the kernel, which keeps the rule of the walk: a document reads when nothing deeper answered or when the deeper answer collects, a collected answer of the same kind is joined, and any other answer ends the walk.

A point in the answer moves back into the frame of each container on the way out, so a tooltip opens beside the pointer, and a context menu opens at it ([context-menu.md](../widget/context-menu.md)).

### The box of a part

`find_reference_box(document, reference; measure, visible)` reads the box `(x, y, width, height)` of the node that a reference reaches in a printed document, in the frame of the document's place. Each node on the way moves the frame by its place, and a viewport moves its content by its transform too. A text has the box of what it draws, measured with `measure`, and `text{a:b}` the box of those characters. A `RegionReferenceStep` is its box. A canvas with no size of its own on an axis has the bounds of what it draws there (`get_canvas_content_bounds`), except over a lazy list, which can have no end. With `visible = true`, each viewport on the way cuts the box to its own, and a box that no viewport shows is `nothing`.

`find_node_reference(document, node; depth)` finds a printed node by identity, level by level through the elements of canvases and the contents of viewports, and answers the reference to it. A container that puts parts of its own before its children uses it in its forward map.

`GraphicsCaching(; render)` is a dispatching projection over canvases. A finite canvas that holds no canvas and no viewport goes to `GraphicsCanvasToGraphicsImage`. The other canvases, the viewports and the collections are copied, so the recursion reaches their children. **`GraphicsCanvasToGraphicsImage` does not rasterize, although its name says so.** It returns a canvas, not a `GraphicsImage`. It puts a pale checkerboard behind the elements, so each cached region shows in a different colour. Its reader resolves a click to a `GraphicsRect` that contains the point. If no box contains it, the reader takes the `GraphicsText` on the same line with the largest `x` at or left of the point. `run_example(...; caching = true)` adds it to a chain.

`GraphicsToGraphics()` is the natural projection of a graphics document: its output is its input. `NaturalToGraphics` uses it, so a shape that a person makes, for example in the evaluator, draws as the shape and not as a tree of its fields. Its reader forwards an operation and declines a gesture, because a shape answers no key and no press.

### Moving the position an operation carries

`map_operation_position(operation, move)` returns `operation` with every position it carries replaced by `move(x, y) -> (x, y)`. It moves each member of a `CompoundOperation` and the operation inside a `WrappingOperation`; an operation that carries no position, and `nothing`, come back unchanged. A package that defines an operation with a position, such as a popup that a widget opens, adds a method of `map_operation_position` for it, so a reader can apply the function to any answer it gets back.

`shift_operation_position(operation, dx, dy)` is the common case: `operation` with every position moved by `(dx, dy)`. A reader that reads a child with a pointer event at `(lx, ly)` for its own `(x, y)` shifts the child's answer by `(x - lx, y - ly)`, the offset at which it placed that child. A reader whose placement scales its child, such as a zoom, calls `map_operation_position` with the scaling map instead. [screen.md](../screen/screen.md) and [widget.md](../widget/widget.md) show how a popup's position reaches the screen this way.

### Measuring

This package calls no font backend. A function that needs the box of a text takes a `TextMeasure`, from [style.md](../style/style.md), as an argument, `FontFileMeasure()` by default. `get_canvas_content_bounds(canvas, measure)` returns the box of everything that a canvas draws. `get_graphics_size(document, measure)` returns the size of one primitive; a bare `GraphicsText` outside a canvas has its width there. Both read a `ContentBounds`, the box that grows as it is extended: `extend_element_bounds!(bounds, element, origin; measure)` adds what an element draws, `extend_canvas_bounds!` what the elements of a canvas draw, `extend_content_bounds!` a box, and `get_content_box` reads it. A backend that repaints what changed, such as SDL and the web, passes one through its walk. The measure of `extend_element_bounds!` is the same, so the bounds of a canvas cover the box of each text it holds.

### Saving to a file

Two functions write a canvas to a file without a window. Each takes a canvas, or a document and a projection that makes one.

```julia
proj = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                          RecursiveProjection(SyntaxToText()),
                          TextToGraphics(measure = FontFileMeasure()))
write_image(document, proj, "snapshot.png"; width = 1200, height = 800)
write_pdf(document, proj, "snapshot.pdf")                                   # one page, sized to the content
write_pdf(document, proj, "book.pdf"; paginate = true, width = 612, height = 792)
```

- `write_image` is in the SDL backend. It draws through an offscreen SDL renderer and writes `.bmp` or `.png`; another extension raises an error. With no size, the image fits the content up to 1200 by 800.
- `write_pdf` is in `ProjecturedPDF` and needs no SDL. It writes each primitive as a PDF path or text operator and embeds the fonts as Type0 fonts, so the text is selectable. With `paginate = true`, `height` is the page height, and the content is cut into bands of that height across pages. It draws from the font files, so it takes no `measure` keyword and sizes its pages by the boxes of the font files; the projection that makes the canvas keeps its own `measure`.
- `GraphicsCanvasToImageFile` and `GraphicsCanvasToPdfFile` are the same steps as the last stage of a chain. Their output is an `ImageFile`, and they have no reader.

[devices-and-backends.md](../../kernel/devices-and-backends.md) describes the backends that paint a canvas on a screen.

## How it fits

The code is in `source/platform/graphics/`. The graphics slice depends on the kernel and on the collection, projection and style slices. `TextToGraphics` produces most canvases. Layouts, widgets, graphs, charts and sequence charts produce shapes directly. [screen.md](../screen/screen.md) holds the window documents whose content is a canvas. The SDL backend, the web backend and the PDF writer paint canvases.

It registers nothing and has no `__init__`.

## Design decisions

- **A colour is a `StyleColor`, not four bytes.** SDL, PDF and the web backend each need a different device encoding, so each backend converts at draw time. A converted cache in the document would fit only one of them. See [plan/done/graphics-stylecolor-and-coordinate-normalization.md](../../../../plan/done/graphics-stylecolor-and-coordinate-normalization.md).
- **Every coordinate is `Int32`.** The canvas uses the same type as the primitives. The same plan holds the change.
- **The measure is an argument.** The package and `TextToGraphics` above it then need neither SDL nor a PDF library, and a test measures with a `FixedMeasure`.
- **A fence is an element, not a flag.** No primitive needs an extra field, and the renderer and the hit test skip it with one `isa` check.
- **Non-overlap is declared, not computed.** The producer, for example a table that stacks its rows, sets `overlapping_elements = false` or puts a fence where it can guarantee it.

## Usage

```julia
label  = GraphicsText("Hello", 10, 20; font = StyleFont("Ubuntu Mono", 24), color = color_white)
caret  = GraphicsRect(100, 50, 2, 20; color = color_red)
card   = GraphicsRect(0, 0, 120, 24; color = color_white, radius = 4, border_width = 1, border_color = color_black)
edge   = GraphicsLine(0, 0, 100, 40; color = color_black, width = 2, dash = (4, 2))
canvas = GraphicsCanvas([label, caret]; w = 400, h = 100)
column = GraphicsCanvas(CellVector(Cell[Cell(label), Cell(caret)]), layout_vertical)
label.x = 50                          # writes through the cell
hit_element_at(canvas, 60, 25)        # the offset of the element, or nothing
```

- Example: `graphics_image_example` draws a JSON document through the text chain; `make_json_projection_example()` of `ProjecturedJSONExample` builds the chain.
- Tests: `test_graphics()` in `test/platform/document/GraphicsDocumentTest.jl`. `GraphicsLayoutTest.jl` beside it covers the layout projections, and `test_pointer_shape()` in `PointerShapeTest.jl` covers `find_pointer_shape`.

## Limits

- `GraphicsCanvasToGraphicsImage` does not rasterize, and no plan tracks the rasterizing cache.
- The PDF writer does not compress its content streams or subset its fonts. It draws a `GraphicsImage` only when `data` is an RGBA byte buffer; an SDL texture has no pixels that it can read.
- A viewport transform can not rotate or shear its content.
