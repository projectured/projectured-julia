function make_sorting_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        SortingProjection(by = x -> x.value),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
