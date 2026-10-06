"""
    make_assistant_projection_example(; measure=FontFileMeasure())

Build a projection chain that takes a `Assistant` to a
`GraphicsCanvas` — the assistant alone, no tabs, no Files pane, no editor.

Stage-6 wiring: the conversation pane is the widget chat presentation
(`ConversationToWidget`) and the input pane is the composer
(`ConversationComposerToWidget`) on the assistant's `ConversationDraft`. Both are
widget-producing projections, so each is a
two-stage chain `…ToWidget → widget_graphics`, where `widget_graphics` renders
the widget tree (and the part-content documents it embeds — text, Julia, JSON,
XML) to graphics.
"""
function make_assistant_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    w2g  = WidgetToGraphics(font; measure=measure)
    # Route the conversation history and the draft through their widget chains.
    # `ConversationDraft` precedes `ConversationDocument` (its subtype).
    inner_chain = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            make_conversation_draft_row(measure=measure),
            make_conversation_row(measure=measure),
        ],
    )))
    ChainingProjection(
        RecursiveProjection(AssistantToWidgetSplitPane()),
        inner_chain,
    )
end
