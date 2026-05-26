function make_syntax_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
