function make_focusing_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        FocusingProjection(
            part_type=JsonArray,
            part=ReferencePath(PositionReference(3)),
        ),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
