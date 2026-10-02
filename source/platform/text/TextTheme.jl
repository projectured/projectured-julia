# Fragment of `TextModule` — the theme of the text: the caret, the selection and
# the text that the text projections style on their own.

"""
    TextTheme

The theme of the text projections. `@theme` declares it, so `ScaledTextTheme`
holds each value times its scale, and `TextTheme()` is the default theme.

The fields are the font of unstyled text, the caret, the highlight, and the
text styles of a boolean, a number and a string. Each field has a docstring
that says what it draws, which the appearance tab shows as its tooltip.

A text projection reads the scaled theme through its `UntrackedCell` style
fields. The fonts and the colors of a text document stay as its author set them.
`TextHighlighting`, `SelectionInverting` and `TextLineNumbering` take their
colors and fonts as keywords: no view of the platform builds them.
"""
@theme struct TextTheme
    "The font of a text that no document styles, such as the line of a placeholder."
    font::StyleFont = font_ubuntu_monospace_regular_20
    "The caret of the text that holds the keyboard."
    caret::StyleColor = color_black
    "The caret of a text that keeps its place while another holds the keyboard."
    dormant_caret::StyleColor = StyleColor(0.55, 0.55, 0.55, 1.0)
    "The width of a caret."
    caret_width::LineWidth = LineWidth(2)
    "The band under the selected text, while its text holds the keyboard."
    highlight::StyleColor = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x40 / 255)
    "The band under the selected text, while another text holds the keyboard."
    dormant_highlight::StyleColor = StyleColor(0x88 / 255, 0x88 / 255, 0x88 / 255, 0x28 / 255)
    "The radius of the corners of the band under the selected text."
    highlight_radius::Radius = Radius(4)
    "A boolean that a primitive projection prints as text."
    bool_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "A number that a primitive projection prints as text."
    number_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    "A string that a primitive projection prints as text."
    string_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

# The style field of type `T` of a text projection that holds the field `name` of
# the text theme: `make_style_field` of `TextTheme`.
_get_text_style(theme, ::Type{T}, name::Symbol) where {T} = make_style_field(TextTheme, theme, T, name)
