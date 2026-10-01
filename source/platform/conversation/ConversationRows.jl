# Fragment of `ConversationModule` — the rows that draw a conversation and its
# draft as chat bubbles, for the table of a renderer. What a part of a bubble
# holds is drawn by the natural renderer, so a part shows a document of every
# domain that the session loaded.

"""
    make_conversation_row(; measure) -> Pair

The row that draws a conversation as chat bubbles: a card for each turn, and in
it a card for each part, which the natural renderer draws. Put
[`make_conversation_draft_row`](@ref) before it in a table, because a draft is a
conversation document too.
"""
make_conversation_row(; measure::TextMeasure) =
    ConversationDocument => ChainingProjection(
        RecursiveProjection(ConversationToWidget()),
        NaturalToGraphics(measure = measure))

"""
    make_conversation_draft_row(; measure) -> Pair

The row that draws the draft that a person composes, the input of an
assistant, as a chat bubble that reads every gesture itself.
"""
make_conversation_draft_row(; measure::TextMeasure) =
    ConversationDraft => ChainingProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        NaturalToGraphics(measure = measure))
