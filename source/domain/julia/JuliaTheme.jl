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
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A variable, a name whose kind the place does not give, and the label of an object that stands in the code, such as a widget pasted into a form."
    identifier_text::TextRole = TextRole(:variable)
    "A string, a chunk of an interpolated string, the quotes of a string interpolation, and a docstring."
    string_text::TextRole = TextRole(:string_literal)
    "A character."
    char_text::TextRole = TextRole(:character_literal)
    "An integer and a float."
    number_text::TextRole = TextRole(:number_literal)
    "`true` and `false`."
    bool_text::TextRole = TextRole(:boolean_literal)
    "`nothing`."
    nothing_text::TextRole = TextRole(:null_literal)
    "A quote, a delimiter, a separator, a brace and a fence."
    punctuation_text::TextRole = TextRole(:punctuation)
    "A comment, in a field of code that colors Julia as a person types it."
    comment_text::TextRole = TextRole(:comment)
    "A keyword."
    keyword_text::TextRole = TextRole(:keyword; weight = 700)
    "A symbol, such as `:name`."
    symbol_text::TextRole = TextRole(:symbol_literal)
    "An operator, the dot of a field access, a range, `::`, `=`, `?:`, `<:`, `->`, and the dollar sign of a string interpolation."
    operator_text::TextRole = TextRole(:operator)
    "The called function."
    callee_text::TextRole = TextRole(:function_name)
    "The name of a function, at its definition."
    function_definition_text::TextRole = TextRole(:function_name; weight = 700)
    "The name of a macro."
    macro_text::TextRole = TextRole(:macro_name)
    "A type after `::`, after `<:`, and before `{`."
    type_text::TextRole = TextRole(:type_name)
    "The name of a struct and of an abstract type, at its definition."
    type_definition_text::TextRole = TextRole(:type_name; weight = 700)
    "A field after a dot."
    field_text::TextRole = TextRole(:field)
    "The name of a module."
    module_text::TextRole = TextRole(:module_name; weight = 700)
    "The path of a `using`, and the typed text of the insertion."
    plain_text::TextRole = TextRole(:text)
    "The completion that the insertion offers."
    hint_text::TextRole = TextRole(:text_faint)
    "The color of the typed text of the insertion while it names nothing."
    wrong_color::StyleColor = ColorRole(:error_text)
    "The color of the typed text of the insertion while it names one thing."
    found_color::StyleColor = ColorRole(:success_text)
end
