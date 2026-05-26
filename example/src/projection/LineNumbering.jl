function make_line_numbering_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        LineNumbering(),
        TextToGraphics(measure=measure),
    )
end
