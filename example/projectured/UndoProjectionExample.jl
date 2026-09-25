# Projects an UndoBuffer down to graphics. The undo projection sits at the top of
# the recursion: it prints the document the buffer holds and answers that output,
# so the buffer is invisible, and the same dispatcher turns that JSON into a
# syntax tree. SyntaxToText then TextToGraphics finish the pipeline, exactly as
# the plain JSON example does.
#
# What the buffer adds is on the way back: every operation the JSON reader makes
# comes back through the buffer, which wraps it so that applying it also records
# the way back.
#
# Gestures owned by the undo projection (the rest fall through to JSON):
#   Ctrl+Z           take the last change back
#   Ctrl+Y           put it back
#   Ctrl+Shift+Z     put it back
function make_undo_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            UndoBuffer      => UndoBufferToAnyProjection(),
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

# Draws the history of an UndoBuffer rather than the document it holds: one line
# per step, newest at the top, with a marker for where the document stands now.
# It is the other half of the pair — `make_undo_projection_example` draws the
# document and the buffer is invisible; this one draws the buffer itself.
function make_undo_history_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        UndoBufferToSyntax(),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
