function make_reversing_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        ReversingProjection(),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
