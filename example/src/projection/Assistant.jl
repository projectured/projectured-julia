"""
    make_assistant_projection_example(; measure=sdl_measure_text)

Build a projection chain that takes a `WorkbenchAssistant` to a
`GraphicsCanvas`. Unlike the full workbench projection, this chain is
focused on the assistant alone — no tabs, no navigator, no editor.

The chain handles the recursive `Conversation → widget tree → graphics`
case by sharing the inner widget-rendering chain as the second step
of the `ConversationDocument` dispatch entry. The shared `dispatch`
vector is mutated *after* `TypeDispatchingProjection` construction so
the entry can reference the very chain that owns it.
"""
function make_assistant_projection_example(; measure=sdl_measure_text)
    # Use the repo-bundled font (Tuffy isn't always installed system-wide).
    font = font_ubuntu_monospace_regular_24
    # Dark text — the SDL backend uses a cream background; the workbench's
    # default `(0xee, 0xee, 0xee, 0xff)` pale-gray is for dark themes only.
    fg   = (0x22, 0x22, 0x22, 0xff)
    w2g  = WidgetToGraphics(font; measure=measure, default_fg=fg)

    # Build the dispatch table for widget+leaf-document → graphics.
    dispatch = vcat(
        w2g.dispatch,
        Pair{DataType,Any}[
            TextDocument      => TextToGraphics(measure=measure),
            PrimitiveDocument => SequentialProjection(
                                     RecursiveProjection(PrimitiveToSyntax()),
                                     RecursiveProjection(SyntaxToText()),
                                     TextToGraphics(measure=measure)),
            JuliaDocument     => make_julia_projection_example(measure=measure),
        ],
    )
    inner_chain = RecursiveProjection(TypeDispatchingProjection(dispatch))

    # `ConversationDocument` needs two steps: produce widgets, then
    # render those widgets as graphics. The second step is the same
    # `inner_chain` we just built — mutate the dispatch vector now
    # that it exists.
    push!(dispatch, ConversationDocument => SequentialProjection(
        RecursiveProjection(ConversationToWidget()),
        inner_chain,
    ))

    SequentialProjection(
        RecursiveProjection(WorkbenchToWidget()),
        inner_chain,
    )
end
