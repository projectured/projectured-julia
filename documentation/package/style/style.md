# Style

> **Kind:** design · **Status:** current · **Stands on:** [macros.md](../kernel/macros.md), [graphics.md](../graphics/graphics.md)

`ProjecturedStyle` holds the values that everything drawn shares: colours, fonts, styled text, strokes, geometry and images. It also holds a TrueType parser that measures text with no display. It has no projection and registers nothing; this document says why its types have the form they have.

## How it works

| Type | What it is |
| --- | --- |
| `StyleColor` | `red`, `green`, `blue`, `alpha`, each a `Float64` from 0 to 1 |
| `StyleFont` | a font file name and a size |
| `StyleText` | a `StyleFont` and a `StyleColor`, the pair that every text needs |
| `StyleStroke` | a colour, a width and a `dash` |
| `Inset`, `Point2D`, `AffineTransform` | a box of margins, a point, a 2D transform with `∘` |
| `ImageFile`, `ImageMemory` | an image from a file or from memory |

The package also defines about a thousand colour constants (`color_black`, `color_solarized_blue`, the `color_slate_*` and `color_indigo_*` ramps) and a font constant for each font file and size under `asset/font/`, for example `font_ubuntu_monospace_regular_20`.

### Value documents

`StyleColor`, `StyleFont` and `StyleText` are declared with `@document ImmutableCell [DC] struct`. `ImmutableCell` makes every field immutable, and `[DC]` gives the plain type name to that form. So `StyleText` is a value with no reactive cell and no selection, and a projection stores it in an `ImmutableCell{StyleText}` field. The reactive forms exist under prefixed names, such as `RCStyleFont`, for the rare case that needs one. [The layout list](../kernel/macros.md#the-layout-list) in macros.md describes the prefixes.

`StyleStroke`, `Inset`, `Point2D` and `AffineTransform` are plain structs. They have no identity in a reference path.

### Measurement without a display

`measure_truetype_text(text, font)` returns `(width, height)` from the advance widths in the `hmtx` table of the font file. The parser reads only the tables it needs and draws nothing. It is the default `measure` function of every example projection, and the PDF and web backends use it. It has the same contract as `measure_sdl_text`, so a projection runs with or without SDL.

A font does not carry every glyph. `find_glyph_font_file(path, character)` finds the file that has a glyph: the font itself, then DejaVu Sans Mono, then Noto Emoji. `measure_truetype_text` measures each character in the font that draws it. The variation selectors U+FE0E and U+FE0F measure as zero width, because the SDL renderer does no shaping.

### Two zoom settings

The size of text on the screen comes from two separate settings:

- **The display scale.** `_DISPLAY_SCALE` is the DPI scale of the display, which the SDL backend detects, times the uniform zoom of Ctrl+= and Ctrl+-. It is a plain `Ref`. Layout does not read it, so a change needs a repaint and no reactive update.
- **The font zoom.** `_FONT_ZOOM` is the zoom of Ctrl+Alt+= and Ctrl+Alt+-. It is a `Cell`, because layout reads it through `font_logical_size(font)`. A change lays out the text again.

`font_device_size(font)` combines the two, and only a backend reads it. Both settings step through the same table, from 0.5 to 3.0.

## How it fits

`ProjecturedStyle` depends only on the kernel, and it is the lowest package of the drawing chain: style, then graphics, then text, then syntax. Every package that draws uses it. A backend converts a `StyleColor` into its own device format when it draws.

## Design decisions

- **One colour type from the domain to the backend.** `GraphicsRect` and the other primitives take a `StyleColor`, not four bytes. The three backends each need a different byte format, so a byte form cached in the document would be wrong for two of them. See [plan/done/graphics-stylecolor-and-coordinate-normalization.md](../../../plan/done/graphics-stylecolor-and-coordinate-normalization.md).
- **Font and colour travel as one `StyleText`.** A projection has one style field for each kind of text, not a font field and a colour field. A theme can then name a style: body, title, caption. See [plan/done/merge-style-text.md](../../../plan/done/merge-style-text.md).
- **Logical pixels everywhere.** Layout works in logical pixels, and only the backend multiplies by the display scale. So a layout does not change when the window moves to another display. See [plan/done/global-display-scale.md](../../../plan/done/global-display-scale.md).
- **A default cell kind for the whole struct.** `@document ImmutableCell` sets the kind of every field at once. See [plan/done/struct-level-default-kind-and-style-documents.md](../../../plan/done/struct-level-default-kind-and-style-documents.md).

## Usage

```julia
style = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
faint = StyleColor(0.0, 0.0, 0.0, 0.25)
width, height = measure_truetype_text("hello", font_ubuntu_monospace_regular_20)
font_logical_size(font_ubuntu_monospace_regular_20)   # 20 at the default font zoom
```

- Test: no package suite exists. `test_font_metrics()`, `test_font_fallback()` and `test_affine_transform()` in `test/substrate/document/` cover the parser and the geometry.

## Limits

- No backend draws a dashed line. A `dash` value in a `StyleStroke` gives a solid line.
- The check whether a font file exists runs once for each path. A font file that appears later is not found.
