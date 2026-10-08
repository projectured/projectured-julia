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

The builder gives each Math projection its styles with `get_math_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme.
"""
@theme struct MathTheme
    "The font that the code of this theme follows: its family, its weight and its size."
    code_font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A variable."
    variable_text::TextRole = TextRole(:variable; base = :code_font)
    "An operator, and the `/` of a fraction."
    operator_text::TextRole = TextRole(:operator; base = :code_font)
    "A parenthesis, a brace, a bracket and the insertion leaf."
    chrome_text::TextRole = TextRole(:punctuation; base = :code_font)
    "A symbol."
    symbol_text::TextRole = TextRole(:constant; base = :code_font)
    "The name of a function, a radical, a big operator, a differential, a derivative, an accent, a matrix or a case list."
    name_text::TextRole = TextRole(:function_name; base = :code_font)
    "A run of plain text."
    word_text::TextRole = TextRole(:text; base = :code_font)
    "The `=` of an assignment."
    equals_text::TextRole = TextRole(:operator; base = :code_font)
    "The upright face: a number, an operator, a function name, a symbol."
    font::StyleFont = StyleFont("DejaVu Sans", 14)
    "The oblique face: a variable."
    slanted_font::FontRole = FontRole(italic = true)
    "The color of every part."
    ink::StyleColor = ColorRole(:text)
    "The color of an empty slot."
    hint::StyleColor = ColorRole(:text_faint)
    "The color that washes a selected box."
    selection_wash::StyleColor = ColorRole(:selection_band)
end
