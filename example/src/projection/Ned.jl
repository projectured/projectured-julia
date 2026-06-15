function make_ned_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(NedToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
