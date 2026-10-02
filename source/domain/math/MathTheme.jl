# Fragment of `MathModule` — the theme of a formula: the text of the linear
# form, and the font, the ink and the selection wash of the typeset form.

"""
    MathTheme

The fonts and the colors of a formula, in its typed form and in its typeset
form: a variable, an operator and a symbol.

The theme of the Math projections. `@theme` declares it, so `ScaledMathTheme`
holds each value times its scale, and `MathTheme()` is the default theme.

The fields are in two groups: the text styles of the linear form
(`MathToSyntax`), and the fonts and the colors of the typeset form
(`MathConfig`). Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

A Math projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct MathTheme
    "A variable."
    variable_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    "An operator, and the `/` of a fraction."
    operator_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
    "A parenthesis, a brace, a bracket and the insertion leaf."
    chrome_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    "A symbol."
    symbol_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
    "The name of a function, a radical, a big operator, a differential, a derivative, an accent, a matrix or a case list."
    name_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    "A run of plain text."
    word_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_default)
    "The `=` of an assignment."
    equals_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    "The upright face: a number, an operator, a function name, a symbol."
    font::StyleFont = font_dejavu_sans_regular_20
    "The oblique face: a variable."
    slanted_font::StyleFont = font_dejavu_sans_italic_20
    "The color of every part."
    ink::StyleColor = color_default
    "The color of an empty slot."
    hint::StyleColor = color_solarized_gray
    "The color that washes a selected box."
    selection_wash::StyleColor = StyleColor(0.15, 0.39, 0.68, 0.22)
end

# The style field of type `T` of a Math projection that holds the field `name`
# of the theme `theme`: a `MathTheme`, a scaled one, or `nothing` for the
# default values.
_get_math_style(theme, ::Type{T}, name::Symbol) where {T} =
    make_style_field(MathTheme, scale_theme(theme), T; name)
