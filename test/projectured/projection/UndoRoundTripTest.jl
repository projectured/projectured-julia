# The property every inverse must have: apply a change, take it back, and the
# document is what it was.
#
# It runs the whole reader battery against the undo example — a real JSON
# document inside an `UndoBuffer`, through the real chain — so every gesture that
# produces a recorded change is one case. A gesture the reader declines, and one
# the filter drops, are skipped: neither makes an entry.
#
# The document is compared as **text**, through a snapshot chain that ends in
# `TextToString`. A printed graphics tree carries sizes and identities that say
# nothing about whether the value came back, and a text rendering says exactly
# that and reads well in a failure message.

# The snapshot chain: the same first two stages the example uses, ending in a
# string instead of graphics.
function _make_undo_snapshot_projection()
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
        RecursiveProjection(TextToString()),
    )
end

function _undo_snapshot(buffer, projection)
    output = print_document(projection, buffer).output
    string(output isa AbstractCell ? output[] : output)
end

# The editor an operation is applied against. A whole-root swap rebinds
# `document`, so the caller re-reads it.
mutable struct _UndoRoundTripEditor
    document::Any
    iomap::Any
end

"""
    test_undo_round_trip()

Every gesture that makes a recorded change is taken back, and the document
returns to the text it had.
"""
function test_undo_round_trip()
@testset "Undo round trip" begin
    snapshot_projection = _make_undo_snapshot_projection()
    # Where the caret is decides what a key means, so the battery runs from
    # several places in the document rather than from one. The paths come from a
    # template and are re-used, because every case builds the same document afresh.
    places = collect_position_selections(make_undo_document_example())
    sample = places[1:max(1, cld(length(places), 12)):end]

    for place in sample, event in _ALL_READER_EVENTS
        # A fresh document per case: a sweep that shares one document tests the
        # state the sweep before it left, not the gesture in hand.
        buffer = make_undo_document_example()
        projection = make_undo_projection_example()
        try
            replace_selection!(buffer, place)
        catch
            continue    # a path this document does not match: not a case
        end
        iomap = print_document(projection, buffer)
        before = _undo_snapshot(buffer, snapshot_projection)

        operation = try
            read_intent(projection, iomap, event)
        catch exception
            @test false
            @warn "read_intent threw for $event at $place: $exception"
            continue
        end
        # Only a recorded change is a case. Everything else makes no entry, so
        # there is nothing to take back and nothing to assert.
        operation isa RecordUndoOperation || continue

        editor = _UndoRoundTripEditor(buffer, iomap)
        evaluate_operation(editor, operation)
        buffer = editor.document
        # A step nobody could invert is a barrier, and a barrier stops the
        # history rather than lying about it. Say which gesture, so a missing
        # inverse is visible rather than silently skipped.
        entry = buffer.undo_entries[end]
        if is_undo_barrier(entry)
            @warn "no way back from $event: $(entry.label)"
            @test_broken false
            continue
        end
        evaluate_operation(editor, UndoOperation(buffer))
        after = _undo_snapshot(editor.document, snapshot_projection)
        after == before || @warn "$event at $place: $(repr(before)) became $(repr(after))"
        @test after == before
    end
end
end # test_undo_round_trip
