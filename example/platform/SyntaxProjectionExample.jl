function make_syntax_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", StyleFont("DejaVu Sans Mono", 20), color_default),
            collapsed_marker = TextString("▸", StyleFont("DejaVu Sans Mono", 20), color_default))),
        TextToGraphics(measure=measure),
    )
end
