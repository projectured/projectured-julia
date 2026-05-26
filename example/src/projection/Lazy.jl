function make_lazy_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_lazy_bidirectional_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
