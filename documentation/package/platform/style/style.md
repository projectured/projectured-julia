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

A [`TextMeasure`](../../../source/style/TextMeasure.jl) answers what a layout needs to place text, with no display: the box of a string, the metrics of a font with no text, and the x of each character boundary of a string.

- `measure_string(measure, text, font) -> StringBox` is the box of `text` set in `font`: its advance `width`, kerning included, and the largest `ascent`, `descent` and `line_gap` of the fonts that draw its glyphs. The baseline of the string is `ascent` below the top of the box.
- `get_font_metrics(measure, font) -> FontMetrics` is the vertical metrics of `font` with no text: the `ascent`, the `descent` and the `line_gap`.
- `compute_caret_offsets(measure, text, font) -> Vector{Float64}` is the pen position before each character of `text`, `length(text) + 1` values. Each is the pen position where the next character starts, so the caret after "A" in "AV" stands where "V" starts, past the kerning of the pair.

Every value is a real number in logical pixels; a `TextMeasure` rounds nothing. `compute_text_extent(measure, text, font) -> (width, ascent, descent)` rounds the box of `measure_string` to whole logical pixels: the width rounded, and the ascent and the descent rounded up, so the box never ends inside the ink. With no `measure`, it answers the box that a `GraphicsText` draws, from the font files.

`FontFileMeasure()` reads the font files, as every backend draws them: the `hmtx` advance of each glyph, the `kern` pairs between two glyphs of one font, the fallback font of a character the font lacks, and the vertical metrics by FreeType's rule. It is the measure of the application and the exports, and the PDF and web backends use it. `FixedMeasure(advance, ascent, descent, line_gap; fonts = Dict())` answers fixed numbers for a test: every character is `advance` wide, there is no kerning, and every font has the given metrics, except a font that `fonts` gives its own `FontMetrics`.

A font does not carry every glyph. `find_glyph_font_file(path, character)` finds the file that has a glyph: the font itself, then DejaVu Sans Mono, then Noto Emoji. `FontFileMeasure` measures each character in the font that draws it. The variation selectors U+FE0E and U+FE0F measure as zero width, because the SDL renderer does no shaping.

### Line spacing

A [`LineSpacing`](../../../source/style/LineSpacing.jl) sets the distance between the lines of a text, as a word processor sets it. The natural distance of a line is the sum of the largest ascent, descent and line gap of its boxes.

- `SingleSpacing()` sets the lines at their natural distance.
- `MultipleSpacing(factor)` sets the lines at `factor` times their natural distance.
- `ExactSpacing(distance)` sets the lines `distance` logical pixels apart, whatever their fonts.
- `AtLeastSpacing(distance)` sets the lines `distance` logical pixels apart, or at their natural distance when that is larger.

`compute_line_box(measure, text, font; spacing = SingleSpacing())` gives the box of a line that holds one text alone, as a label or a title does: a [`LineBox`](../../../source/style/LineSpacing.jl) with the width, the height, the baseline and the `y` of the text in the box. The baseline sits half of the leading below the top of the box, then the ascent, and never higher than the rounded ascent of the text, so the ink never rises above the box.

**Example.** Ubuntu 20 has an ascent of 18.64, a descent of 3.78 and a line gap of 0.56 logical pixels, so its natural distance is 22.98. `compute_line_box(FontFileMeasure(), "delay", font_ubuntu_regular_20)` at `SingleSpacing()` gives a line box 23 pixels high, with the baseline 19 pixels below its top: half of the line gap, 0.28, and the ascent, rounded.

### Two zoom settings

The size of text on the screen comes from two separate settings:

- **The uniform zoom.** The zoom of Ctrl+= and Ctrl+- is the `zoom` of the `Display` of an editor, in the kernel. The backend multiplies it with the `scale` of the hardware into the device pixel ratio. Layout does not read it, so a change needs a repaint and no reactive update. Each editor has its own.
- **The font zoom.** `_FONT_ZOOM` is the zoom of Ctrl+Alt+= and Ctrl+Alt+-. It is a `Cell`, because layout reads it through `font_logical_size(font)`. A change lays out the text again.

`font_device_size(font, ratio)` combines the font zoom with the device pixel ratio, and only a backend reads it. Both settings step through the same table, from 0.5 to 3.0, with `step_zoom(zoom, delta)`.

## How it fits

`ProjecturedStyle` depends only on the kernel, and it is the lowest package of the drawing chain: style, then graphics, then text, then syntax. Every package that draws uses it. A backend converts a `StyleColor` into its own device format when it draws.

## Design decisions

- **One colour type from the domain to the backend.** `GraphicsRect` and the other primitives take a `StyleColor`, not four bytes. The three backends each need a different byte format, so a byte form cached in the document would be wrong for two of them. See [plan/done/graphics-stylecolor-and-coordinate-normalization.md](../../../plan/done/graphics-stylecolor-and-coordinate-normalization.md).
- **Font and colour travel as one `StyleText`.** A projection has one style field for each kind of text, not a font field and a colour field. A theme can then name a style: body, title, caption. See [plan/done/merge-style-text.md](../../../plan/done/merge-style-text.md).
- **Logical pixels everywhere.** Layout works in logical pixels, and only the backend multiplies by the device pixel ratio. So a layout does not change when the window moves to another display. See [plan/done/global-display-scale.md](../../../plan/done/global-display-scale.md).
- **A default cell kind for the whole struct.** `@document ImmutableCell` sets the kind of every field at once. See [plan/done/struct-level-default-kind-and-style-documents.md](../../../plan/done/struct-level-default-kind-and-style-documents.md).

## Usage

```julia
style = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
faint = StyleColor(0.0, 0.0, 0.0, 0.25)
width, ascent, descent = compute_text_extent("hello", font_ubuntu_monospace_regular_20)
font_logical_size(font_ubuntu_monospace_regular_20)   # 20 at the default font zoom
```

- Test: no package suite exists. `test_font_metrics()`, `test_font_fallback()` and `test_affine_transform()` in `test/substrate/document/` cover the parser and the geometry; `test_text_measure()` and `test_line_spacing()`, in the same folder, cover the measure contract and the line spacing.

## Limits

- No backend draws a dashed line. A `dash` value in a `StyleStroke` gives a solid line.
- The check whether a font file exists runs once for each path. A font file that appears later is not found.
