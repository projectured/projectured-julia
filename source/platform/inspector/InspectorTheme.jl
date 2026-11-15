# Fragment of `InspectorModule` — the theme of the reference inspector and the
# selection inspector: the font and the color of a section header.

"""
    InspectorTheme

The font and the color of the section headers of the Reference tab and the
Selection tab. The text of a reference under a header takes the fonts and the
colors of [`ReferenceTheme`](@ref).

The theme of [`ReferenceInspectorToText`](@ref) and
[`SelectionInspectorToText`](@ref). `@theme` declares it, so
`ScaledInspectorTheme` holds each value times its scale, and
`InspectorTheme()` is the default theme.

The fields are the font and the color of a section header. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

An inspector holds its styles and no theme; its builder gives them with `get_inspector_style`,
from a theme scaled or not, and with no theme it holds the plain values of the
default theme.
"""
@theme struct InspectorTheme
    "The \"Compact\" and \"Human-readable\" section headers."
    header_font::ThemeFont = FontRole(:title)
    "The \"Compact\" and \"Human-readable\" section headers."
    header_color::ThemeColor = ColorRole(:heading)
end

