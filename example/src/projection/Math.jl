function make_math_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(MathToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
