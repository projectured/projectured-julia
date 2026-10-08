# Fragment of `TextModule` — the theme of the text: the caret, the selection and
# the text that the text projections style on their own.

"""
    TextTheme

The font, the caret and the highlight of text in a document, the colors of a
boolean, a number and a string, and of a type-in that is no value yet and of its
placeholder.

The theme of the text projections. `@theme` declares it, so `ScaledTextTheme`
holds each value times its scale, and `TextTheme()` is the default theme.

The fields are the font of unstyled text, the caret, the highlight, and the
text styles of a boolean, a number and a string. Each field has a docstring
that says what it draws, which the appearance tab shows under its name.

A text projection holds its styles and no theme; its builder gives them with
`get_text_style`, from a theme scaled or not. The fonts and the colors of a text document stay as its author set them.
`HighlightedTextToText`, `SelectionInverting` and `TextLineNumbering` take their
colors and fonts as keywords: no view of the platform builds them.
"""
@theme struct TextTheme
    "The font of a text that no document styles, such as the line of a placeholder."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The caret of the text that holds the keyboard."
    caret::ThemeColor = ColorRole(:caret)
    "The caret of a text that keeps its place while another holds the keyboard."
    dormant_caret::ThemeColor = ColorRole(:caret_dormant)
    "The width of a caret."
    caret_width::LineWidth = LineWidth(2)
    "The band under the selected text, while its text holds the keyboard."
    highlight::ThemeColor = ColorRole(:selection_band)
    "The band under the selected text, while another text holds the keyboard."
    dormant_highlight::ThemeColor = ColorRole(:selection_band_dormant)
    "The radius of the corners of the band under the selected text."
    highlight_radius::Radius = Radius(4)
    "The distance between the lines of code, as a multiple of the natural line height of its font."
    code_line_spacing::LineSpacing = MultipleSpacing(1.35)
    "The distance between the lines of prose, as a multiple of the natural line height of its font."
    prose_line_spacing::LineSpacing = MultipleSpacing(1.3)
    "A boolean that a primitive projection prints as text."
    bool_text::ThemeText = TextRole(:boolean_literal)
    "A number that a primitive projection prints as text."
    number_text::ThemeText = TextRole(:number_literal)
    "A string that a primitive projection prints as text."
    string_text::ThemeText = TextRole(:string_literal)
    "The text of a type-in that is no value yet, such as `1e` on the way to a number."
    wrong_color::ThemeColor = ColorRole(:error_text)
    "What an empty type-in shows, such as `missing` in a cell of a data frame."
    placeholder_text::ThemeText = TextRole(:text_faint)
    "A text that no other field styles, such as the name of an empty document."
    plain_text::ThemeText = TextRole(:text)
    "The number before each line of a text with line numbers."
    line_number_text::ThemeText = TextRole(:text_muted)
    "The surface behind each match of a search in a text."
    match_highlight::ThemeColor = ColorRole(:search_match)
    "The surface of the character under a block caret, which shows inverted."
    inverted_background::ThemeColor = ColorRole(:text)
    "The character under a block caret, which shows inverted."
    inverted_foreground::ThemeColor = ColorRole(:background)
    "The mark of a part whose projection failed, in place of that part."
    fault_text::ThemeText = TextRole(:error_text; family = "DejaVu Sans Mono", weight = 700,
                                    relative_size = 0.8)
end

