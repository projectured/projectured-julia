function make_primitive_string_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        PrimitiveStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
