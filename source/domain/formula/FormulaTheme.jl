# Fragment of `FormulaModule` — the theme of a formula on the syntax rung: the
# insertion placeholder, a reference to another formula, the name and the
# chrome of a formula's own line, and its result.

"""
    FormulaTheme

The theme of the Formula projections. `@theme` declares it, so
`ScaledFormulaTheme` holds each value times its scale, and `FormulaTheme()` is
the default theme.

- `insertion_text` — the "insert formula" placeholder.
- `reference_text` — a reference to another formula, by its current name.
- `name_text` — the name of a formula.
- `operator_text` — the `=` and the `⇒` of a formula's line.
- `result_text` — the value of a formula.
- `plain_font` — the font the lines of an environment separate on.

A Formula projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FormulaTheme
    insertion_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    reference_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_violet)
    name_text::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    operator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    result_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    plain_font::StyleFont = font_ubuntu_monospace_regular_20
end

# The style field of type `T` of a Formula projection that holds the field
# `name` of the theme `theme`: a `FormulaTheme`, a scaled one, or `nothing` for
# the default values.
_get_formula_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(FormulaTheme, scale_theme(theme), T, name)

# The font that a plain Formula projection field draws with: the font of
# `plain_font`, read from the scaled theme, or from the default theme with no
# theme.
function _get_formula_font(theme)
    scaled = scale_theme(theme)
    scaled === nothing ? get_theme_defaults(FormulaTheme).plain_font :
                         make_theme_cell(StyleFont, scaled, s -> s.plain_font)
end
