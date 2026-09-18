# An UndoBuffer over a small JSON object. The buffer draws nothing of its own, so
# the document looks exactly like the plain JSON example; what it adds is a
# history. Every edit through the projection is recorded, Ctrl+Z takes one back
# and Ctrl+Y puts it back. See make_undo_projection_example for the keys.
function make_undo_document_example()
    UndoBuffer(
        JsonObject(
            "title"  => JsonString("Undo"),
            "status" => JsonString("draft"),
            "views"  => JsonNumber(7),
        ))
end
