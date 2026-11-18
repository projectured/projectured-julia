# An edit through a view writes the content. `make_content_edit` takes a write at a
# path of the tree of views, and gives the write below the field `viewed` of the
# deepest view above the written place. The content type and its view type are
# those of the test of the declaration.

function test_content_edit()
@testset "An edit through a view writes the content" begin

leaf(s) = SyntaxLeaf(TextString(s))
inner = SyntaxNode([leaf("x"), leaf("y")])
shelf = ContentViewTestShelf("novels", CellVector(Document[leaf("a"), inner]), leaf("n"))
view = ContentViewTestShelfView(shelf)
editor = (; document = view)
plain(path) = strip_reference_types(path)
write_at(path, value) = ReplaceReferencedValueOperation(nothing, plain(path), value)

@testset "A write of an element goes to the list of the content" begin
    new_leaf = leaf("b")
    edit = make_content_edit(view, write_at(@reference(view, books[1]), new_leaf))
    @test edit isa ReplaceReferencedValueOperation
    @test plain(edit.reference) == plain(@reference(view, books.viewed[1]))
    evaluate_operation(editor, edit)
    @test shelf.books[1] === new_leaf && view.books[1].viewed === new_leaf
    @test length(shelf.books) == 2 && view.books isa CellVectorView
end

@testset "A write below the view of a child goes to the content of that view" begin
    new_leaf = leaf("z")
    edit = make_content_edit(view, write_at(@reference(view, books[2].children[1]), new_leaf))
    @test plain(edit.reference) == plain(@reference(view, books[2].children.viewed[1]))
    evaluate_operation(editor, edit)
    @test inner.children[1] === new_leaf && view.books[2].children[1].viewed === new_leaf
end

@testset "A write of a field that takes a document goes to the content" begin
    new_note = leaf("m")
    edit = make_content_edit(view, write_at(@reference(view, note), new_note))
    @test plain(edit.reference) == Reference(FieldReferenceStep("viewed"), FieldReferenceStep("note"))
    evaluate_operation(editor, edit)
    @test shelf.note === new_note && view.note.viewed === new_note
end

@testset "A write of a plain field of the content goes to the content" begin
    edit = make_content_edit(view, write_at(Reference(FieldReferenceStep("label")), "essays"))
    @test plain(edit.reference) == Reference(FieldReferenceStep("viewed"), FieldReferenceStep("label"))
    evaluate_operation(editor, edit)
    @test shelf.label == "essays"
end

@testset "A write of a field of state of a view stays a write of the view" begin
    own = write_at(Reference(FieldReferenceStep("zoom")), 4)
    @test make_content_edit(view, own) === own
    below = write_at(@reference(view, books[2].collapsed), true)
    @test make_content_edit(view, below) === below
    evaluate_operation(editor, below)
    @test view.books[2].collapsed && !inner.collapsed
end

@testset "A write of the content of the view itself has no place" begin
    whole = write_at(EmptyReference(), leaf("w"))
    @test make_content_edit(view, whole) === nothing
    @test make_content_edit(view, CompoundOperation(Any[whole, ReplaceSelectionOperation(EmptyReference())])) === nothing
end

@testset "A path that names a place of a content stays" begin
    already = write_at(@reference(view, books.viewed[1]), leaf("c"))
    @test make_content_edit(view, already) === already
end

@testset "A write of a carried document stays" begin
    carried = ReplaceReferencedValueOperation(shelf, "label", "poems")
    @test make_content_edit(view, carried) === carried
end

@testset "A replace keeps its caret on the views, and the new content holds none" begin
    new_leaf = leaf("kept")
    set_selection!(new_leaf, plain(@reference(new_leaf, value{1})))
    replace = make_replace_document_operation(plain(@reference(view, books[1])), new_leaf)
    edit = make_content_edit(view, replace)
    @test edit isa CompoundOperation && length(edit.operations) == 2
    @test plain(edit.operations[1].reference) == plain(@reference(view, books.viewed[1]))
    @test edit.operations[2] isa ReplaceSelectionOperation
    @test get_stored_selection(new_leaf) === nothing
    evaluate_operation(editor, edit)
    @test shelf.books[1] === new_leaf
    @test plain(get_stored_selection(view.books[1])) == plain(@reference(view.books[1], value{1}))
    @test get_stored_selection(new_leaf) === nothing
end

@testset "A wrapped operation and a list of rows take the edit of each member" begin
    wrapped = make_content_edit(view, ShowSelectionOperation(write_at(@reference(view, books[1]), leaf("s"))))
    @test wrapped isa ShowSelectionOperation
    @test plain(get_wrapped_operation(wrapped).reference) == plain(@reference(view, books.viewed[1]))
    rows = CollectedIntentsOperation(Intent[
        Intent(nothing, write_at(@reference(view, books[1]), leaf("r")), "a row with a place", "test"),
        Intent(nothing, write_at(EmptyReference(), leaf("q")), "a row with no place", "test"),
        Intent(nothing, nothing, "a row that can not act now", "test"),
    ])
    listed = make_content_edit(view, rows)
    @test listed isa CollectedIntentsOperation
    @test [intent.description for intent in listed.intents] == ["a row with a place", "a row that can not act now"]
    @test plain(listed.intents[1].operation.reference) == plain(@reference(view, books.viewed[1]))
end

@testset "A write of the next stage comes back as a write of the printed content" begin
    path = plain(@reference(view, books[2].children[2]))
    edit = make_content_edit(view, write_at(path, leaf("t")))
    back = ProjectionAlgebraModule._make_printed_edit(view, edit)
    @test plain(back.reference) == path
    untouched = write_at(path, leaf("u"))
    @test ProjectionAlgebraModule._make_printed_edit(view, untouched) === untouched
end

end
end
