function make_filtering_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        FilteringProjection(predicate = x -> startswith(x.value, r"[aeiou]")),
        NestingProjection(CollectionToSyntax(), PrimitiveStringToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
