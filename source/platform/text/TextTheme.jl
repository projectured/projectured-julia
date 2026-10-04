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

A text projection reads the scaled theme through its `UntrackedCell` style
fields. The fonts and the colors of a text document stay as its author set them.
`TextHighlighting`, `SelectionInverting` and `TextLineNumbering` take their
colors and fonts as keywords: no view of the platform builds them.
"""
@theme struct TextTheme
    "The font of a text that no document styles, such as the line of a placeholder."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The caret of the text that holds the keyboard."
    caret::StyleColor = color_black
    "The caret of a text that keeps its place while another holds the keyboard."
    dormant_caret::StyleColor = StyleColor(0.55, 0.55, 0.55, 1.0)
    "The width of a caret."
    caret_width::LineWidth = LineWidth(2)
    "The band under the selected text, while its text holds the keyboard."
    highlight::StyleColor = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x40 / 255)
    "The band under the selected text, while another text holds the keyboard."
    dormant_highlight::StyleColor = StyleColor(0x88 / 255, 0x88 / 255, 0x88 / 255, 0x28 / 255)
    "The radius of the corners of the band under the selected text."
    highlight_radius::Radius = Radius(4)
    "The distance between the lines of code, as a multiple of the natural line height of its font."
    code_line_spacing::LineSpacing = MultipleSpacing(1.35)
    "The distance between the lines of prose, as a multiple of the natural line height of its font."
    prose_line_spacing::LineSpacing = MultipleSpacing(1.3)
    "A boolean that a primitive projection prints as text."
    bool_text::TextRole = TextRole(color_solarized_cyan)
    "A number that a primitive projection prints as text."
    number_text::TextRole = TextRole(color_solarized_magenta)
    "A string that a primitive projection prints as text."
    string_text::TextRole = TextRole(color_solarized_green)
    "The text of a type-in that is no value yet, such as `1e` on the way to a number."
    wrong_color::StyleColor = color_solarized_red
    "What an empty type-in shows, such as `missing` in a cell of a data frame."
    placeholder_text::TextRole = TextRole(color_completion_hint)
    "A text that no other field styles, such as the name of an empty document."
    plain_text::TextRole = TextRole(color_default)
    "The number before each line of a text with line numbers."
    line_number_text::TextRole = TextRole(StyleColor(88 / 255, 110 / 255, 117 / 255, 1.0))
    "The surface behind each match of a search in a text."
    match_highlight::StyleColor = color_yellow
    "The surface of the character under a block caret, which shows inverted."
    inverted_background::StyleColor = color_solarized_background_dark
    "The character under a block caret, which shows inverted."
    inverted_foreground::StyleColor = color_solarized_content_lighter
    "The mark of a part whose projection failed, in place of that part."
    fault_text::TextRole = TextRole(color_solarized_red; family = "DejaVu Sans Mono", weight = 700,
                                    relative_size = 0.8)
end

