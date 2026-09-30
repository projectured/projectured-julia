function make_markdown_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(MarkdownToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The rendered ("beautiful") view: marker-free, formatted markdown — big bold
# headings, real bold/italic, plain inline code, `•` bullets, `▏` quote bars,
# `───` rules, blue links. Word-wrapped like prose: at the edge of its range,
# and at 800 px at most.
function make_markdown_rendered_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(MarkdownToSyntax(; style=:rendered)),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure, max_width=800),
        TextToGraphics(measure=measure),
    )
end
