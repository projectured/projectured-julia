function make_graphics_image_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
