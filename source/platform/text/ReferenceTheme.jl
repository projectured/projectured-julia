# Fragment of `TextModule` — the theme of `ReferenceToText` and
# `ReferenceToHumanReadableText`: the font of the body, the font of the
# connector between two lines of the human-readable form, and the color of
# each kind of token.

"""
    ReferenceTheme

The theme of [`ReferenceToText`](@ref) and [`ReferenceToHumanReadableText`](@ref).
`@theme` declares it, so `ScaledReferenceTheme` holds each value times its
scale, and `ReferenceTheme()` is the default theme.

- `font` — the body of both forms.
- `aside_font` — the italic "which is" that connects one line of the
  human-readable form to the line below it.
- `punctuation_color` — a delimiter (`.`, `[`, `]`, `{`, `}`, `::`, `<`, `>`, a
  comma, a colon) and the plain words of a phrase ("the ", " of ", "a ", "no
  selection", "∅", …).
- `name_color` — the name of a field or of a step.
- `index_color` — an element index, a position, a range bound, or a point
  coordinate.
- `type_color` — the `::Type` a step descends from, or the parent type of a
  step, when it is known.
- `projection_color` — the name of a projection.
- `unknown_color` — a step of a kind neither form knows how to describe, and a
  type that could not be found.

Both projections hold the scaled theme as one `UntrackedCell` style field, read
once at each print with `unwrap_cell`; with no theme they hold the plain values
of the default theme.
"""
@theme struct ReferenceTheme
    font::StyleFont = font_ubuntu_monospace_regular_20
    aside_font::StyleFont = font_ubuntu_monospace_italic_20
    punctuation_color::StyleColor = color_solarized_gray
    name_color::StyleColor = color_solarized_cyan
    index_color::StyleColor = color_solarized_magenta
    type_color::StyleColor = color_solarized_orange
    projection_color::StyleColor = color_solarized_yellow
    unknown_color::StyleColor = color_solarized_red
end

# The style field of `name`, of the value type `T`, of a reference projection: a
# `ReferenceTheme`, a scaled one, or `nothing` for the default values.
_get_reference_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(ReferenceTheme, scale_theme(theme), T, name)
