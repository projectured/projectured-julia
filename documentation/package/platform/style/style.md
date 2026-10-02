# Style

> **Kind:** design · **Status:** current · **Stands on:** [macros.md](../../kernel/macros.md), [graphics.md](../graphics/graphics.md)

The style slice of `ProjecturedPlatform` holds the values that everything drawn shares: colours, fonts, styled text, strokes, geometry and images. It also holds a TrueType parser that measures text with no display. It has no projection and registers nothing; this document says why its types have the form they have.

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

`StyleColor`, `StyleFont` and `StyleText` are declared with `@document ImmutableCell [DC] struct`. `ImmutableCell` makes every field immutable, and `[DC]` gives the plain type name to that form. So `StyleText` is a value with no reactive cell and no selection, and a projection stores it in an `ImmutableCell{StyleText}` field. The reactive forms exist under prefixed names, such as `RCStyleFont`, for the rare case that needs one. [The layout list](../../kernel/macros.md#the-layout-list) in macros.md describes the prefixes.

`StyleStroke`, `Inset`, `Point2D` and `AffineTransform` are plain structs. They have no identity in a reference path. A `.pred` file can hold an `Inset` and a `Point2D`, because the slice adds `is_pred_constructible` for them: a saved window keeps its size, its scroll position and its margins.

### Measurement without a display

A [`TextMeasure`](../../../../source/platform/style/TextMeasure.jl) answers what a layout needs to place text, with no display: the box of a string, the metrics of a font with no text, and the x of each character boundary of a string.

- `measure_string(measure, text, font) -> StringBox` is the box of `text` set in `font`: its advance `width`, kerning included, and the largest `ascent`, `descent` and `line_gap` of the fonts that draw its glyphs. The baseline of the string is `ascent` below the top of the box.
- `get_font_metrics(measure, font) -> FontMetrics` is the vertical metrics of `font` with no text: the `ascent`, the `descent` and the `line_gap`.
- `compute_caret_offsets(measure, text, font) -> Vector{Float64}` is the pen position before each character of `text`, `length(text) + 1` values. Each is the pen position where the next character starts, so the caret after "A" in "AV" stands where "V" starts, past the kerning of the pair.

Every value is a real number in logical pixels; a `TextMeasure` rounds nothing. `compute_text_extent(measure, text, font) -> (width, ascent, descent)` rounds the box of `measure_string` to whole logical pixels: the width rounded, and the ascent and the descent rounded up, so the box never ends inside the ink. With no `measure`, it answers the box that a `GraphicsText` draws, from the font files.

`FontFileMeasure()` reads the font files, as every backend draws them: the `hmtx` advance of each glyph, the `kern` pairs between two glyphs of one font, the fallback font of a character the font lacks, and the vertical metrics by FreeType's rule. It is the measure of the application and the exports, and the PDF and web backends use it. `FixedMeasure(advance, ascent, descent, line_gap; fonts = Dict())` answers fixed numbers for a test: every character is `advance` wide, there is no kerning, and every font has the given metrics, except a font that `fonts` gives its own `FontMetrics`.

A font does not carry every glyph. `find_glyph_font_file(path, character)` finds the file that has a glyph: the font itself, then DejaVu Sans Mono, then Noto Emoji. `FontFileMeasure` measures each character in the font that draws it. The variation selectors U+FE0E and U+FE0F measure as zero width, because the SDL renderer does no shaping.

### Line spacing

A [`LineSpacing`](../../../../source/platform/style/LineSpacing.jl) sets the distance between the lines of a text, as a word processor sets it. The natural distance of a line is the sum of the largest ascent, descent and line gap of its boxes.

- `SingleSpacing()` sets the lines at their natural distance.
- `MultipleSpacing(factor)` sets the lines at `factor` times their natural distance.
- `ExactSpacing(distance)` sets the lines `distance` logical pixels apart, whatever their fonts.
- `AtLeastSpacing(distance)` sets the lines `distance` logical pixels apart, or at their natural distance when that is larger.

`compute_line_box(measure, text, font; spacing = SingleSpacing())` gives the box of a line that holds one text alone, as a label or a title does: a [`LineBox`](../../../../source/platform/style/LineSpacing.jl) with the width, the height, the baseline and the `y` of the text in the box. The baseline sits half of the leading below the top of the box, then the ascent, and never higher than the rounded ascent of the text, so the ink never rises above the box.

**Example.** Ubuntu 20 has an ascent of 18.64, a descent of 3.78 and a line gap of 0.56 logical pixels, so its natural distance is 22.98. `compute_line_box(FontFileMeasure(), "delay", font_ubuntu_regular_20)` at `SingleSpacing()` gives a line box 23 pixels high, with the baseline 19 pixels below its top: half of the line gap, 0.28, and the ascent, rounded.

### Themes and the appearance

A **theme** is a document that holds the fonts, the colors and the sizes that the
projections of one domain draw with. `@theme struct JsonTheme … end` declares it,
with a default for each field, so `JsonTheme()` is the default theme. The type of a
field says which scale applies to it:

| Type of the field | Scale |
| --- | --- |
| `StyleFont`, and the font of a `StyleText` | font scale |
| `StyleStroke`, its width | line scale |
| `Spacing` | spacing scale |
| `Radius` | radius scale |
| `LineWidth` | line scale |
| `ControlSize` | control scale |
| `IconSize` | icon scale |

The five types of length wrap a number, an `Inset` or a `Point2D` in logical pixels.
Any other value, such as a color, takes no scale. A field of a document is a plain
cell whose declared type is not checked, so the declared type decides the kind:
a bare number in a field declared `Radius` scales as a radius
(`convert_theme_value`). `scale_length` multiplies a length
and keeps a length above 0 at least 1, so a line or a gap never disappears.

A string before a field is the docstring of the field, as in a plain struct, and
it says what the value draws. `@theme` keeps the docstrings in
`get_theme_field_texts(JsonTheme)`, so they need no docstring of the type, and
`find_theme_field_text(JsonTheme, :key_text)` reads one; the appearance tab shows
it as the tooltip of the name of the field. `get_theme_presets(T)` names the presets
of a theme type, which the tab offers; a type has none unless it adds a method.

`@theme` also declares the **scaled theme**, `ScaledJsonTheme`: for each field, a
computed cell that holds the value of the theme times its scale. The cell follows a
change of the field and of the scale. A projection reads the scaled theme; a person
edits the theme. A scaled theme also keeps the appearance whose scales it follows
(`get_theme_appearance`), so a projection can scale a length that is not a value
of its theme.

An **`Appearance`** holds what a person sets about the look of one editor: the
`zoom`, the six scales (`font_scale`, `icon_scale`, `spacing_scale`, `control_scale`,
`radius_scale`, `line_scale`), and for each domain its theme and its scaled theme,
found by the type that the declaration names (`get_theme_type`).
`get_scaled_theme!(appearance, JsonTheme)` answers the scaled theme, and makes and
stores the default theme at the first request; a projection calls it while it is
built, never while it prints. `set_theme!(appearance, theme)` puts another theme in
place, such as a preset. `make_scaled_theme(theme)` scales a theme with no
appearance, at a scale of 1.

**A projection reads a theme through its style fields.** A projection declared
`@projection UntrackedCell struct` holds one field for each value that it draws.
Its constructor takes `theme`, calls `scale_theme(theme)` once, and gives each
field `make_style_field(K, theme, T; name)`: with a scaled theme of `K`, a cell
that reads the value at each read with no edge (`make_theme_cell`); with no theme,
the plain value of the default theme (`get_theme_defaults(K)`, made once for each
theme type). So a projection that a printer builds at each print makes no theme,
and a view shows a change of a theme when the `appearance` wrapper prints it
again. A plain struct holds such a field in an `Any` field and reads it with
`unwrap_cell`.

### The zoom and the scales

The size of things on the screen comes from the `Appearance` of an editor: its
`zoom` and its six scales (`font_scale`, `icon_scale`, `spacing_scale`,
`control_scale`, `radius_scale`, `line_scale`). `AdjustZoomOperation` and
`AdjustScaleOperation`, and the keys that reach them, are bindings of the
`appearance` wrapper of `build_editor`; an editor built with no `Appearance` has
no zoom keys.

- **The zoom.** `AdjustZoomOperation` steps `appearance.zoom` and copies it into
  the `zoom` of the `Display` of the editor. The backend multiplies it with the
  `density` of the hardware into the device pixel ratio. Layout does not read
  it, so a change needs a repaint and no reactive update. Each editor has its
  own.
- **The scales.** `AdjustScaleOperation` steps one of the six scales, which
  `scale_theme_value` applies while a theme is scaled: a font's size, among
  other values, already carries the scale by the time a projection reads it.
  `font_logical_size(font)` therefore reads no scale of its own — it is
  `font.size`. A scale reaches no cell of the view, so a change needs a new
  print of the whole view, not a relayout underneath the old one.

`font_device_size(font, ratio)` combines a font's logical size with the device
pixel ratio, and only a backend reads it. The zoom and the scales step through
the same table, from 0.5 to 3.0, with `step_factor(scale, delta)`.

## How it fits

The style slice depends on the kernel and on the serialization slice, whose seam `is_pred_constructible` it extends. It is the lowest slice of the drawing chain: style, then graphics, then text, then syntax. Every slice that draws uses it. A backend converts a `StyleColor` into its own device format when it draws.

## Design decisions

- **One colour type from the domain to the backend.** `GraphicsRect` and the other primitives take a `StyleColor`, not four bytes. The three backends each need a different byte format, so a byte form cached in the document would be wrong for two of them. See [plan/done/graphics-stylecolor-and-coordinate-normalization.md](../../../../plan/done/graphics-stylecolor-and-coordinate-normalization.md).
- **Font and colour travel as one `StyleText`.** A projection has one style field for each kind of text, not a font field and a colour field. A theme can then name a style: body, title, caption. See [plan/done/merge-style-text.md](../../../../plan/done/merge-style-text.md).
- **Logical pixels everywhere.** Layout works in logical pixels, and only the backend multiplies by the device pixel ratio. So a layout does not change when the window moves to another display. See [plan/done/global-display-scale.md](../../../../plan/done/global-display-scale.md).
- **A default cell kind for the whole struct.** `@document ImmutableCell` sets the kind of every field at once. See [plan/done/struct-level-default-kind-and-style-documents.md](../../../../plan/done/struct-level-default-kind-and-style-documents.md).

## Usage

```julia
style = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
faint = StyleColor(0.0, 0.0, 0.0, 0.25)
width, ascent, descent = compute_text_extent("hello", font_ubuntu_monospace_regular_20)
font_logical_size(font_ubuntu_monospace_regular_20)   # 20, the font's own size
```

- Test: no package suite exists. `test_font_metrics()`, `test_font_fallback()` and `test_affine_transform()` in `test/platform/document/` cover the parser and the geometry; `test_text_measure()` and `test_line_spacing()`, in the same folder, cover the measure contract and the line spacing.

## Limits

- No backend draws a dashed line. A `dash` value in a `StyleStroke` gives a solid line.
- The check whether a font file exists runs once for each path. A font file that appears later is not found.
