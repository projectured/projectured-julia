function make_focusing_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        FocusingProjection(
            part_type=JsonArray,
            # Focus on the nested JsonArray (element 3). A structural focus
            # descends into an *element* — `ElementReferenceStep`, not a cursor
            # `PositionReferenceStep` (a zero-width caret evaluates to a `Position`,
            # not a document, so it can't be focused into).
            part=Reference(ElementReferenceStep(3)),
        ),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
