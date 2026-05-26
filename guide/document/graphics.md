# Graphics Domain

The graphics domain provides rendering primitives for the SDL2 backend. It represents visual elements as reactive documents that can be projected to the screen.

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
- `x::Cell` — horizontal position
- `y::Cell` — vertical position
- `width::Cell` — element width
- `height::Cell` — element height

## Styling

- `font` — font family and style
- `color` — text or fill color
- All styling fields are reactive Cells

## Key Features

- Reactive rendering — changes update automatically
- Canvas can hold mixed graphics elements
- Coordinates are reactive for animations
- Integrates with SDL2 backend for display

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

File format roadmap: BMP is built into SDL2 and needs no extra dependencies.
PNG output is a future extension (requires SDL_image).
