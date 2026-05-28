"""
    make_assistant_projection_example(; measure=sdl_measure_text)

Build a projection chain that takes a `WorkbenchAssistant` to a
`GraphicsCanvas`. Unlike the full workbench projection, this chain is
focused on the assistant alone — no tabs, no navigator, no editor.

The conversation goes through `ConversationToSyntax` → `SyntaxToText` →
`TextToGraphics`, so layout (line stacking, word wrap, indentation)
is handled by the existing text-rendering machinery rather than a
manual widget-position layout.
"""
function make_assistant_projection_example(; measure=sdl_measure_text)
    # Use the repo-bundled font (Tuffy isn't always installed system-wide).
    font = font_ubuntu_monospace_regular_24
    # Dark text — the SDL backend uses a cream background; the workbench's
    # default `(0xee, 0xee, 0xee, 0xff)` pale-gray is for dark themes only.
    fg   = (0x22, 0x22, 0x22, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)

    inner_chain = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextDocument         => TextToGraphics(measure=measure),
            PrimitiveDocument    => SequentialProjection(
                                        RecursiveProjection(PrimitiveToSyntax()),
                                        RecursiveProjection(SyntaxToText()),
                                        TextToGraphics(measure=measure)),
            JuliaDocument        => make_julia_projection_example(measure=measure),
            # Conversation → Syntax → Text → Graphics
            ConversationDocument => SequentialProjection(
                                        RecursiveProjection(ConversationToSyntax()),
                                        RecursiveProjection(SyntaxToText()),
                                        TextToGraphics(measure=measure)),
        ],
    )))

    SequentialProjection(
        RecursiveProjection(WorkbenchToWidget()),
        inner_chain,
    )
end
