# Text Domain

The text domain bridges structural (syntax tree) and visual (graphics) domains. Text is stored as a flat sequence of spans, each with its own reactive style and color. Selection is a flat character offset.

**Indexing conventions**: paths use `[i]` for the i-th item (1-based) and `{k}` for the cursor at boundary `k` (0-based). The two are readings of the same axis — see [the boundary axis](../editor/reference.md#the-boundary-axis). In Text the axis appears as spans *and* as characters within a span; the same `[i]` / `{k}` syntax addresses both.

## Types

- **TextString**: A text span with content and styling
- **TextNewline**: Line break with styling
- **TextSpacing**: Horizontal or vertical spacing
- **TextGraphics**: Embedded graphics within text

## Examples

```julia
# Create a simple text span
span = TextString("Hello", "bold", "red")

# Create with just content
span = TextString("world")

# Styled text
span = TextString("Important!", "bold italic", "#ff0000")

# Create a newline
newline = TextNewline(font="monospace", line_color="gray")

# Create spacing
spacing = TextSpacing(10, unit=:pixel)
spacing = TextSpacing(2, unit=:space)

# Access and modify
span.content[] = "New content"
span.font[] = "italic"
span.font_color[] = "blue"
```

## Selection

Selection is a flat offset across all spans. At the top level, `[i]` selects the i-th span and `{k}` is the cursor between spans. When the path descends into a span, the sub-path indexes characters: `.content[i]` for the i-th character, `.content{k}` for the cursor between characters.

## Styling Fields

Each span has:
- `content::Cell` — the text string
- `font::Cell` — font style (e.g., "bold", "italic", "monospace")
- `font_color::Cell` — text color (name, hex, or rgb)
- `fill_color::Cell` — background fill color
- `line_color::Cell` — border/line color
- `padding::Cell` — inset/padding value

## Key Features

- Each span is independently styled
- Reactive styling updates propagate automatically
- Flat character offset selection for easy navigation
