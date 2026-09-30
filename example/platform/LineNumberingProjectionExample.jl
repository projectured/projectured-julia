function make_line_numbering_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        LineNumbering(),
        TextToGraphics(measure=measure),
    )
end
