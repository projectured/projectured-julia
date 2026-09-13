function make_xml_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
