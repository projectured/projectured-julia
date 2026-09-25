function make_filtering_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        FilteringProjection(predicate = x -> startswith(x.value, r"[aeiou]")),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
