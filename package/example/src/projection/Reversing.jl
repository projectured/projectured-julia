function make_reversing_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        ReversingProjection(),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
