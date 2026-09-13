function make_book_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(BookToSyntax()),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
