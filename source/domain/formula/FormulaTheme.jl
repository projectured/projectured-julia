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

The builder gives each Formula projection its styles with `get_formula_style`,
from a theme scaled or not; a projection built with no styles holds the plain
values of the default theme.
"""
@theme struct FormulaTheme
    "The \"insert formula\" placeholder."
    insertion_text::TextRole = TextRole(color_solarized_gray; base = :plain_font)
    "A reference to another formula, by its current name."
    reference_text::TextRole = TextRole(color_solarized_violet; base = :plain_font, weight = 700)
    "The name of a formula."
    name_text::TextRole = TextRole(color_solarized_blue; base = :plain_font, weight = 700)
    "The `=` and the `⇒` of a formula's line."
    operator_text::TextRole = TextRole(color_solarized_gray; base = :plain_font)
    "The value of a formula."
    result_text::TextRole = TextRole(color_solarized_green; base = :plain_font)
    "The font the lines of an environment separate on."
    plain_font::StyleFont = StyleFont("Ubuntu Mono", 14)
end

# The font that a plain Formula projection field draws with: the font of
# `plain_font` in the theme `theme`, scaled or not.
function _get_formula_font(theme)
    theme === nothing && return get_theme_defaults(FormulaTheme).plain_font
    make_theme_cell(StyleFont, theme, values -> values.plain_font)
end
