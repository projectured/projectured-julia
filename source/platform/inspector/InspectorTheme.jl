# Fragment of `InspectorModule` — the theme of the reference inspector and the
# selection inspector: the font of the body, and the font and the color of a
# section header.

"""
    InspectorTheme

The font and the colors of the Reference tab and the Selection tab: the body
text and the section headers.

The theme of [`ReferenceInspectorToText`](@ref) and
[`SelectionInspectorToText`](@ref). `@theme` declares it, so
`ScaledInspectorTheme` holds each value times its scale, and
`InspectorTheme()` is the default theme.

The fields are the font of the body, and the font and the color of a section
header. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

An inspector holds its styles and no theme; its builder gives them with `get_inspector_style`,
from a theme scaled or not, and with no theme it holds the plain values of the
default theme.
"""
@theme struct InspectorTheme
    "The body: the compact reference and the human-readable narrative."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The \"Compact\" and \"Human-readable\" section headers."
    header_font::FontRole = FontRole(family = "Liberation Sans", weight = 700, relative_size = 1.5)
    "The \"Compact\" and \"Human-readable\" section headers."
    header_color::StyleColor = ColorRole(:heading)
end

