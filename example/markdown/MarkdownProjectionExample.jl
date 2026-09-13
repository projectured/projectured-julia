function make_markdown_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(MarkdownToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The rendered ("beautiful") view: marker-free, formatted markdown — big bold
# headings, real bold/italic, plain inline code, `•` bullets, `▏` quote bars,
# `───` rules, blue links. Word-wrapped like prose.
function make_markdown_rendered_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(MarkdownToSyntax(; style=:rendered)),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
