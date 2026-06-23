function make_line_numbering_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        LineNumbering(),
        TextToGraphics(measure=measure),
    )
end
