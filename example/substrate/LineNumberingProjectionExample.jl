function make_line_numbering_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        LineNumbering(),
        TextToGraphics(measure=measure),
    )
end
