function make_searching_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        SearchingProjection(r"a"),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
