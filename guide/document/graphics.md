# Graphics Domain

The graphics domain provides rendering primitives for the SDL2 backend. It represents visual elements as reactive documents that can be projected to the screen.

## Types

- **GraphicsText**: Rendered text with position and styling
- **GraphicsRect**: Rectangle for cursor, selection, or decoration
- **GraphicsCanvas**: Container holding a collection of graphics elements

## Examples

```julia
# Create graphics text
gtext = GraphicsText(
    TextString("Hello"),
    x = Cell(10),
    y = Cell(20),
    font = "monospace",
    color = "white"
)

# Create a rectangle (e.g., for cursor)
rect = GraphicsRect(
    x = Cell(100),
    y = Cell(50),
    width = Cell(10),
    height = Cell(20),
    color = "red"
)

# Create a canvas
canvas = GraphicsCanvas(
    width = Cell(800),
    height = Cell(600),
    elements = CellVector([Cell(gtext), Cell(rect)])
)

# Access and modify
gtext.x[] = 50
rect.color[] = "blue"
push!(canvas.elements, Cell(new_element))
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
