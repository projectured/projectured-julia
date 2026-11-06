# Fragment of `JuliaModule` — the theme of the Julia syntax: the text of each
# kind of token, the plain and the hint text of the insertion hole, and the
# colors of its commitability.

"""
    JuliaTheme

The colors and the fonts of Julia code: a name, a value, a keyword, an
operator and a called function.

The theme of the Julia projections. `@theme` declares it, so `ScaledJuliaTheme`
holds each value times its scale, and `JuliaTheme()` is the default theme.

The fields are the text styles of the tokens of the Julia syntax, and the
colors of the typed text of the insertion hole by its commitability. Each
field has a docstring that says what it draws, which the appearance tab shows
under its name.

The builder gives each Julia projection its styles with `get_julia_style`,
from a theme scaled or not; a projection built with no styles holds the plain
values of the default theme.
"""
@theme struct JuliaTheme
    "A variable, a name whose kind the place does not give, and the label of an object that stands in the code, such as a widget pasted into a form."
    identifier_text::ThemeText = TextRole(:variable; font_role = :document_code)
    "A string, a chunk of an interpolated string, the quotes of a string interpolation, and a docstring."
    string_text::ThemeText = TextRole(:string_literal; font_role = :document_code)
    "A character."
    char_text::ThemeText = TextRole(:character_literal; font_role = :document_code)
    "An integer and a float."
    number_text::ThemeText = TextRole(:number_literal; font_role = :document_code)
    "`true` and `false`."
    bool_text::ThemeText = TextRole(:boolean_literal; font_role = :document_code)
    "`nothing`."
    nothing_text::ThemeText = TextRole(:null_literal; font_role = :document_code)
    "A quote, a delimiter, a separator, a brace and a fence."
    punctuation_text::ThemeText = TextRole(:punctuation; font_role = :document_code)
    "A comment."
    comment_text::ThemeText = TextRole(:comment; font_role = :document_code)
    "A keyword."
    keyword_text::ThemeText = TextRole(:keyword; font_role = :document_code, weight = 700)
    "A symbol, such as `:name`."
    symbol_text::ThemeText = TextRole(:symbol_literal; font_role = :document_code)
    "An operator, the dot of a field access, a range, `::`, `=`, `?:`, `<:`, `->`, and the dollar sign of a string interpolation."
    operator_text::ThemeText = TextRole(:operator; font_role = :document_code)
    "The called function."
    callee_text::ThemeText = TextRole(:function_name; font_role = :document_code)
    "The name of a function, at its definition."
    function_definition_text::ThemeText = TextRole(:function_name; font_role = :document_code, weight = 700)
    "The name of a macro."
    macro_text::ThemeText = TextRole(:macro_name; font_role = :document_code)
    "A type after `::`, after `<:`, and before `{`."
    type_text::ThemeText = TextRole(:type_name; font_role = :document_code)
    "The name of a struct and of an abstract type, at its definition."
    type_definition_text::ThemeText = TextRole(:type_name; font_role = :document_code, weight = 700)
    "A field after a dot."
    field_text::ThemeText = TextRole(:field; font_role = :document_code)
    "The name of a module."
    module_text::ThemeText = TextRole(:module_name; font_role = :document_code, weight = 700)
    "The path of a `using`, and the typed text of the insertion."
    plain_text::ThemeText = TextRole(:text; font_role = :document_code)
    "The completion that the insertion offers."
    hint_text::ThemeText = TextRole(:text_faint; font_role = :document_code)
    "The color of the typed text of the insertion while it names nothing."
    wrong_color::ThemeColor = ColorRole(:error_text)
    "The color of the typed text of the insertion while it names one thing."
    found_color::ThemeColor = ColorRole(:success_text)
end
