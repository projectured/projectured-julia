# Render a widget tree (from ConversationToWidget / the composer) to graphics,
# including the part-content documents embedded in the cards.
#
# This is the generic `NaturalToGraphics`, so a conversation part can hold *any*
# content document — not just the few types the assistant historically listed —
# and still render (unknown types degrade to the reflective `Any` fallback). The
# example-specific Julia/JSON/XML projections are kept as `extra` overrides to
# preserve their established styling, and a bare graphics document passes straight
# through so the layout sizes/places it (the generic graphics_size seam); prose,
# layouts, widgets, every other domain, and the `Any` backstop come from
# `NaturalToGraphics`.
_conversation_widget_graphics(; measure=truetype_measure_text) =
    NaturalToGraphics(measure=measure, extra=Pair{Type,Any}[
        JuliaDocument    => make_julia_projection_example(measure=measure),
        JsonDocument     => make_json_projection_example(measure=measure),
        YamlDocument     => make_yaml_projection_example(measure=measure),
        XmlDocument      => make_xml_projection_example(measure=measure),
        # Assistant chat shows *rendered* markdown; the model still receives the raw
        # source (Assistant `_block_text`/`_doc_source` use the source chain).
        MarkdownDocument => make_markdown_rendered_projection_example(measure=measure),
        # Pass a graphics document straight through; the layout sizes/places it
        # via the generic graphics_size seam (so `GraphicsCircle(10,10,10)` shows).
        GraphicsDocument => IdentityProjection(),
    ])

# Standalone conversation projection: `ConversationConversation → Graphics`,
# rooted at the conversation itself (no `WorkbenchToWidget` stage). Mirrors the
# conversation slot of `make_assistant_projection_example`, so what renders here
# is exactly what the assistant panel shows for its scroll-back.
#
# Chain: Conversation → Syntax → Text → (WordWrap) → Graphics, with `JuliaDocument`
# code bodies routed through the Julia projection and `TextBlock` straight to text.
function make_conversation_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_20
    w2g  = WidgetToGraphics(font; measure=measure)
    text_to_graphics = ChainingProjection(WordWrapping(measure=measure),
                                            TextToGraphics(measure=measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            TextDocument         => text_to_graphics,
            JuliaDocument        => make_julia_projection_example(measure=measure),
            # Rendered markdown on screen; the model still gets raw source.
            MarkdownDocument     => make_markdown_rendered_projection_example(measure=measure),
            # `indent_size=0` keeps newlines inside message bodies aligned at
            # column 0 with the surrounding messages (same as the assistant).
            ConversationDocument => ChainingProjection(
                                        RecursiveProjection(ConversationToSyntax()),
                                        RecursiveProjection(SyntaxToText(indent_size=0)),
                                        text_to_graphics),
        ],
    )))
end

# Widget presentation: `ConversationConversation → Widget bubbles → Graphics`.
# Two stages: the conversation projects to a vertical list of collapsible turn
# cards (each a WidgetCard with an avatar header) holding collapsible part cards;
# then the widget tree — and the part-content documents embedded in it — are
# rendered to graphics by `_conversation_widget_graphics`, the shared
# NaturalToGraphics-based content renderer (so a part can hold any document).
make_conversation_widget_projection_example(; measure=truetype_measure_text) =
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
make_conversation_editor_projection_example(; measure=truetype_measure_text) =
    ChainingProjection(
        RecursiveProjection(ConversationComposerToWidget()),
        _conversation_widget_graphics(measure=measure),
    )
