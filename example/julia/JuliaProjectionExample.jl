function make_julia_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(JuliaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
