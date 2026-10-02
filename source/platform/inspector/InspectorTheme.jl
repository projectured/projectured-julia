# Fragment of `InspectorModule` — the theme of the reference inspector and the
# selection inspector: the font of the body, and the font and the color of a
# section header.

"""
    InspectorTheme

The theme of [`ReferenceInspectorToText`](@ref) and
[`SelectionInspectorToText`](@ref). `@theme` declares it, so
`ScaledInspectorTheme` holds each value times its scale, and
`InspectorTheme()` is the default theme.

- `font` — the body: the compact reference and the human-readable narrative.
- `header_font` and `header_color` — the "Compact" and "Human-readable" section
  headers.

An inspector reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct InspectorTheme
    font::StyleFont = font_ubuntu_monospace_regular_20
    header_font::StyleFont = font_liberation_sans_bold_30
    header_color::StyleColor = color_solarized_blue
end

# The style field of an inspector projection that holds the field `name` of the
# theme `theme`, of the value type `T`: an `InspectorTheme`, a scaled one, or
# `nothing` for the default values.
_get_inspector_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(InspectorTheme, scale_theme(theme), T, name)
