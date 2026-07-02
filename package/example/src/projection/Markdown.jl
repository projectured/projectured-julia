function make_markdown_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(MarkdownToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
