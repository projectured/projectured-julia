function make_reversing_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        ReversingProjection(),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
