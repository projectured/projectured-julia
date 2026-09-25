# Render a widget tree (from ConversationToWidget / the composer) to graphics,
# including the part-content documents embedded in the cards.
#
# This is the generic `NaturalToGraphics`, so a conversation part can hold *any*
# content document — not just the few types the assistant historically listed —
# and still render (unknown types degrade to the reflective `Any` fallback). The
# example-specific Julia/JSON/XML projections are kept as `extra` overrides to
# preserve their established styling, and a bare graphics document passes straight
# through so the layout sizes/places it (the generic get_graphics_size seam); prose,
# layouts, widgets, every other domain, and the `Any` backstop come from
# `NaturalToGraphics`.
_conversation_widget_graphics(; measure=FontFileMeasure()) =
    NaturalToGraphics(measure=measure, extra=Pair{Type,Any}[
        JuliaDocument    => make_julia_projection_example(measure=measure),
        JsonDocument     => make_json_projection_example(measure=measure),
        YamlDocument     => make_yaml_projection_example(measure=measure),
        XmlDocument      => make_xml_projection_example(measure=measure),
        # Assistant chat shows *rendered* markdown; the model still receives the raw
        # source (Assistant `_block_text`/`_doc_source` use the source chain). A
        # page is a stack of its blocks, as in a tab, so a table on it is a widget
        # table; each block of the page comes back to the row below it.
        MarkdownRoot     => ChainingProjection(MarkdownRootToVerticalLayout(),
                                               VerticalLayoutToGraphicsCanvas()),
        MarkdownDocument => make_markdown_rendered_projection_example(measure=measure),
        # Pass a graphics document straight through; the layout sizes/places it
        # via the generic get_graphics_size seam (so `GraphicsCircle(10,10,10)` shows).
        GraphicsDocument => IdentityProjection(),
    ])

# Widget presentation: `ConversationConversation → Widget bubbles → Graphics`.
# Two stages: the conversation projects to a vertical list of collapsible turn
# cards (each a WidgetCard with an avatar header) holding collapsible part cards;
# then the widget tree — and the part-content documents embedded in it — are
# rendered to graphics by `_conversation_widget_graphics`, the shared
# NaturalToGraphics-based content renderer (so a part can hold any document).
make_conversation_widget_projection_example(; measure=FontFileMeasure()) =
    ChainingProjection(
        RecursiveProjection(ConversationToWidget()),
        _conversation_widget_graphics(measure=measure),
    )

# Composer (Stage 3b): a draft `ConversationTurn` edited part by part, rendered
# through the **widget** pipeline. `ConversationComposerToWidget` is
# self-contained — it renders the turn as a chat-bubble `WidgetCard` of per-part
# cards and reads every gesture itself — then the widget tree is rendered to
# graphics by the same `_conversation_widget_graphics` as the conversation and
# assistant panels.
make_conversation_editor_projection_example(; measure=FontFileMeasure()) =
    ChainingProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        _conversation_widget_graphics(measure=measure),
    )
