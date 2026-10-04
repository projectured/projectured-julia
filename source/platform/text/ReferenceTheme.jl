# Fragment of `TextModule` — the theme of `ReferenceToText` and
# `ReferenceToHumanReadableText`: the font of the body, the font of the
# connector between two lines of the human-readable form, and the color of
# each kind of token.

"""
    ReferenceTheme

The font and the colors of a reference shown as text, in the reference tab and
in the selection tab. A name, an index, a type and other kinds of word each
take their own color.

The theme of [`ReferenceToText`](@ref) and [`ReferenceToHumanReadableText`](@ref).
`@theme` declares it, so `ScaledReferenceTheme` holds each value times its
scale, and `ReferenceTheme()` is the default theme.

The fields are the fonts of the body and the connector, and the colors of
each kind of token. Each field has a docstring that says what it draws,
which the appearance tab shows under its name.

Both projections hold the scaled theme as one `UntrackedCell` style field, read
once at each print with `unwrap_cell`; with no theme they hold the plain values
of the default theme.
"""
@theme struct ReferenceTheme
    "The body of both forms."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The italic \"which is\" that connects one line of the human-readable form to the line below it."
    aside_font::FontRole = FontRole(italic = true)
    "A delimiter, a comma or a colon, and the plain words of a phrase, such as \"the \" or \"of \"."
    punctuation_color::StyleColor = color_solarized_gray
    "The name of a field or of a step."
    name_color::StyleColor = color_solarized_cyan
    "An element index, a position, a range bound, or a point coordinate."
    index_color::StyleColor = color_solarized_magenta
    "The type that a step descends from, or the parent type of a step, when it is known."
    type_color::StyleColor = color_solarized_orange
    "The name of a projection."
    projection_color::StyleColor = color_solarized_yellow
    "A step of a kind neither form describes, and a type that is not found."
    unknown_color::StyleColor = color_solarized_red
end
