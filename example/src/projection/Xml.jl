function make_xml_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
