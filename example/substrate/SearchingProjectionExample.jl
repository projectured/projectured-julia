function make_searching_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        SearchingProjection(r"a"),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
