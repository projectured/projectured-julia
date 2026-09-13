function make_object_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
