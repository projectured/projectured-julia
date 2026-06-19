# Graphics Domain

<img width="396" alt="Graphics Image example" src="../../image/example/graphics-image.png">

The graphics domain provides the backend-agnostic rendering primitives. It represents visual elements as reactive documents that can be projected to the screen, and is consumed by both the SDL2 backend (native windows) and the web backend (which serializes the same primitives to a JSON draw-list the browser paints — see the [devices and backends guide](../devices-and-backends.md#web-backend)).

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
proj = SequentialProjection(
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
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("snapshot.bmp"; width=1200, height=800),
)
iomap = projection_print(proj, doc)
# iomap.output isa ImageFile
```

`GraphicsCanvasToImageFile` has no reader — it is a write-only, side-effecting
projection.

File formats: `write_image` supports both `.bmp` (built into SDL2) and `.png`
(via `IMG_SavePNG` from SDL2_image); other extensions error.
