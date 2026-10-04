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
    "A variable, and the label of an object that stands in the code, such as a widget pasted into a form."
    identifier_text::TextRole = TextRole(color_solarized_violet)
    "A number, a string, a character, a chunk of an interpolated string, the quotes of a string interpolation, and a docstring."
    literal_text::TextRole = TextRole(color_solarized_green)
    "A quote, a delimiter, a separator, a brace and a fence."
    punctuation_text::TextRole = TextRole(color_solarized_gray)
    "A comment, in a field of code that colors Julia as a person types it."
    comment_text::TextRole = TextRole(color_solarized_gray)
    "A keyword, `true`, `false` and `nothing`."
    keyword_text::TextRole = TextRole(color_solarized_magenta; weight = 700)
    "A symbol, `<:`, `->`, and the dollar sign of a string interpolation."
    symbol_text::TextRole = TextRole(color_solarized_magenta)
    "An operator, the dot of a field access, a range, `::`, `=` and `?:`."
    operator_text::TextRole = TextRole(color_solarized_cyan)
    "The called function, and the name of a macro."
    callee_text::TextRole = TextRole(color_solarized_blue)
    "The name of a module."
    name_text::TextRole = TextRole(color_solarized_blue; weight = 700)
    "The path of a `using`, and the typed text of the insertion."
    plain_text::TextRole = TextRole(color_default)
    "The completion that the insertion offers."
    hint_text::TextRole = TextRole(color_completion_hint)
    "The color of the typed text of the insertion while it names nothing."
    wrong_color::StyleColor = color_solarized_red
    "The color of the typed text of the insertion while it names one thing."
    found_color::StyleColor = color_solarized_green
end
