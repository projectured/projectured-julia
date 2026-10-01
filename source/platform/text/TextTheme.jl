# Fragment of `TextModule` — the theme of the text: the caret, the selection and
# the text that the text projections style on their own.

"""
    TextTheme

The theme of the text projections. `@theme` declares it, so `ScaledTextTheme`
holds each value times its scale, and `TextTheme()` is the default theme.

- `font` — the font of a text that no document styles, such as the line of a
  placeholder.
- `caret`, `dormant_caret` and `caret_width` — the caret of the text that holds
  the keyboard, the caret of a text that keeps its place while another holds the
  keyboard, and its width.
- `highlight`, `dormant_highlight` and `highlight_radius` — the band under the
  selected text, live and dormant, and the radius of its corners.
- `bool_text`, `number_text` and `string_text` — a boolean, a number and a string
  that the primitive projections print as text.

A text projection reads the scaled theme through its `UntrackedCell` style
fields. The fonts and the colors of a text document stay as its author set them.
`TextHighlighting`, `SelectionInverting` and `TextLineNumbering` take their
colors and fonts as keywords: no view of the platform builds them.
"""
@theme struct TextTheme
    font::StyleFont = font_ubuntu_monospace_regular_20
    caret::StyleColor = color_black
    dormant_caret::StyleColor = StyleColor(0.55, 0.55, 0.55, 1.0)
    caret_width::LineWidth = LineWidth(2)
    highlight::StyleColor = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x40 / 255)
    dormant_highlight::StyleColor = StyleColor(0x88 / 255, 0x88 / 255, 0x88 / 255, 0x28 / 255)
    highlight_radius::Radius = Radius(4)
    bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    number_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    string_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

# The style field of type `T` of a text projection that holds the field `name` of
# the text theme: `make_style_field` of `TextTheme`.
_get_text_style(theme, ::Type{T}, name::Symbol) where {T} = make_style_field(TextTheme, theme, T, name)
