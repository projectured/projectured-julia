# Style

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [macros.md](../../kernel/macros.md), [graphics.md](../graphics/graphics.md)

The style slice of `ProjecturedPlatform` holds the values that everything drawn shares: colours, fonts, styled text, strokes, geometry and images. It also holds a TrueType parser that measures text with no display. It has no projection and registers nothing; this document says why its types have the form they have.

## How it works

| Type | What it is |
| --- | --- |
| `StyleColor` | `red`, `green`, `blue`, `alpha`, each a `Float64` from 0 to 1 |
| `StyleFont` | a family, a size in logical pixels, a weight and a slant |
| `StyleText` | a `StyleFont` and a `StyleColor`, the pair that every text needs |
| `StyleStroke` | a colour, a width and a `dash` |
| `Inset`, `Point2D`, `AffineTransform` | a box of margins, a point, a 2D transform with `∘` |
| `ImageMemory` | an image from memory |
| `Image` | the picture that a file holds: its path, and pixels that a task reads after the frame that paints them |
| `ImageFile` | the file document of a picture file: `content` is its `Image` |

The package also defines about 80 colour constants, in curated ramps: `color_black`, `color_solarized_blue`, the Tailwind `color_zinc_*`, `color_slate_*` and `color_indigo_*` ramps. These are fixed colours for a document or a theme field that no colour setting follows; the palette that a role or a step of a ramp draws from is a separate set of ramps, under ["Colours"](#colours) below. A font has no constants: a font is a description, and a theme or a document writes it where it is used.

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
| `FontRole`, and the font of a `TextRole` | font scale, after the role takes its font from the font theme |
| `StyleStroke`, its width | line scale |
| `Spacing` | spacing scale |
| `Radius` | radius scale |
| `LineWidth` | line scale |
| `ControlSize` | control scale |
| `IconSize` | icon scale |

The five types of length wrap a number, an `Inset` or a `Point2D` in logical pixels.
Any other value, such as a color, takes no scale. The declared type decides the
kind: a write of a bare number into a field declared `Radius` converts it to a
`Radius`, by the conversion of the check of declared types, and
`convert_theme_value` gives the kind to a bare number that a field holds with the
check off, so it scales as a radius. `scale_length` multiplies a length
and keeps a length above 0 at least 1, so a line or a gap never disappears.

**Font roles.** A font field of a theme names a role of the font theme, as a
colour field names a role of the colour theme. The
[`FontTheme`](../../../../source/platform/style/FontTheme.jl) holds the roles: two
families, `sans_family` and `mono_family`, and one `FontStep` for each role, which
gives a kind of family (`:sans` or `:mono`), a size, a weight and a slant. The
appearance holds one font theme for every colour mode, and `get_font_theme(appearance)`
gives it. A [`FontRole`](../../../../source/platform/style/FontRole.jl) names a role,
and can set its own weight and slant over those of the step: `FontRole(:quiet)`,
`FontRole(:document_code; weight = 700)`. A `TextRole` is a font role and a colour.
[type-rules.md](../../../rule/type-rules.md) says which text takes which role.

```julia
@theme struct JsonTheme
    "The key of an object member, with its quotes."
    key_text::ThemeText = TextRole(:field; font_role = :document_code)
    "The brackets of an array and the braces of an object."
    delimiter_text::ThemeText = TextRole(:punctuation; font_role = :document_code, weight = 700)
end
```

`TextRole(:field; font_role = :document_code)` is
`TextRole(ColorRole(:field); font_role = :document_code)`: the colour of the role
`field` of the colour theme, under ["Colours"](#colours) below, and the font of
the role `document_code`. With no `font_role`, the font is the role `text`. A field
of a theme can also hold a fixed colour, such as a constant of
[Color.jl](../../../../source/platform/style/Color.jl), for a colour that no colour
setting changes.

The scaled theme holds the `StyleFont` or the `StyleText` that each role gives.
`resolve_font_role(role, appearance)` takes the family, the size, the weight and the
slant from the font theme, and puts the weight and the slant of the field over
them. The font scale then multiplies the size, and the size rounds once. The cell
reads the font theme, so a change of a step or of a family in the appearance tab
changes every text that names that role. A role never changes its size.

A field that needs another size or another family holds an exact `StyleFont`,
which takes only the font scale. An icon in Lucide is such a text:
`TextRole(:warning_text; font = StyleFont("Lucide", 13))` keeps the font and takes
the colour from the role. The appearance tab and an appearance file accept both
forms. So a field that holds a text declares the union `ThemeText`, a `StyleText`
or a `TextRole`, a field that holds a font declares `ThemeFont`, a `StyleFont` or a
`FontRole`, and a colour field declares `ThemeColor`. The check of declared types
then admits both forms.

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

An **`Appearance`** holds what a person sets about the look of one editor: its
`scale`, an `AppearanceScale` with the `zoom` and the six scales (`font_scale`,
`icon_scale`, `spacing_scale`, `control_scale`, `radius_scale`, `line_scale`), its
`colors`, an `AppearanceColors` with the five colour settings and the colours of the
system, and for each domain its theme and its scaled theme, found by the type that
the declaration names (`get_theme_type`). Three `ThemeGroup` documents,
`editor_themes`, `tool_themes` and `document_themes`, hold the themes under the
headings of the appearance tab, "Editor", "Tools" and "Documents"; `set_theme!`
puts each theme into its heading at the place that `get_theme_place(T)` gives, a
heading and a rank. The default places a theme of `ProjecturedPlatform` under
"Tools" and any other under "Documents"; the appearance slice places the six themes
that every view draws with under "Editor". The heading "Editor" holds the font
theme first, and its `color_theme` is a computed cell: the colour theme of the
present mode and contrast. The keyword default of `editor_themes` makes it from the
fields before it, `colors` and `color_themes`, so it follows the colour settings
and the colours of the system. Each part and each heading is a document, so a tree
shows them as nodes and a reference names them.
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

### Colours

A colour field of a theme holds a fixed colour, a step of a palette, or a role
of the colour theme. The three kinds scale together: a `PaletteColor` and a
`ColorRole` follow the colour settings of the appearance, in the same way that
a `Spacing` follows the spacing scale.

**The palette.** A [`Palette`](../../../../source/platform/style/Palette.jl) gives a
ramp of 12 colours for each of nine hues, `:neutral` and the eight accents
`:red`, `:orange`, `:amber`, `:green`, `:teal`, `:blue`, `:violet` and `:pink`
([`PALETTE_HUES`](../../../../source/platform/style/Palette.jl)), in a light mode and
in a dark mode. Every palette gives the same hues at the same steps, and each
step has one purpose:

| Step | Purpose |
| --- | --- |
| 1 | the background of a window |
| 2 | a raised or a sunken surface |
| 3–5 | the fill of a part: at rest, under the pointer, pressed or chosen |
| 6–8 | a faint line, a line, a strong line |
| 9–10 | a solid fill, and the same under the pointer |
| 11 | a text of low contrast, and a token |
| 12 | a text of high contrast |

`register_palette!(palette)` puts a palette into the registry under its name;
`find_palette(name)` finds one, and `get_palette_names()` lists every name.
`DEFAULT_PALETTE_NAME` is `"radix"`:
[RadixPalette.jl](../../../../source/platform/style/RadixPalette.jl) holds the data of
Radix Colors, six neutral ramps (slate, gray, mauve, sage, olive and sand, slate
first) and the eight accent ramps, where the hue `:blue` is the Radix scale
`indigo`. These ramps are a set apart from the constants of
[Color.jl](../../../../source/platform/style/Color.jl): a theme field that names a
step of a ramp draws from the palette of the appearance, never from a constant.

**The three kinds of colour.** The union
[`ThemeColor`](../../../../source/platform/style/ThemeColor.jl) is:

- a `StyleColor`, a fixed colour that no setting changes;
- `PaletteColor(hue, step; alpha = 1, minimum_contrast = 0, against = nothing)`,
  a step of a ramp of the palette, where `:accent` as the hue names the hue of
  the accent of the appearance. With a `minimum_contrast` above 0, a step that
  falls short moves along its own ramp toward the end with more contrast, just
  far enough to reach that ratio against `against`, or against the background
  steps of the neutral ramp when `against` is `nothing`;
- `ColorRole(role; alpha = 1)`, a role of the colour theme, such as
  `ColorRole(:keyword)`.

`format_theme_color(color)` gives the text that a person reads for any of the
three: `#rrggbbaa` for a fixed colour, `"blue 11"` for a step, and `"@keyword"`
for a role, each with the alpha in percent when it is below 1.

**The colour theme and its roles.**
[`ColorTheme`](../../../../source/platform/style/ColorTheme.jl) is the theme whose 63
fields are the roles: what a colour does, such as `background`, `text_muted`,
`accent` or `keyword`. `@theme` declares it, with a default step of a ramp for
each role, so `ColorTheme()` is the default colour theme, and the appearance
holds one `ColorTheme` for each pair of a mode and a contrast. The roles are
in eleven groups:

| Group | Example roles |
| --- | --- |
| Surfaces | `background`, `surface`, `surface_sunken`, `surface_inverse` |
| Texts | `text`, `text_muted`, `text_faint`, `text_on_accent` |
| Lines | `border`, `border_strong`, `grid` |
| Accent | `accent`, `accent_text`, `accent_tint`, `focus_ring` |
| The layers of a state | `hover`, `pressed`, `selection_band`, `selection_ring`, `caret` |
| Status | `error_fill`, `error_text`, `warning_text`, `success_text`, `info_text` |
| Tokens | `keyword`, `link`, `operator`, `punctuation`, `comment`, `markup`, `heading` |
| The names of the tokens | `function_name`, `macro_name`, `event`, `field`, `type_name`, `type_parameter`, `module_name`, `variable`, `parameter`, `enum_member`, `tag` |
| The values of the tokens | `string_literal`, `character_literal`, `number_literal`, `boolean_literal`, `null_literal`, `symbol_literal`, `constant` |
| The series of a chart | `series_1` … `series_8` |
| Overlays | `shadow`, `scrim` |

Each kind of value has a role of its own, and every view that prints a value
names the role of its kind: a number in JSON, in Julia, in SQL and in a cell of
a data frame has the color of `number_literal`. Two roles name another role by
default: `character_literal` takes the color of `string_literal`, and
`null_literal` the color of `boolean_literal`. The role `constant` colors a
named constant that is no literal, such as a constant of mathematics.

Each kind of name has a role of its own too, and a view names the role of the
kind that the place of a name gives: a column of SQL and a field after a dot in
Julia are a `field`, a table and a type are a `type_name`. A name at its
definition takes the role of its kind, and the field of its view theme makes it
bold. Many kinds fall back to a role by default, because the palette has nine
hues: `macro_name` and `event` take the colour of `function_name`,
`type_parameter` and `module_name` that of `type_name`, `parameter` that of
`variable`, `enum_member` that of `symbol_literal`, and `tag` that of `keyword`.

Almost every field holds a `PaletteColor`; a few hold a fixed colour instead,
such as `text_on_accent = color_white` and the overlays `shadow` and `scrim`.
A field of every theme other than `ColorTheme` names a role with a `ColorRole`,
so it follows the colour settings: `key_text::ThemeText = TextRole(:field; font_role = :document_code)` of
`JsonTheme` draws with the colour that the role `field` gives,
`PaletteColor(:blue, 11; minimum_contrast = 4.5)` by default, which resolves to
step 11 of the blue ramp of the palette of the appearance, in its mode — Radix
indigo by default — or a step closer to the end of the ramp with more
contrast, where step 11 itself falls short of 4.5:1. A person can also
fine-tune a role of
`ColorTheme` itself to a `ColorRole`, so that it takes the colour of another
role; `resolve_theme_color` follows such a chain up to 8 steps deep, and
raises an `ArgumentError` on a cycle.

A `@theme` declaration and a preset of a theme hold no fixed palette colour and
no colour written as numbers, except `ColorTheme.jl` itself, which is the one
place that maps a role to a step of the palette; `test_style()` checks every
other file of `source/` for one (see
[testing-guide.md](../../../guide/testing-guide.md#the-style-guard)).

**The colour settings of the appearance.** Five fields of `Appearance` choose
the colours of every view:

| Field | Values |
| --- | --- |
| `color_mode` | `:system`, `:light` or `:dark` ([`COLOR_MODES`](../../../../source/platform/style/Appearance.jl)); `:system` by default |
| `color_contrast` | `:system`, `:normal` or `:high` ([`COLOR_CONTRASTS`](../../../../source/platform/style/Appearance.jl)); `:system` by default |
| `color_palette` | the name of a palette of the registry |
| `color_accent` | the hue that `:accent` names, or `:system`; `:blue` by default |
| `color_neutral` | the neutral ramp of the palette, such as slate |

**The settings of the operating system.** A setting `:system` follows the
operating system. The field `system_colors` of the appearance holds the
`SystemColors` of the system: its mode, its contrast and its accent colour. It
is a fact of the system, not a setting, so an appearance file does not save
it. `get_color_mode`, `get_color_contrast` and `get_color_accent` give the
value in use: the setting, or the value of the system for `:system`. The accent
of the system is a colour, and `get_color_accent` takes the hue of the palette
whose step 9 has the nearest OKLCH hue angle (`find_nearest_accent_hue`); a grey
accent, or none, gives blue. With no answer of a backend, as in a test or a PDF
file, the system is light and normal.

The `appearance` wrapper fills `system_colors` from
`find_system_colors(parts.backend)` before the editor exists, because the editor
makes its first print when it is made. A backend that
finds a change later reports it as a `SystemColorsChange`, which
`AppearanceManagingProjection` writes into `system_colors` as view state: the
view prints again, and the undo list does not record it. The SDL backend asks
the system again each time one of its windows gets the focus (see
[sdl.md](../../backend/sdl/sdl.md)).

`color_themes` holds one `ColorTheme` for each pair of a mode and a contrast,
four in all, by the name that `get_color_variant(mode, contrast)` gives the
pair; so a fine-tune of a role stays with the mode and the contrast where a
person made it. `get_color_theme(appearance)` answers the colour theme of the
pair in use.

**How a colour is computed, like a scaled length.** `scale_theme_value(value,
theme, appearance)` computes a `Spacing` field by the `spacing_scale` of the
appearance, and a `PaletteColor` or a `ColorRole` field by the colour settings,
in the same function. A `PaletteColor` resolves through
`compute_palette_color`, in the palette, the mode, the neutral and the accent
that the colour settings name. A `ColorRole` resolves through
`resolve_theme_color`, which reads the field of that role in
`get_color_theme(appearance)` and resolves what it finds the same way. A
`StyleColor` stays as it is, at every scale. So a change of `color_mode` from
light to dark, or of `color_palette` from Radix to another palette,
recomputes every colour of every view in one print of the whole view, as a
change of a scale recomputes every length.

An appearance file saves a fixed colour as its `#rrggbbaa` text, a role as a
table that names it, and a step of a ramp as a table of its hue and its step,
each with its alpha when it is below 1 (`save_appearance!`,
`load_appearance!`).

### A picture of a file

`Image(path)` is the picture that a file holds. Making it reads nothing and runs no work. It has eight fields: `filename`, `read_count`, `pixels`, `head_size`, `decoded_count`, `natural_size`, `failure` and `source`. All but `filename` are view state: a save writes the path only (`pred_arguments`), a load makes a picture that reads nothing, and undo records no change of them.

`pixels` is a background cell (`make_background_cell`). Its input is the path and `read_count`. The work of its `source` decodes the file with `decode_image` and answers `(bytes, width, height)`, or the exception of a file that is missing or does not decode, as a value, so a read of the cell never throws. Each `Image` makes a `BackgroundSource` of its own, so the pictures that one frame paints decode in parallel, each on a task of the default pool. The `apply` of the cell returns an `ApplyImageAnswerOperation`, which writes the size into `natural_size`, or the exception into `failure`, and writes a cell only when its value changes. The operation drops the answer of a `read_count` that a newer count follows.

`head_size` is a second background cell with the same input. Its work reads the size from the head of the file with `read_image_size`, with no decode, and answers `(width, height)`, `nothing` for a file whose head says none, or the exception of a file that can not be opened. The head cells of all pictures share one source (`_IMAGE_SIZE_SOURCE`, "the sizes of pictures"), so the sizes that one frame asks for are read on one task. `decoded_count` is the `read_count` whose decode answered, and −1 until the first decode answers. `ApplyImageAnswerOperation` has one more field, `is_pixel_answer`: for one read the decode wins over the head, a size answer for a read whose decode answered is dropped, a size answer of `nothing` writes nothing, and a size clears `failure`.

`get_image_natural_size(image)` is the call of a print for the size. It reads the head cell only while the decode of this read has not answered, so a picture whose decode answered asks for no head. A file that is missing shows its failure without a paint, and one more `read_count` reads the head again.

A print reads `failure` and `get_image_natural_size`, which are `nothing` until the first answer, and never `pixels`. A label (`_push_content!`) and a text span (`_extract_image_data`) put the pixel cell itself into the `data` of their `GraphicsImage`. `GraphicsImage` keeps a cell as it is, so only the paint of a backend reads `data`, and only that read records the demand for the task. A picture with no size measures 320 by 240 pixels, which the slot of the label fits, and a picture whose pixels have not come (`decoded_count` below 0) or with a `failure` shows a box under its pixels. One more `read_count` gives the cell a new input: it answers its last pixels until the new ones come, and the next paint asks again.

A copy of a picture (`copy_document`, with the plain policy or the policy of a copy gesture) is a new `Image` of the same path that reads nothing, as a load makes. A field-by-field copy would share the `source` and keep a pixel cell that nothing feeds. A policy that stops the copy at a document that it does not own (`is_descendable_for_copy`) gets the placeholder, as for any document.

### A picture file

`ImageFile(path)` is the file document of a picture file. It has the three fields of every file type: `filename`, `content` and `disk`. `content` is the `Image` that the file holds, and `get_edited_document` reaches it through a history. A person does not edit it (`is_editable_file_type` answers `false`), so Ctrl+S writes nothing and the decoration says "read only". `StyleModule.__init__` registers the extensions `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif`, so `read_document_file`, `make_file_tab` and the open of a file make one. `read_file_content(ImageFile, path)` answers `Image(path)` and reads no byte of the file, not even its time or its size. `ImageFile(path)` makes a new file document that no other place shares; a holder that must follow the file asks the editor for its one file document of the path with `open_file_document!`.

A change of the file is a change of every file that a person does not edit. The file counts it in its `disk`, a task reads the file when a place draws the file, the hash of the time and the size decides whether the file loads, and the load gives the new `Image` to the history. `replace_wrapped_document!(::Image, document)` keeps the old picture when the new one has the same path, adds one to its `read_count` and drops the new picture, which nothing read. So the file keeps one picture with its pixels, and the pixel cell gets a new input. A picture of another path, and the seed of a file that is gone, replace the picture. F5 does the same: for a file that a person does not edit, `ReloadFileOperation` takes the hash of the time and the size, and reads no byte of the file.

`get_shown_picture(content)` is what a holder draws for `content`: the `Image` that a picture file holds, and `content` itself for anything else. A label, a text span and the picture cell of a roster draw the picture through it. A roster cell shows a picture for a value for which it answers an `ImageDocument`, at most `table_picture_height` high in its shape, and a box 4 by 3 before the pixels come. The picture of a conversation, the image spans of Markdown, Book and RST, and the example documents make an `Image` and read no pixel on the loop.

A script with no editor reads the pixels with `wait_for_cell!(getfield(picture, :pixels); editor = nothing)`. Make a picture where a document is built, never inside a computation, because a computation that makes one makes a new pixel cell at each run. A test gives a picture a source of its own with `_make_image(path, source)`; no public maker takes a source.

### The zoom and the scales

The size of things on the screen comes from the `Appearance` of an editor: the
`zoom` and the six scales of its `scale` (`font_scale`, `icon_scale`,
`spacing_scale`, `control_scale`, `radius_scale`, `line_scale`). `AdjustZoomOperation` and
`AdjustScaleOperation`, and the keys that reach them, are bindings of the
`appearance` wrapper of `build_editor`; an editor built with no `Appearance` has
no zoom keys.

- **The zoom.** `AdjustZoomOperation` steps `appearance.scale.zoom` and copies it into
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

- Test: no package suite exists. `test_image()` covers `Image`, and `test_image_file_read()` of the SDL package reads real files. `test_font_metrics()`, `test_font_fallback()` and `test_affine_transform()` in `test/platform/document/` cover the parser and the geometry; `test_text_measure()` and `test_line_spacing()`, in the same folder, cover the measure contract and the line spacing.

## Limits

- No backend draws a dashed line. A `dash` value in a `StyleStroke` gives a solid line.
- The check whether a font file exists runs once for each path. A font file that appears later is not found.
