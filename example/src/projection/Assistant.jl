"""
    conversation_draft_entry(; measure=sdl_measure_text) -> Pair

The dispatch entry that renders a `ConversationDraft` (the assistant panel's
composer input) to graphics: the composer produces a widget chat bubble, then a
two-stage `composer → widget_graphics` chain renders it (and the text/Julia/JSON/
XML documents embedded in its part cards). Shared by every projection that draws
the assistant panel (assistant, workbench, wrapper). Place it **before** any
`ConversationDocument` entry, since `ConversationDraft <: ConversationDocument`.
"""
function conversation_draft_entry(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=measure)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    widget_graphics = RecursiveProjection(TypeDispatchingProjection(vcat(
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
    ConversationDraft => SequentialProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        widget_graphics)
end

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
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure))
    w2g  = WidgetToGraphics(font; measure=measure)

    # Widget tree (from ConversationToWidget / the composer) → graphics, including
    # the part-content documents embedded in the cards.
    content_dispatch = Pair{DataType,Any}[
        HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
        VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
        TextDocument     => text_to_graphics,
        JuliaDocument    => make_julia_projection_example(measure=measure),
        JsonDocument     => make_json_projection_example(measure=measure),
        XmlDocument      => make_xml_projection_example(measure=measure),
    ]
    widget_graphics = RecursiveProjection(TypeDispatchingProjection(vcat(w2g.dispatch, content_dispatch)))

    # The panel widget tree → graphics, routing the conversation history and the
    # draft through their widget chains. `ConversationDraft` must precede
    # `ConversationDocument` (it is a subtype) so the draft hits the composer.
    inner_chain = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        content_dispatch,
        Pair{DataType,Any}[
            ConversationDraft    => SequentialProjection(
                                        RecursiveProjection(ConversationComposerToWidget()),
                                        widget_graphics),
            ConversationDocument => SequentialProjection(
                                        RecursiveProjection(ConversationToWidget()),
                                        widget_graphics),
        ],
    )))

    SequentialProjection(
        RecursiveProjection(WorkbenchToWidget()),
        inner_chain,
    )
end
