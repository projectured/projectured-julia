function make_object_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(ObjectToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
