function make_julia_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(JuliaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
