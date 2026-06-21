function make_searching_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        SearchingProjection(r"a"),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
