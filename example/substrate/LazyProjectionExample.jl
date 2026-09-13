function make_lazy_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_lazy_bidirectional_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
