function make_primitive_string_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        PrimitiveStringToSyntaxLeaf(),
        SyntaxLeafToText(),
        TextToGraphics(measure=measure),
    )
end
