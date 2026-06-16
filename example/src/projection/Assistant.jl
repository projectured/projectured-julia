# Render a widget tree (from ConversationToWidget / the composer) to graphics,
# including the part-content documents embedded in the cards.
function _conversation_widget_graphics(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=measure)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
            VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
            TextDocument     => text_to_graphics,
            JuliaDocument    => make_julia_projection_example(measure=measure),
            JsonDocument     => make_json_projection_example(measure=measure),
            XmlDocument      => make_xml_projection_example(measure=measure),
        ],
    )))
end

"""
    conversation_draft_entry(; measure=sdl_measure_text) -> Pair

Dispatch entry rendering a `ConversationDraft` (the assistant panel's composer
input): the composer produces a widget chat bubble, then `widget_graphics`
renders it. Place **before** any `ConversationDocument` entry, since
`ConversationDraft <: ConversationDocument`.
"""
conversation_draft_entry(; measure=sdl_measure_text) =
    ConversationDraft => SequentialProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        _conversation_widget_graphics(measure=measure))

"""
    conversation_widget_entry(; measure=sdl_measure_text) -> Pair

Dispatch entry rendering the conversation history (`ConversationDocument`) as the
Stage-2 widget chat bubbles (`ConversationToWidget → widget_graphics`). Shared by
the assistant, workbench, and wrapper panels so they all show the widget chat.
"""
conversation_widget_entry(; measure=sdl_measure_text) =
    ConversationDocument => SequentialProjection(
        RecursiveProjection(ConversationToWidget()),
        _conversation_widget_graphics(measure=measure))

"""
    make_assistant_projection_example(; measure=sdl_measure_text)

Build a projection chain that takes a `WorkbenchAssistant` to a
`GraphicsCanvas`. Unlike the full workbench projection, this chain is
focused on the assistant alone — no tabs, no navigator, no editor.

Stage-6 wiring: the conversation pane is the widget chat presentation
(`ConversationToWidget`) and the input pane is the composer
(`ConversationComposerToWidget`) on the assistant's draft turn (wrapped in a
`ConversationDraft`). Both are widget-producing projections, so each is a
two-stage chain `…ToWidget → widget_graphics`, where `widget_graphics` renders
the widget tree (and the part-content documents it embeds — text, Julia, JSON,
XML) to graphics.
"""
function make_assistant_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=measure)
    # Route the conversation history and the draft through their widget chains.
    # `ConversationDraft` precedes `ConversationDocument` (its subtype).
    inner_chain = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            conversation_draft_entry(measure=measure),
            conversation_widget_entry(measure=measure),
        ],
    )))
    SequentialProjection(
        RecursiveProjection(WorkbenchToWidget()),
        inner_chain,
    )
end
