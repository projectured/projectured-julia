function JsonXmlToSyntax()
    RecursiveProjection(TypeDispatchingProjection(
        JsonNull        => JsonNullToSyntaxLeaf(),
        JsonBool        => JsonBoolToSyntaxLeaf(),
        JsonNumber      => JsonNumberToSyntaxLeaf(),
        JsonString      => JsonStringToSyntaxLeaf(),
        JsonArray       => JsonArrayToSyntaxNode(),
        JsonObject      => JsonObjectToSyntaxNode(),
        JsonInsertion   => JsonInsertionToSyntaxLeaf(),
        JsonObjectEntry => JsonObjectEntryToSyntaxNode(),
        Vector{Cell}    => CopyingProjection(),
        XmlText         => XmlTextToSyntaxLeaf(),
        XmlAttribute    => XmlAttributeToSyntaxNode(),
        XmlElement      => XmlElementToSyntaxNode(),
    ))
end

function make_mixed_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        JsonXmlToSyntax(),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
