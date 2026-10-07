# Fragment of `JsonModule` — the theme of the JSON syntax: the text of each kind
# of value, of a key, and of the brackets and the separators.

"""
    JsonTheme

The colors and the fonts of a JSON document: its values, its keys, its
brackets and its separators.

The theme of the JSON projections. `@theme` declares it, so `ScaledJsonTheme`
holds each value times its scale, and `JsonTheme()` is the default theme.

The fields are the text styles of a value of each kind, a string's quotes, an
object's key, a delimiter and a separator. Each field has a docstring that
says what it draws, which the appearance tab shows under its name.

A JSON projection holds its styles and no theme; its builder gives them with `get_json_style`,
from a theme scaled or not, and with no theme it holds the plain values of the
default theme.
"""
@theme struct JsonTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A null value."
    null_text::ThemeText = TextRole(:null_literal)
    "A boolean value."
    bool_text::ThemeText = TextRole(:boolean_literal)
    "A number value."
    number_text::ThemeText = TextRole(:number_literal)
    "A string value."
    string_text::ThemeText = TextRole(:string_literal)
    "The quotes around a string."
    quote_text::ThemeText = TextRole(:punctuation)
    "The key of an object member, with its quotes."
    key_text::ThemeText = TextRole(:field)
    "The brackets of an array and the braces of an object."
    delimiter_text::ThemeText = TextRole(:punctuation; weight = 700)
    "A comma, and the colon of a member."
    separator_text::ThemeText = TextRole(:punctuation)
end
