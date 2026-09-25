function make_julia_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(JuliaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
