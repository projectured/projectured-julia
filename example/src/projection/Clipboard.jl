# Projects a ClipboardSlice down to graphics. The clipboard projection sits at the
# top of the recursion: it recurses into the wrapped JSON `content` (or, once a
# slice is stored and the view is toggled, into the stored `slice`), and the same
# dispatcher turns that JSON into a syntax tree. SyntaxToText then TextToGraphics
# finish the pipeline, exactly as the plain JSON example does.
#
# Gestures owned by the clipboard projection (the rest fall through to JSON):
#   Ctrl+/        toggle between showing the wrapped content and the stored slice
#   Ctrl+C        copy the selected sub-document into the slice (deep copy)
#   Ctrl+X        cut the selected sub-document into the slice
#   Ctrl+N        note: store the live selected object in the slice (no copy)
#   Ctrl+V        paste the stored slice over the current selection
#   Ctrl+Shift+V  paste a fresh deep copy of the stored slice
function make_clipboard_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(TypeDispatchingProjection(
            ClipboardSlice  => ClipboardSliceToAnyProjection(),
            JsonNull        => JsonNullToSyntaxLeaf(),
            JsonBool        => JsonBoolToSyntaxLeaf(),
            JsonNumber      => JsonNumberToSyntaxLeaf(),
            JsonString      => JsonStringToSyntaxLeaf(),
            JsonArray       => JsonArrayToSyntaxNode(),
            JsonObject      => JsonObjectToSyntaxNode(),
            JsonInsertion   => JsonInsertionToSyntaxLeaf(),
            JsonObjectEntry => CopyingProjection(),
            Vector{Cell}    => CopyingProjection(),
        )),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
