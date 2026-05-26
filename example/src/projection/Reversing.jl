function make_reversing_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        ReversingProjection(),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
