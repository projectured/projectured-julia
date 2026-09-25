function make_yaml_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(YamlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
