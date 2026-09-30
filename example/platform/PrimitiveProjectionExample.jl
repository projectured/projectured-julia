function make_primitive_string_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        PrimitiveStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
