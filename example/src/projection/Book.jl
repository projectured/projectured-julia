function make_book_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(BookToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
