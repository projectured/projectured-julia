# Fragment of `ConversationModule` — the theme of a conversation: the label and
# the glyph beside a turn's role, the tag and the sections of a part, the
# prompts of a form, and the colors the composer draws a typed part with.

"""
    ConversationTheme

The fonts and the colors of a conversation: the label and the glyph beside a
turn, the tag of a part, the sections of an evaluation, the `>`/`=` prompts of
a form, and the typed text of the composer.

The theme of the conversation projections. `@theme` declares it, so
`ScaledConversationTheme` holds each value times its scale, and
`ConversationTheme()` is the default theme.

The fields are in groups: the base fonts, the label and the glyph of each
role, the tag and the sections of a part, the prompts of a form, the colors
the composer draws a typed part with, and the gaps between the parts of the
widgets. Each field has a docstring that says what it draws, which the
appearance tab shows under its name.

A conversation projection holds its styles and no theme. Its builder
(`ConversationToWidget`, `make_conversation_composer_projection`,
`make_evaluator_form_projection`, `make_evaluator_toplevel_projection`) gives
them with `get_conversation_style`, from a theme scaled or not; a projection built
with no styles holds the plain values of the default theme.
"""
@theme struct ConversationTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The font that the code and the prompts of this theme follow: its family, its weight and its size."
    code_font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The label beside a turn whose role is the user."
    user_role_text::TextRole = TextRole(:accent_text; weight = 700, relative_size = 0.9)
    "The label beside a turn whose role is the assistant."
    assistant_role_text::TextRole = TextRole(PaletteColor(:teal, 11; minimum_contrast = 4.5); weight = 700, relative_size = 0.9)
    "The label beside a turn whose role is neither the user nor the assistant."
    other_role_text::TextRole = TextRole(:text_muted; weight = 700, relative_size = 0.9)
    "The glyph beside a turn whose role is the user."
    user_role_icon::TextRole = TextRole(:accent_text; family = "Lucide")
    "The glyph beside a turn whose role is the assistant."
    assistant_role_icon::TextRole = TextRole(PaletteColor(:teal, 11; minimum_contrast = 4.5); family = "Lucide")
    "The glyph beside a turn whose role is neither the user nor the assistant."
    other_role_icon::TextRole = TextRole(:text_muted; family = "Lucide")
    "The tag that names a part's kind: a code's language, \"thinking\", or the name of a tool."
    kind_text::TextRole = TextRole(:text_muted; weight = 700, relative_size = 0.8)
    "The title of a section of an evaluation: its code or its result."
    section_text::TextRole = TextRole(:text_muted; relative_size = 0.8)
    "The title of a section of an evaluation whose result is an error."
    error_text::TextRole = TextRole(:error_text; weight = 700, relative_size = 0.8)
    "The `>`/`=` prompt before the code or the result of a form."
    prompt_text::TextRole = TextRole(:text_muted; base = :code_font)
    "The `=` prompt before the result of a form whose evaluation failed."
    error_prompt_text::TextRole = TextRole(:error_text; base = :code_font)
    "The typed text of an editable part of the composer."
    plain_color::StyleColor = ColorRole(:text)
    "The placeholder of an empty part, and the static words of a kind chooser."
    placeholder_color::StyleColor = ColorRole(:text_faint)
    "The value of a kind chooser that names a known kind."
    valid_color::StyleColor = ColorRole(:success_text)
    "The value of a kind chooser that names no kind."
    invalid_color::StyleColor = ColorRole(:error_text)
    "The hint that completes the value of a kind chooser."
    completion_hint_color::StyleColor = ColorRole(:text_faint)
    "The gap between the parts of one turn, and between the cards of the composer."
    part_gap::Spacing = Spacing(8)
    "The gap between the turns of a transcript."
    turn_gap::Spacing = Spacing(8)
    "The gap between the icon and the label of a turn's role."
    role_gap::Spacing = Spacing(10)
    "The gap between the form and the result of an evaluation shown in a transcript."
    section_gap::Spacing = Spacing(10)
    "The indent of a section of an evaluation under the panel that holds it."
    section_indent::Spacing = Spacing(Inset(0, 0, 12, 0))
    "The gap between the forms of a standalone REPL."
    element_gap::Spacing = Spacing(8)
    "The gap between the code and the result of a form, and between the rows of a REPL."
    row_gap::Spacing = Spacing(4)
    "The gap between a prompt and what follows it."
    prompt_gap::Spacing = Spacing(8)
    "The gap between the options above the forms of the evaluator."
    option_gap::Spacing = Spacing(12)
    "The gap between the transcript and the composer of an assistant card."
    card_gap::Spacing = Spacing(6)
    "The least height of the composer under the transcript of the assistant."
    composer_min_height::ControlSize = ControlSize(200)
end
