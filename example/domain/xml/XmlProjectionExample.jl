function make_xml_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
