function make_yaml_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(YamlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
