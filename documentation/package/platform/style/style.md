# Style

> **Kind:** design · **Status:** current · **Stands on:** [macros.md](../../kernel/macros.md), [graphics.md](../graphics/graphics.md)

The style slice of `ProjecturedPlatform` holds the values that everything drawn shares: colours, fonts, styled text, strokes, geometry and images. It also holds a TrueType parser that measures text with no display. It has no projection and registers nothing; this document says why its types have the form they have.

## How it works

| Type | What it is |
| --- | --- |
| `StyleColor` | `red`, `green`, `blue`, `alpha`, each a `Float64` from 0 to 1 |
| `StyleFont` | a family, a size in logical pixels, a weight and a slant |
| `StyleText` | a `StyleFont` and a `StyleColor`, the pair that every text needs |
| `StyleStroke` | a colour, a width and a `dash` |
| `Inset`, `Point2D`, `AffineTransform` | a box of margins, a point, a 2D transform with `∘` |
| `ImageFile`, `ImageMemory` | an image from a file or from memory |

The package also defines about a thousand colour constants (`color_black`, `color_solarized_blue`, the `color_slate_*` and `color_indigo_*` ramps). A font has no constants: a font is a description, and a theme or a document writes it where it is used.

### Value documents

`StyleColor`, `StyleFont` and `StyleText` are declared with `@document ImmutableCell [DC] struct`. `ImmutableCell` makes every field immutable, and `[DC]` gives the plain type name to that form. So `StyleText` is a value with no reactive cell and no selection, and a projection stores it in an `ImmutableCell{StyleText}` field. The reactive forms exist under prefixed names, such as `RCStyleFont`, for the rare case that needs one. [The layout list](../../kernel/macros.md#the-layout-list) in macros.md describes the prefixes.

`StyleStroke`, `Inset`, `Point2D` and `AffineTransform` are plain structs. They have no identity in a reference path. A `.pred` file can hold an `Inset` and a `Point2D`, because the slice adds `is_pred_constructible` for them: a saved window keeps its size, its scroll position and its margins.

### Fonts and their faces

A font is a description, as in CSS: `StyleFont("Ubuntu Mono", 14; weight = 700, italic = true)`. The weight is on the scale of CSS and OpenType, from 100 to 900, where 400 is regular and 700 is bold. A font is 24 bytes and is stored inline, so a new font allocates nothing and two equal fonts are one value. `with_font_size(font, size)` gives the font at another size.

A [`FontFace`](../../../../source/platform/style/FontFace.jl) is one face of a bundled family: its family, its weight, its slant and its file under `asset/font/`. The table of the faces is a constant, and `test_font_face` checks each face against the OS/2 table of its file. `find_font_face(family, weight, italic)` finds a face by the font matching of CSS: the slant first, then the nearest weight, with the family matched with no regard to case. `get_font_families()` names the bundled families, and `get_font_weights(family)` the weights of the faces of a family.

`compute_font_path(font)` is the file that draws a font: the file of the face that `find_font_face` finds, or of DejaVu Sans when no bundled face has the family. The measure, the backends and the caches of fonts key on this path, and `font_file` resolves it where a file is opened. It allocates nothing.

### Measurement without a display

A [`TextMeasure`](../../../../source/platform/style/TextMeasure.jl) answers what a layout needs to place text, with no display: the box of a string, the metrics of a font with no text, and the x of each character boundary of a string.

- `measure_string(measure, text, font) -> StringBox` is the box of `text` set in `font`: its advance `width`, kerning included, and the largest `ascent`, `descent` and `line_gap` of the fonts that draw its glyphs. The baseline of the string is `ascent` below the top of the box.
- `get_font_metrics(measure, font) -> FontMetrics` is the vertical metrics of `font` with no text: the `ascent`, the `descent` and the `line_gap`.
- `compute_caret_offsets(measure, text, font) -> Vector{Float64}` is the pen position before each character of `text`, `length(text) + 1` values. Each is the pen position where the next character starts, so the caret after "A" in "AV" stands where "V" starts, past the kerning of the pair.

Every value is a real number in logical pixels; a `TextMeasure` rounds nothing. `compute_text_extent(measure, text, font) -> (width, ascent, descent)` rounds the box of `measure_string` to whole logical pixels: the width rounded, and the ascent and the descent rounded up, so the box never ends inside the ink. With no `measure`, it answers the box that a `GraphicsText` draws, from the font files.

`FontFileMeasure()` reads the font files, as every backend draws them: the `hmtx` advance of each glyph, the `kern` pairs between two glyphs of one font, the fallback font of a character the font lacks, and the vertical metrics by FreeType's rule. It is the measure of the application and the exports, and the PDF and web backends use it. `FixedMeasure(advance, ascent, descent, line_gap; fonts = Dict())` answers fixed numbers for a test: every character is `advance` wide, there is no kerning, and every font has the given metrics, except a font that `fonts` gives its own `FontMetrics`.

A font does not carry every glyph. `find_glyph_font_file(font, character)` finds the file that has a glyph: the face of the font, then the faces of `get_fallback_font_files(font)`. These are DejaVu Sans Mono and then Noto Emoji, each at the weight of the font and then regular, and always upright. `FontFileMeasure` measures each character in the font that draws it. The variation selectors U+FE0E and U+FE0F measure as zero width, because the SDL renderer does no shaping.

### Line spacing

A [`LineSpacing`](../../../../source/platform/style/LineSpacing.jl) sets the distance between the lines of a text, as a word processor sets it. The natural distance of a line is the sum of the largest ascent, descent and line gap of its boxes.

- `SingleSpacing()` sets the lines at their natural distance.
- `MultipleSpacing(factor)` sets the lines at `factor` times their natural distance.
- `ExactSpacing(distance)` sets the lines `distance` logical pixels apart, whatever their fonts.
- `AtLeastSpacing(distance)` sets the lines `distance` logical pixels apart, or at their natural distance when that is larger.

`compute_line_box(measure, text, font; spacing = SingleSpacing())` gives the box of a line that holds one text alone, as a label or a title does: a [`LineBox`](../../../../source/platform/style/LineSpacing.jl) with the width, the height, the baseline and the `y` of the text in the box. The baseline sits half of the leading below the top of the box, then the ascent, and never higher than the rounded ascent of the text, so the ink never rises above the box.

**Example.** Ubuntu 20 has an ascent of 18.64, a descent of 3.78 and a line gap of 0.56 logical pixels, so its natural distance is 22.98. `compute_line_box(FontFileMeasure(), "delay", StyleFont("Ubuntu", 20))` at `SingleSpacing()` gives a line box 23 pixels high, with the baseline 19 pixels below its top: half of the line gap, 0.28, and the ascent, rounded.

### Themes and the appearance

A **theme** is a document that holds the fonts, the colors and the sizes that the
projections of one domain draw with. `@theme struct JsonTheme … end` declares it,
with a default for each field, so `JsonTheme()` is the default theme. The type of a
field says which scale applies to it:

| Type of the field | Scale |
| --- | --- |
| `StyleFont`, and the font of a `StyleText` | font scale |
| `FontRole`, and the font of a `TextRole` | font scale, after the role takes its base |
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

**Base fonts and roles.** A theme holds its fonts as base fonts and roles. A base
font is a `StyleFont` field, usually `font`, and `code_font` in a theme that draws
both prose and code. Every other font of the theme is a role over a base: a
[`FontRole`](../../../../source/platform/style/FontRole.jl) names the field of its
base, and sets only what differs from it: a family, a weight, a slant, and a size
relative to the base. A `TextRole` is a font role and a color.

```julia
@theme struct JsonTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The key of an object member, with its quotes."
    key_text::TextRole = TextRole(color_solarized_blue)
    "The brackets of an array and the braces of an object."
    delimiter_text::TextRole = TextRole(color_solarized_gray; weight = 700)
end
```

The scaled theme holds the `StyleFont` or the `StyleText` that each role gives:
`apply_font_role(role, base)`, then the font scale. Its cell reads the base font,
so a person who changes the family or the size of the base changes every role of
the theme, and a heading of `relative_size = 1.8` stays 1.8 times the body. A
role field can also hold a `StyleFont` or a `StyleText` as it is, which scales as
before; the appearance tab and an appearance file accept both forms.

A string before a field is the docstring of the field, as in a plain struct, and
it says what the value draws. `@theme` keeps the docstrings in
`get_theme_field_texts(JsonTheme)`, so they need no docstring of the type, and
`find_theme_field_text(JsonTheme, :key_text)` reads one; the appearance tab shows
it under the name of the field. The first paragraph of the docstring of the theme
type is for a person: it says what the values change, and the appearance tab shows
it at the top of the card of the theme (`compute_docstring_summary` of the kernel
tool layer). `get_theme_presets(T)` names the presets
of a theme type, which the tab offers; a type has none unless it adds a method.

`@theme` also declares the **scaled theme**, `ScaledJsonTheme`: for each field, a
computed cell that holds the value of the theme times its scale. The cell follows a
change of the field and of the scale. A builder gives the styles of the scaled
theme to a projection; a person edits the theme. A scaled theme also keeps the
appearance whose scales it follows (`get_theme_appearance`). A projection never
reads it: every length that a projection draws is a value of its theme, of a kind
that a scale scales.

An **`Appearance`** holds what a person sets about the look of one editor: the
`zoom`, the six scales (`font_scale`, `icon_scale`, `spacing_scale`, `control_scale`,
`radius_scale`, `line_scale`), and for each domain its theme and its scaled theme,
found by the type that the declaration names (`get_theme_type`).
`get_scaled_theme!(appearance, JsonTheme)` answers the scaled theme, and makes and
stores the default theme at the first request; a projection calls it while it is
built, never while it prints. `set_theme!(appearance, theme)` puts another theme in
place, such as a preset. `make_scaled_theme(theme)` scales a theme with no
appearance, at a scale of 1.

**A projection holds its styles, and its builder fills them.** A projection
declared `@projection UntrackedCell struct` holds one field for each value that it
draws, and no theme. Nothing in a projection scales, or asks whether a theme is
scaled. `@theme struct JsonTheme` writes and exports `get_json_style(theme, name)`
(the name of the type without `Theme`, in snake case): with a theme of the type,
scaled or not, a cell that reads the value of the field `name` at each read with
no edge (`make_theme_cell`); with `nothing`, the plain value of the default theme
(`get_theme_defaults`, made once for each theme type). A style field defaults to
`get_json_style(nothing, :role)`, and a builder gives the styles:

- a factory of the domain, such as `JsonToSyntax(; theme, syntax_theme)`, which
  passes each projection the styles of its roles;
- an outer keyword constructor that takes `theme`, beside a struct with no theme
  field, such as the second constructor of a widget printer;
- `make_<name>_projection(; theme)`, for a projection that has no factory, such
  as `make_message_log_projection`.

Only a builder that holds an `Appearance` calls `get_scaled_theme!`. A user
interface with no scales passes a theme as it is, and it draws at no scale:
`get_theme_value(theme, name)` gives the value of one field of a theme, scaled or
not, a length as its number and a role as the font or the text it gives, and
`get_theme_values(theme)` gives them all by name. So a projection that a printer
builds at each print makes no theme, and a view shows a change of a theme when
the `appearance` wrapper prints it again. A plain struct holds a style in an `Any`
field and reads it with `unwrap_cell`. `make_theme_values_field(K, theme)` gives
all the values of a theme as one `NamedTuple` field, for a printer that reads many
of them, such as a chart.

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
style = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_blue)
faint = StyleColor(0.0, 0.0, 0.0, 0.25)
width, ascent, descent = compute_text_extent("hello", StyleFont("Ubuntu Mono", 20))
font_logical_size(StyleFont("Ubuntu Mono", 20))   # 20, the font's own size
```

- Test: no package suite exists. `test_font_metrics()`, `test_font_fallback()` and `test_affine_transform()` in `test/platform/document/` cover the parser and the geometry; `test_text_measure()` and `test_line_spacing()`, in the same folder, cover the measure contract and the line spacing.

## Limits

- No backend draws a dashed line. A `dash` value in a `StyleStroke` gives a solid line.
- The check whether a font file exists runs once for each path. A font file that appears later is not found.
