function make_focusing_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        FocusingProjection(
            part_type=JsonArray,
            part=ReferencePath(PositionReference(3)),
        ),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
