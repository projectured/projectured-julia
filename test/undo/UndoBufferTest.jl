"""
`UndoModule` — the buffer, the three operations and the transparent projection.

Every case is one round trip: make a change through the buffer, take it back,
and the document is what it was. The content projection is the identity, so
what is under test is the buffer and the operations, not a chain.
"""

@document struct UndoLeaf
    value::String
end

@document struct UndoList
    items::CellVector
end

# A list of leaves. It is a function and not another constructor, because the
# document macro already emits one that takes a vector.
_make_list(values) =
    UndoList(CellVector(Cell[Cell(UndoLeaf(v, nothing)) for v in values]), nothing)

# The editor an operation is applied against: whatever object holds the document.
mutable struct _UndoEditor
    document::Any
end

_texts(list::UndoList) = [item.value for item in list.items]

# A write into the first element of the list the buffer holds, in the content's
# own frame — the frame the reader of the content answers in.
_write_first(text) = ReplaceReferencedValueOperation(nothing,
    Reference(FieldReferenceStep("items"), RangeReferenceStep(0, 1), FieldReferenceStep("value")),
    text)

function test_undo_buffer()
@testset "UndoBuffer" begin

    ctrl = ModifierKeys(ctrl = true)
    ctrl_shift = ModifierKeys(ctrl = true, shift = true)

    @testset "the history is bounded, and an edit forgets what could be redone" begin
        buffer = UndoBuffer(_make_list(["a"]); capacity = 2)
        push_undo_entry!(buffer, UndoEntry("one", DoNothingOperation(), nothing))
        push_undo_entry!(buffer, UndoEntry("two", DoNothingOperation(), nothing))
        push_undo_entry!(buffer, UndoEntry("three", DoNothingOperation(), nothing))
        @test [entry.label for entry in buffer.undo_entries] == ["two", "three"]

        push!(buffer.redo_entries, UndoEntry("gone", DoNothingOperation(), nothing))
        push_undo_entry!(buffer, UndoEntry("four", DoNothingOperation(), nothing))
        @test length(buffer.redo_entries) == 0

        clear_undo_history!(buffer)
        @test length(buffer.undo_entries) == 0
        @test length(buffer.redo_entries) == 0
    end

    @testset "the default filter drops what changes nothing and a bare caret move" begin
        @test !is_undo_step(nothing, nothing)
        @test !is_undo_step(nothing, DoNothingOperation())
        @test !is_undo_step(nothing, ReplaceSelectionOperation(EmptyReference()))
        @test is_undo_step(nothing, _write_first("x"))
        # A compound that carries a write is kept: only a bare caret move matches.
        @test is_undo_step(nothing, CompoundOperation(Any[_write_first("x"),
                                                          ReplaceSelectionOperation(EmptyReference())]))
    end

    @testset "an entry with no way back is a barrier" begin
        @test is_undo_barrier(UndoEntry("opaque", nothing, nothing))
        @test !is_undo_barrier(UndoEntry("plain", DoNothingOperation(), nothing))
    end

    @testset "the printer answers the content's output and the buffer vanishes" begin
        list = _make_list(["a", "b"])
        buffer = UndoBuffer(list)
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        @test iomap.output === list
        @test iomap.content_iomap.input === list
    end

    @testset "a reference gains the content step going back and loses it going forward" begin
        buffer = UndoBuffer(_make_list(["a"]))
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        inner = Reference(FieldReferenceStep("items"), RangeReferenceStep(0, 1))
        back = map_reference_backward(projection, iomap, inner)
        @test get_reference_steps(back)[1] == FieldReferenceStep("content")
        @test map_reference_forward(projection, iomap, back) == inner
        # A path that does not go through the content has no pre-image.
        @test map_reference_forward(projection, iomap,
                  Reference(FieldReferenceStep("undo_entries"))) === nothing
    end

    @testset "an edit through the buffer is recorded, taken back and put back" begin
        list = _make_list(["a", "b"])
        buffer = UndoBuffer(list)
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        editor = _UndoEditor(buffer)

        operation = read_intent(projection, iomap, _write_first("changed"))
        @test operation isa RecordUndoOperation
        # The recorded operation is rooted at the buffer, not at the content.
        @test get_reference_steps(get_wrapped_operation(operation).reference)[1] ==
              FieldReferenceStep("content")

        evaluate_operation(editor, operation)
        @test _texts(list) == ["changed", "b"]
        @test length(buffer.undo_entries) == 1
        @test buffer.undo_entries[1].label == "set .content.items[1].value = \"changed\""

        evaluate_operation(editor, UndoOperation(buffer))
        @test _texts(list) == ["a", "b"]
        @test length(buffer.undo_entries) == 0
        @test length(buffer.redo_entries) == 1

        evaluate_operation(editor, RedoOperation(buffer))
        @test _texts(list) == ["changed", "b"]
        @test length(buffer.undo_entries) == 1
        @test length(buffer.redo_entries) == 0
    end

    @testset "a delete is taken back with the element it removed, and the same cell" begin
        list = _make_list(["a", "b", "c"])
        buffer = UndoBuffer(list)
        editor = _UndoEditor(buffer)
        cell = get_cell_at(list.items, 2)
        operation = RecordUndoOperation(buffer,
            delete_elements(Reference(FieldReferenceStep("content"), FieldReferenceStep("items")), 1))
        evaluate_operation(editor, operation)
        @test _texts(list) == ["a", "c"]
        evaluate_operation(editor, UndoOperation(buffer))
        @test _texts(list) == ["a", "b", "c"]
        # The element comes back in the cell it left, so whatever followed that
        # cell follows it still.
        @test get_cell_at(list.items, 2) === cell
    end

    # An entry names the object it writes into, not a path from the editor's
    # root, so it still applies after the buffer has moved somewhere else in the
    # tree — a tab dragged to another pane, a pane split.
    @testset "an entry survives the buffer moving in the tree" begin
        list = _make_list(["a", "b"])
        buffer = UndoBuffer(list)
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        evaluate_operation(_UndoEditor(buffer),
                           read_intent(projection, iomap, _write_first("changed")))
        @test _texts(list) == ["changed", "b"]
        # An editor whose document is another tree entirely takes the step back.
        evaluate_operation(_UndoEditor(UndoLeaf("elsewhere", nothing)), UndoOperation(buffer))
        @test _texts(list) == ["a", "b"]
    end

    @testset "an operation the filter drops is passed on unrecorded" begin
        buffer = UndoBuffer(_make_list(["a"]))
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        operation = read_intent(projection, iomap, ReplaceSelectionOperation(EmptyReference()))
        @test operation isa ReplaceSelectionOperation
        @test !(operation isa RecordUndoOperation)
    end

    @testset "a filter of its own decides instead" begin
        buffer = UndoBuffer(_make_list(["a"]))
        projection = UndoBufferToAnyProjection(filter = (gesture, operation) -> false)
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        @test !(read_intent(projection, iomap, _write_first("x")) isa RecordUndoOperation)
    end

    @testset "Ctrl+Z answers only when there is something to take back" begin
        list = _make_list(["a"])
        buffer = UndoBuffer(list)
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        editor = _UndoEditor(buffer)

        # Nothing recorded yet: the key is not swallowed.
        @test !(read_intent(projection, iomap, KeyDown(:z, ctrl)) isa UndoOperation)

        evaluate_operation(editor, read_intent(projection, iomap, _write_first("changed")))
        undo = read_intent(projection, iomap, KeyDown(:z, ctrl))
        @test undo isa UndoOperation
        @test undo.buffer === buffer

        evaluate_operation(editor, undo)
        @test _texts(list) == ["a"]
        @test read_intent(projection, iomap, KeyDown(:y, ctrl)) isa RedoOperation
        @test read_intent(projection, iomap, KeyDown(:z, ctrl_shift)) isa RedoOperation
    end

    @testset "a barrier stops the way back" begin
        list = _make_list(["a"])
        buffer = UndoBuffer(list)
        editor = _UndoEditor(buffer)
        push_undo_entry!(buffer, UndoEntry("opaque", nothing, nothing))
        evaluate_operation(editor, UndoOperation(buffer))
        # The entry stays where it is, and nothing was put on the other list.
        @test length(buffer.undo_entries) == 1
        @test length(buffer.redo_entries) == 0
    end

    @testset "an operation nobody can invert is recorded as a barrier" begin
        list = _make_list(["a"])
        buffer = UndoBuffer(list)
        editor = _UndoEditor(buffer)
        # `SelectNextInsertionOperation` carries a predicate and no reference, and
        # a root that is not a Document leaves it with nothing to do; what matters
        # here is an operation whose inverse the kernel does not know.
        evaluate_operation(editor, RecordUndoOperation(buffer, ToggleCollapseOperation()))
        @test length(buffer.undo_entries) == 1
        @test is_undo_barrier(buffer.undo_entries[1])
    end

    @testset "the caret goes back to where the edit was" begin
        list = _make_list(["abc", "def"])
        buffer = UndoBuffer(list)
        editor = _UndoEditor(buffer)
        before = Reference(FieldReferenceStep("content"), FieldReferenceStep("items"),
                           RangeReferenceStep(0, 1), FieldReferenceStep("value"),
                           RangeReferenceStep(1, 1))
        replace_selection!(buffer, before)
        evaluate_operation(editor, RecordUndoOperation(buffer,
            ReplaceReferencedValueOperation(nothing,
                Reference(FieldReferenceStep("content"), FieldReferenceStep("items"),
                          RangeReferenceStep(1, 2), FieldReferenceStep("value")),
                "changed")))
        # Move the caret away, then undo: it comes back to the edit.
        replace_selection!(buffer, Reference(FieldReferenceStep("content"),
                                             FieldReferenceStep("items"),
                                             RangeReferenceStep(1, 2),
                                             FieldReferenceStep("value"),
                                             RangeReferenceStep(0, 0)))
        evaluate_operation(editor, UndoOperation(buffer))
        @test get_reference_steps(strip_reference_types(get_selection(buffer))) ==
              get_reference_steps(before)
    end

    # Two buffers on one path. The inner one answers the key, and the outer one
    # records that it did — so an outer undo asks the inner buffer to redo rather
    # than repeating its work.
    @testset "the inner buffer answers, and the outer records that it did" begin
        list = _make_list(["a"])
        inner = UndoBuffer(list)
        outer = UndoBuffer(inner)
        projection = UndoBufferToAnyProjection()
        # The outer projection prints the inner buffer through the inner
        # projection, which prints the list through the identity.
        inner_iomap = print_document(projection, IdentityProjection(), inner, PrinterContext())
        outer_iomap = UndoBufferToAnyIoMap(projection, outer,
                                           ComputedCell(() -> inner_iomap.output), inner_iomap)
        editor = _UndoEditor(outer)

        operation = read_intent(projection, outer_iomap, _write_first("changed"))
        @test operation isa RecordUndoOperation
        @test operation.buffer === outer
        @test get_wrapped_operation(operation) isa RecordUndoOperation
        @test get_wrapped_operation(operation).buffer === inner

        evaluate_operation(editor, operation)
        @test _texts(list) == ["changed"]
        @test length(inner.undo_entries) == 1
        @test length(outer.undo_entries) == 1

        # The outer step's way back is the inner buffer's undo, so taking it back
        # leaves the inner buffer's own two lists right.
        evaluate_operation(editor, UndoOperation(outer))
        @test _texts(list) == ["a"]
        @test length(inner.undo_entries) == 0
        @test length(inner.redo_entries) == 1
        @test length(outer.redo_entries) == 1

        # And the way back from that is the inner buffer's redo.
        evaluate_operation(editor, RedoOperation(outer))
        @test _texts(list) == ["changed"]
        @test length(inner.undo_entries) == 1
        @test length(inner.redo_entries) == 0
    end

    @testset "an undo inside is an edit outside" begin
        list = _make_list(["a"])
        inner = UndoBuffer(list)
        outer = UndoBuffer(inner)
        projection = UndoBufferToAnyProjection()
        inner_iomap = print_document(projection, IdentityProjection(), inner, PrinterContext())
        outer_iomap = UndoBufferToAnyIoMap(projection, outer,
                                           ComputedCell(() -> inner_iomap.output), inner_iomap)
        editor = _UndoEditor(outer)
        evaluate_operation(editor, read_intent(projection, outer_iomap, _write_first("changed")))

        # Ctrl+Z reaches the inner buffer, and the outer records the undo.
        undo = read_intent(projection, outer_iomap, KeyDown(:z, ctrl))
        @test undo isa RecordUndoOperation
        @test undo.buffer === outer
        @test get_wrapped_operation(undo) isa UndoOperation
        @test get_wrapped_operation(undo).buffer === inner

        evaluate_operation(editor, undo)
        @test _texts(list) == ["a"]
        @test length(outer.undo_entries) == 2
    end

    @testset "a buffer never records its own undo" begin
        list = _make_list(["a"])
        buffer = UndoBuffer(list)
        projection = UndoBufferToAnyProjection()
        iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
        editor = _UndoEditor(buffer)
        evaluate_operation(editor, read_intent(projection, iomap, _write_first("changed")))
        evaluate_operation(editor, read_intent(projection, iomap, KeyDown(:z, ctrl)))
        @test length(buffer.undo_entries) == 0
    end

    @testset "make_undoable_operation records a change from outside the reader" begin
        list = _make_list(["a"])
        buffer = UndoBuffer(list)
        editor = _UndoEditor(buffer)
        operation = make_undoable_operation(buffer,
            ReplaceReferencedValueOperation(nothing,
                Reference(FieldReferenceStep("content"), FieldReferenceStep("items"),
                          RangeReferenceStep(0, 1), FieldReferenceStep("value")),
                "changed"))
        @test operation isa RecordUndoOperation
        evaluate_operation(editor, operation)
        @test _texts(list) == ["changed"]
        evaluate_operation(editor, UndoOperation(buffer))
        @test _texts(list) == ["a"]
        @test make_undoable_operation(buffer, nothing) === nothing
    end

end
end # test_undo_buffer
