function make_xml_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# Widget-based pipeline: Domain → Syntax → Widget → Graphics. The same XML→Syntax
# stage, then `SyntaxToWidget` turns each element node into a collapsible card and
# each leaf into embedded text (see `make_syntax_widget_graphics` in Json.jl).
function make_xml_widget_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(XmlToSyntax()),
        RecursiveProjection(SyntaxToWidget()),
        make_syntax_widget_graphics(measure=measure),
    )
end
