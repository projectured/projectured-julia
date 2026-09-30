function make_book_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(BookToSyntax()),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
