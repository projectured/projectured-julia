function make_object_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
