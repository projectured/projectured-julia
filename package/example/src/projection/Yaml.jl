function make_yaml_projection_example(; measure=truetype_measure_text)
    SequentialProjection(
        RecursiveProjection(YamlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
