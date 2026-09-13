"""
    conversation_draft_entry(; measure=measure_truetype_text) -> Pair

Dispatch entry rendering a `ConversationDraft` (the assistant panel's composer
input): the composer produces a widget chat bubble, then `widget_graphics`
renders it. Place **before** any `ConversationDocument` entry, since
`ConversationDraft <: ConversationDocument`.
"""
conversation_draft_entry(; measure=measure_truetype_text) =
    ConversationDraft => ChainingProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        _conversation_widget_graphics(measure=measure))

"""
    conversation_widget_entry(; measure=measure_truetype_text) -> Pair

Dispatch entry rendering the conversation history (`ConversationDocument`) as the
Stage-2 widget chat bubbles (`ConversationToWidget → widget_graphics`). Shared by
the assistant, workbench, and wrapper panels so they all show the widget chat.
"""
conversation_widget_entry(; measure=measure_truetype_text) =
    ConversationDocument => ChainingProjection(
        RecursiveProjection(ConversationToWidget()),
        _conversation_widget_graphics(measure=measure))

"""
    make_assistant_projection_example(; measure=measure_truetype_text)

Build a projection chain that takes a `Assistant` to a
`GraphicsCanvas`. Unlike the full workbench projection, this chain is
focused on the assistant alone — no tabs, no navigator, no editor.

Stage-6 wiring: the conversation pane is the widget chat presentation
(`ConversationToWidget`) and the input pane is the composer
(`ConversationComposerToWidget`) on the assistant's `ConversationDraft`. Both are
widget-producing projections, so each is a
two-stage chain `…ToWidget → widget_graphics`, where `widget_graphics` renders
the widget tree (and the part-content documents it embeds — text, Julia, JSON,
XML) to graphics.
"""
function make_assistant_projection_example(; measure=measure_truetype_text)
    font = font_ubuntu_monospace_regular_20
    w2g  = WidgetToGraphics(font; measure=measure)
    # Route the conversation history and the draft through their widget chains.
    # `ConversationDraft` precedes `ConversationDocument` (its subtype).
    inner_chain = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            conversation_draft_entry(measure=measure),
            conversation_widget_entry(measure=measure),
        ],
    )))
    ChainingProjection(
        RecursiveProjection(WorkbenchToWidget()),
        inner_chain,
    )
end
