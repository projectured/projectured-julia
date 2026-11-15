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
    "A variable."
    variable_text::ThemeText = TextRole(:variable; font_role = :document_code)
    "An operator, and the `/` of a fraction."
    operator_text::ThemeText = TextRole(:operator; font_role = :document_code)
    "A parenthesis, a brace, a bracket and the insertion leaf."
    chrome_text::ThemeText = TextRole(:punctuation; font_role = :document_code)
    "A symbol."
    symbol_text::ThemeText = TextRole(:constant; font_role = :document_code)
    "The name of a function, a radical, a big operator, a differential, a derivative, an accent, a matrix or a case list."
    name_text::ThemeText = TextRole(:function_name; font_role = :document_code)
    "A run of plain text."
    word_text::ThemeText = TextRole(:text; font_role = :document_code)
    "The `=` of an assignment."
    equals_text::ThemeText = TextRole(:operator; font_role = :document_code)
    "The upright face: a number, an operator, a function name, a symbol."
    font::ThemeFont = FontRole(:document_text)
    "The oblique face: a variable."
    slanted_font::ThemeFont = FontRole(:document_text; italic = true)
    "The color of every part."
    ink::ThemeColor = ColorRole(:text)
    "The color of an empty slot."
    hint::ThemeColor = ColorRole(:text_faint)
    "The color that washes a selected box."
    selection_wash::ThemeColor = ColorRole(:selection_band)
end
