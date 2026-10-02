# Fragment of `FormulaModule` — the theme of a formula on the syntax rung: the
# insertion placeholder, a reference to another formula, the name and the
# chrome of a formula's own line, and its result.

"""
    FormulaTheme

The fonts and the colors of a formula: its insertion placeholder, a reference
to another formula, a name, an operator and a result.

The theme of the Formula projections. `@theme` declares it, so
`ScaledFormulaTheme` holds each value times its scale, and `FormulaTheme()` is
the default theme.

The fields are the text styles of the insertion placeholder, a reference, a
name, an operator and a result, and the plain font of an environment's lines.
Each field has a docstring that says what it draws, which the appearance tab
shows under its name.

A Formula projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FormulaTheme
    "The \"insert formula\" placeholder."
    insertion_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_gray)
    "A reference to another formula, by its current name."
    reference_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_violet)
    "The name of a formula."
    name_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_blue)
    "The `=` and the `⇒` of a formula's line."
    operator_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_gray)
    "The value of a formula."
    result_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_green)
    "The font the lines of an environment separate on."
    plain_font::StyleFont = StyleFont("Ubuntu Mono", 20)
end

# The style field of type `T` of a Formula projection that holds the field
# `name` of the theme `theme`: a `FormulaTheme`, a scaled one, or `nothing` for
# the default values.
_get_formula_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(FormulaTheme, scale_theme(theme), T; name)

# The font that a plain Formula projection field draws with: the font of
# `plain_font`, read from the scaled theme, or from the default theme with no
# theme.
function _get_formula_font(theme)
    scaled = scale_theme(theme)
    scaled === nothing ? get_theme_defaults(FormulaTheme).plain_font :
                         make_theme_cell(StyleFont, scaled, s -> s.plain_font)
end
