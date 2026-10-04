# Fragment of `SyntaxModule` — the theme of the syntax: the text of each kind of
# leaf, of the delimiters, and of the parts of an insertion.

"""
    SyntaxTheme

The colors and the fonts of a syntax view: its values, its names, its brackets
and its separators. They also color the text a person types to add a value,
and the fields of an object that a person inspects.

The theme of the syntax projections. `@theme` declares it, so `ScaledSyntaxTheme`
holds each value times its scale, and `SyntaxTheme()` is the default theme.

The fields are in groups: the leaves, the reflection of an object, the
collections, the insertion, the delimiter under the pointer and the font of
an undelimited node. Each field has a docstring that says what it draws,
which the appearance tab shows under its name.

A syntax projection holds its styles and no theme; its builder gives them with `get_syntax_style`,
from a theme scaled or not, and with no theme it holds the plain values of the
default theme. A domain
that prints its own leaves styles them with a theme of its own.
"""
@theme struct SyntaxTheme
    "A boolean value."
    bool_text::TextRole = TextRole(:constant)
    "A number value."
    number_text::TextRole = TextRole(:constant)
    "A string value."
    string_text::TextRole = TextRole(:string_literal)
    "The quotes around a string or a character."
    quote_text::TextRole = TextRole(:punctuation)
    "A symbol, in the reflected display of an object."
    symbol_text::TextRole = TextRole(:constant)
    "The value `nothing`, in the reflected display of an object."
    nothing_text::TextRole = TextRole(:constant)
    "A boolean value, in the reflected display of an object."
    reflected_bool_text::TextRole = TextRole(:constant)
    "The name of the type of an object."
    type_name_text::TextRole = TextRole(:type_name; weight = 700)
    "The name of a field."
    field_name_text::TextRole = TextRole(:field)
    "The muted italic text of an undefined field, of a cycle and of an empty placeholder."
    note_text::TextRole = TextRole(:text_muted; italic = true)
    "A bracket."
    delimiter_text::TextRole = TextRole(:punctuation; weight = 700)
    "A comma."
    separator_text::TextRole = TextRole(:punctuation)
    "The prefix and the suffix, and the placeholder of an empty buffer, of the insertion."
    label_text::TextRole = TextRole(:text_faint)
    "The typed text of the insertion while it names nothing yet."
    typed_text::TextRole = TextRole(:text)
    "The continuation that a completion offers."
    hint_text::TextRole = TextRole(:text_faint)
    "The color of the typed text of the insertion while it names nothing."
    wrong_color::StyleColor = ColorRole(:error_text)
    "The color of the typed text of the insertion while it names one thing."
    found_color::StyleColor = ColorRole(:success_text)
    "The color of the delimiters around the part under the pointer."
    lit_delimiter::StyleColor = ColorRole(:punctuation_lit)
    "The font of the indentation and the line breaks of a node with no delimiter of its own, such as the body of a block."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "A bracket and a space of a reflected object, in the font of its field names."
    object_delimiter_text::TextRole = TextRole(:punctuation)
    "The ellipsis that stands in for the children of a folded node, in the size of the text around it."
    ellipsis_text::TextRole = TextRole(:text_muted; family = "DejaVu Sans Mono")
    "The mark of a part whose projection failed, in place of that part."
    fault_text::TextRole = TextRole(:error_text; family = "DejaVu Sans Mono", weight = 700,
                                    relative_size = 0.8)
end

