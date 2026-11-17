# The declaration of a view type: `@content_view` writes the field `viewed`, a child
# field for each list of the content, the constructor and the methods that make the
# type the view of its content type. A person writes only the state.

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

@testset "The declaration writes the field of the content and a field for each list" begin
    @test declared(ContentViewTestShelfView, 4) == (:viewed, :books, :collapsed, :zoom)
    @test !(:label in fieldnames(ContentViewTestShelfView)) && !(:note in fieldnames(ContentViewTestShelfView))
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
    @test over_given.books.given === given && over_given.books[2] === view.books[2]
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
    given = CellVector(Any[nothing, nothing])
    @test make_content_view(node, given).children.given === given
    @test node_view.collapsed == false
end

@testset "A declaration that names a field of the content again is an error" begin
    bad_viewed = :(@content_view ContentViewTestShelf struct ContentViewTestBadView <: ContentView
        viewed::Int = 1
    end)
    bad_list = :(@content_view ContentViewTestShelf struct ContentViewTestBadView <: ContentView
        books::Int = 1
    end)
    @test_throws Exception macroexpand(@__MODULE__, bad_viewed)
    @test_throws Exception macroexpand(@__MODULE__, bad_list)
end

end
end
