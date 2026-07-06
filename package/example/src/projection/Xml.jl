function make_xml_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
