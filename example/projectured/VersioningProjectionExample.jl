# Projects a VersionedObject down to graphics. The versioning projection sits at
# the top of the recursion: it selects one ObjectVersion by the document's
# criterion and recurses into that version's value (a JSON object), and the same
# dispatcher turns that JSON into a syntax tree. SyntaxToText then TextToGraphics
# finish the pipeline, exactly as the plain JSON example does. Nested
# VersionedObjects (a versioned value containing further versioned objects)
# resolve automatically — each by its own criterion — because the recursion
# re-dispatches on VersionedObject at every level.
#
# Gestures owned by the versioning projection (the rest fall through to JSON):
#   Ctrl+Shift+S   snapshot the active value into a new (front) ObjectVersion
#   Ctrl+Delete    delete the active version
function make_versioning_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            VersionedObject => VersioningToAnyProjection(),
            JsonNull        => JsonNullToSyntaxLeaf(),
            JsonBool        => JsonBoolToSyntaxLeaf(),
            JsonNumber      => JsonNumberToSyntaxLeaf(),
            JsonString      => JsonStringToSyntaxLeaf(),
            JsonArray       => JsonArrayToSyntaxNode(),
            JsonObject      => JsonObjectToSyntaxNode(),
            JsonInsertion   => JsonInsertionToSyntaxLeaf(),
            JsonObjectEntry => JsonObjectEntryToSyntaxNode(),
            Vector{Cell}    => CopyingProjection(),
        )),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
