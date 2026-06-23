function make_sorting_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        SortingProjection(by = x -> x.value),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
