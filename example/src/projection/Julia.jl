function make_julia_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(JuliaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        LineNumbering(),
        TextToGraphics(measure=measure),
    )
end
