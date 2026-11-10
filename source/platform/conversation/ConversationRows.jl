# Fragment of `ConversationModule` — the rows that draw a conversation and its
# draft as chat bubbles, for the table of a renderer. What a part of a bubble
# holds is drawn by the natural renderer, so a part shows a document of every
# domain that the session loaded.

"""
    make_conversation_row(; measure, appearance = Appearance(), settings = nothing) -> Pair

The row that draws a conversation as chat bubbles: a card for each turn, and in
it a card for each part, which the natural renderer draws. Put
[`make_conversation_draft_row`](@ref) before it in a table, because a draft is a
conversation document too.

The transcript follows `finished_turn` of the `ConversationSettings` of
`settings`; with no settings, a finished turn shows its message.
"""
make_conversation_row(; measure::TextMeasure, appearance::Appearance = Appearance(),
                      settings::Union{Nothing,Settings} = nothing) =
    ConversationDocument => ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = ConversationToWidget(;
                                                    theme = get_scaled_theme!(appearance, ConversationTheme),
                                                    widget_theme = get_scaled_theme!(appearance, WidgetTheme),
                                                    finished_turn = _get_finished_turn(settings)),
                                                    substitute = FaultToWidget())),
        NaturalToGraphics(measure = measure, appearance = appearance))

# What a finished turn shows: the cell of the setting, so the transcript follows a
# change, or the default with no settings.
_get_finished_turn(::Nothing) = :message
_get_finished_turn(settings::Settings) =
    get_setting_cell(get_settings_group!(settings, ConversationSettings), :finished_turn)

"""
    make_conversation_draft_row(; measure, appearance = Appearance()) -> Pair

The row that draws the draft that a person composes, the input of an
assistant, as a chat bubble that reads every gesture itself.
"""
make_conversation_draft_row(; measure::TextMeasure, appearance::Appearance = Appearance()) =
    ConversationDraft => ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = make_conversation_composer_projection(;
                                                    theme = get_scaled_theme!(appearance, ConversationTheme),
                                                    widget_theme = get_scaled_theme!(appearance, WidgetTheme)),
                                                    substitute = FaultToWidget())),
        NaturalToGraphics(measure = measure, appearance = appearance))
