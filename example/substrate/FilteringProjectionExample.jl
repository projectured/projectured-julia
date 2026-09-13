function make_filtering_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        FilteringProjection(predicate = x -> startswith(x.value, r"[aeiou]")),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
