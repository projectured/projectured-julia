function make_book_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(BookToSyntax()),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
