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
