function make_primitive_string_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        PrimitiveStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
