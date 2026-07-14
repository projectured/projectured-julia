function JsonXmlToSyntax()
    RecursiveProjection(TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(),
        JsonBool        => JsonBoolToSyntaxLeaf(),
        JsonNumber      => JsonNumberToSyntaxLeaf(),
        JsonString      => JsonStringToSyntaxLeaf(),
        JsonArray       => JsonArrayToSyntaxNode(),
        JsonObject      => JsonObjectToSyntaxNode(),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(),
        JsonObjectEntry => CopyingProjection(),
        Vector{Cell}    => CopyingProjection(),
        XmlText         => XmlTextToSyntaxLeaf(),
        XmlAttribute    => XmlAttributeToSyntaxNode(),
        XmlElement      => XmlElementToSyntaxNode(),
    ))
end

function make_mixed_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        JsonXmlToSyntax(),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
