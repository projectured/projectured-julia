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

# The same document with a history already in it: two changes made and one taken
# back, so the panel has a line above the marker and two below it. The entries are
# made the way every entry is made — by applying a recorded operation — rather
# than built by hand, so the example shows what the mechanism produces.
function make_undo_history_document_example()
    buffer = make_undo_document_example()
    editor = (document = buffer,)
    # The path a reader would answer, so the history reads the way it reads when a
    # person types: `set .content.entries[2].value.value = "published"`.
    record(index, text) = RecordUndoOperation(buffer,
        ReplaceReferencedValueOperation(nothing,
            Reference(FieldReferenceStep("content"), FieldReferenceStep("entries"),
                      ElementReferenceStep(index), FieldReferenceStep("value"),
                      FieldReferenceStep("value")),
            text))
    evaluate_operation(editor, record(2, "published"))
    evaluate_operation(editor, record(1, "reviewed"))
    evaluate_operation(editor, UndoOperation(buffer))
    buffer
end
