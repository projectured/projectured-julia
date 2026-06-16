# Standalone conversation projection: `ConversationConversation → Graphics`,
# rooted at the conversation itself (no `WorkbenchToWidget` stage). Mirrors the
# conversation slot of `make_assistant_projection_example`, so what renders here
# is exactly what the assistant panel shows for its scroll-back.
#
# Chain: Conversation → Syntax → Text → (WordWrap) → Graphics, with `JuliaDocument`
# code bodies routed through the Julia projection and `TextText` straight to text.
function make_conversation_projection_example(; measure=sdl_measure_text)
    font = font_ubuntu_monospace_regular_24
    w2g  = WidgetToGraphics(font; measure=measure)
    text_to_graphics = SequentialProjection(WordWrapping(measure=measure),
                                            TextToGraphics(measure=measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextDocument         => text_to_graphics,
            JuliaDocument        => make_julia_projection_example(measure=measure),
            # `indent_size=0` keeps newlines inside message bodies aligned at
            # column 0 with the surrounding messages (same as the assistant).
            ConversationDocument => SequentialProjection(
                                        RecursiveProjection(ConversationToSyntax()),
                                        RecursiveProjection(SyntaxToText(indent_size=0)),
                                        text_to_graphics),
        ],
    )))
end
