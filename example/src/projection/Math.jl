function make_math_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(MathToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
