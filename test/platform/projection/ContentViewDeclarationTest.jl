# The declaration of a view type: `@content_view` writes the field `viewed`, a child
# field for each list of the content and for each field that takes any document,
# the constructor and the methods that make the type the view of its content type.
# A person writes only the state.

# A content type with a plain field, a list and a field that takes a document.
@document struct ContentViewTestShelf <: Document
    label::String
    books::CellVector = CellVector()
    note::Union{Document, Nothing} = nothing
end

@content_view ContentViewTestShelf struct ContentViewTestShelfView <: ContentView
    collapsed::Bool = false
    zoom::Int = 1
end

function test_content_view_declaration()
@testset "The declaration of a view type" begin

leaf(s) = SyntaxLeaf(TextString(s))
shelf = ContentViewTestShelf("novels", CellVector(Document[leaf("a"), leaf("b")]))
view = ContentViewTestShelfView(shelf)
declared(T, count) = fieldnames(T)[1:count]

@testset "The declaration writes the field of the content and a field for each child" begin
    @test declared(ContentViewTestShelfView, 5) == (:viewed, :books, :note, :collapsed, :zoom)
    @test !(:label in fieldnames(ContentViewTestShelfView))
    @test ContentViewTestShelfView <: ContentView
    @test view.viewed === shelf
    @test view.books isa CellVectorView && view.books.viewed === shelf.books
    @test view.collapsed == false && view.zoom == 1
    @test view.books[2] isa SyntaxLeafView && view.books[2].viewed === shelf.books[2]
end

@testset "The view of a list follows the field of the content" begin
    other = ContentViewTestShelf("essays", CellVector(Document[leaf("c")]))
    other_view = ContentViewTestShelfView(other)
    first_list = other.books
    other.books = CellVector(Document[leaf("d"), leaf("e"), leaf("f")])
    @test other.books !== first_list
    @test other_view.books.viewed === other.books && length(other_view.books) == 3
end

@testset "The declaration makes the type the view of its content type" begin
    made = make_content_view(shelf)
    @test made isa ContentViewTestShelfView && made.viewed === shelf && made !== view
    given = CellVector(Any[nothing, view.books[2]])
    over_given = make_content_view(shelf, given)
    @test over_given isa ContentViewTestShelfView && over_given.viewed === shelf
    @test over_given.books[1] === nothing && over_given.books[2] === view.books[2]
    @test over_given.note === nothing
    # A given view is at the index of its content, at any place of the given list.
    turned = make_content_view(shelf, CellVector(Any[view.books[2], view.books[1]]))
    @test turned.books[1] === view.books[1] && turned.books[2] === view.books[2]
    @test length(make_content_view(shelf, CellVector(Any[view.books[2]])).books) == 2
end

@testset "The child field of a field that takes any document holds the view of that document" begin
    desk = ContentViewTestShelf("desk")
    desk_view = ContentViewTestShelfView(desk)
    # An empty field has no view.
    @test desk_view.note === nothing
    first_note = leaf("n")
    desk.note = first_note
    note_view = desk_view.note
    @test note_view isa SyntaxLeafView && note_view.viewed === first_note
    # The same document has the same view at each read.
    @test desk_view.note === note_view
    # The step of the field reaches the view, and a caret into the document is on it.
    path = strip_reference_types(@reference(desk_view, note.value{1}))
    @test try_evaluate_reference(desk_view, Reference(FieldReferenceStep("note")), nothing) === note_view
    replace_selection!(desk_view, path)
    @test strip_reference_types(get_stored_selection(note_view)) ==
          strip_reference_types(@reference(note_view, value{1}))
    @test get_stored_selection(first_note) === nothing
    # Another document in the field has another view.
    second_note = SyntaxNode([leaf("x"), leaf("y")])
    desk.note = second_note
    @test desk_view.note isa SyntaxNodeView && desk_view.note.viewed === second_note
    @test desk_view.note !== note_view
    # A document that has no view type has no view.
    desk.note = TextString("plain")
    @test desk_view.note === nothing
    desk.note = nothing
    @test desk_view.note === nothing
end

@testset "A second view copies the state of the view in the field, and shares no view" begin
    node = SyntaxNode([leaf("x"), leaf("y")])
    desk = ContentViewTestShelf("desk", CellVector(Document[leaf("a")]), node)
    desk_view = ContentViewTestShelfView(desk)
    desk_view.note.collapsed = true
    desk_view.zoom = 3
    sibling = make_sibling_view(desk_view)
    @test sibling isa ContentViewTestShelfView && sibling !== desk_view && sibling.viewed === desk
    @test sibling.note isa SyntaxNodeView && sibling.note !== desk_view.note && sibling.note.viewed === node
    @test sibling.note.collapsed && sibling.zoom == 3
    sibling.note.collapsed = false
    @test desk_view.note.collapsed
    # An empty field stays a field that follows the content.
    empty_desk = ContentViewTestShelf("empty")
    empty_sibling = make_sibling_view(ContentViewTestShelfView(empty_desk))
    @test empty_sibling.note === nothing
    empty_desk.note = leaf("late")
    @test empty_sibling.note isa SyntaxLeafView
    # A copy of a view is a view of a copy of the content, with the state of the view.
    copy = copy_document(desk_view)
    @test copy.viewed !== desk && copy.note isa SyntaxNodeView && copy.note.viewed === copy.viewed.note
    @test copy.note.viewed !== node && copy.note.collapsed
end

@testset "The view types of the text and of the syntax take the declaration" begin
    block = TextBlock(TextLine(TextString("alpha")))
    @test declared(TextView, 4) == (:viewed, :wrap, :line_spacing, :closed_folds)
    @test !(:elements in fieldnames(TextView))
    @test make_content_view(block) isa TextView && make_content_view(block).viewed === block
    @test TextView(block).wrap == false && TextView(block, true).wrap == true

    first_leaf = leaf("a")
    @test declared(SyntaxLeafView, 1) == (:viewed,)
    @test isempty(intersect(fieldnames(SyntaxLeafView), (:open, :close, :value)))
    @test make_content_view(first_leaf) isa SyntaxLeafView && make_content_view(first_leaf).viewed === first_leaf

    node = SyntaxNode([first_leaf, leaf("b")])
    node_view = SyntaxNodeView(node)
    @test declared(SyntaxNodeView, 3) == (:viewed, :children, :collapsed)
    @test isempty(intersect(fieldnames(SyntaxNodeView), (:open, :close, :sep)))
    @test node_view.children isa CellVectorView && node_view.children.viewed === node.children
    @test make_content_view(node) isa SyntaxNodeView
    given = CellVector(Any[nothing, node_view.children[2]])
    over_given = make_content_view(node, given)
    @test over_given.children[1] === nothing && over_given.children[2] === node_view.children[2]
    @test node_view.collapsed == false
end

@testset "A declaration that names a field of the content again is an error" begin
    bad_viewed = :(@content_view ContentViewTestShelf struct ContentViewTestBadView <: ContentView
        viewed::Int = 1
    end)
    bad_list = :(@content_view ContentViewTestShelf struct ContentViewTestBadView <: ContentView
        books::Int = 1
    end)
    bad_slot = :(@content_view ContentViewTestShelf struct ContentViewTestBadView <: ContentView
        note::Int = 1
    end)
    @test_throws Exception macroexpand(@__MODULE__, bad_viewed)
    @test_throws Exception macroexpand(@__MODULE__, bad_list)
    @test_throws Exception macroexpand(@__MODULE__, bad_slot)
end

end
end
