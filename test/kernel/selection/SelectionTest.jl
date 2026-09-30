"""
`SelectionModule` — the writers of the selection, over test-local documents.

Covers:
- `with_selection`, `set_selection!` and `clear_selection!` write and clear the
  path in each document along it,
- a path that does not match throws `SelectionMismatchException` and writes no cell,
- `replace_selection!` clears the branch that the new path leaves,
- a caret move in one leaf writes no `selection` cell of an ancestor,
- a keeper keeps the branch that the focus leaves as dormant, and a later write
  makes it live again,
- `map_selection_forward` carries the live or dormant state to the image,
- `@with_selection` builds a path typed against the document that it builds.
"""

using Test
using ProjecturedKernel.CellModule: Cell, @computation, is_cell_up_to_date
using ProjecturedKernel.DocumentModule: @document, SelectionDocument
using ProjecturedKernel.ReferenceModule: Reference, EmptyReference, FieldReferenceStep,
                                         MFieldReferenceStep, ElementReferenceStep,
                                         PositionReferenceStep,
                                         strip_reference_types, is_fully_typed_reference
using ProjecturedKernel.SelectionModule

@document struct SelectionLeaf
    text::String = ""
end

@document struct SelectionPair
    left::Any = nothing
    right::Any = nothing
end

# Holds its documents in a plain vector, so an index can go past the end.
@document struct SelectionList
    items::Vector{Any} = Any[]
end

# Keeps the selection of its page when the focus goes elsewhere.
@document struct SelectionKeeper
    page::Any = nothing
end
SelectionModule.has_dormant_selection(::SelectionKeeper) = true

function test_selection()
@testset "Selection" begin

    @testset "with_selection selects a path and answers the document" begin
        leaf = SelectionLeaf(text = "a")
        path = Reference(FieldReferenceStep("text"))
        @test with_selection(leaf, path) === leaf
        # The writer adds the node types to the path, so the test compares the
        # path without them.
        @test strip_reference_types(get_selection(leaf)) == path
    end

    @testset "clear_selection! clears the selection of a document" begin
        leaf = with_selection(SelectionLeaf(text = "a"),
                              Reference(FieldReferenceStep("text")))
        clear_selection!(leaf)
        @test get_selection(leaf) === nothing
    end

    @testset "clear_selection! clears each document on the path that it holds" begin
        root = SelectionPair(left = SelectionLeaf(text = "a"))
        deep = Reference(FieldReferenceStep("left"), FieldReferenceStep("text"))
        set_selection!(root, deep)
        @test strip_reference_types(get_selection(root)) == deep
        clear_selection!(root)
        @test get_selection(root) === nothing
        @test get_selection(root.left) === nothing
    end

    @testset "a path of M steps descends as a path of C steps" begin
        root = SelectionPair(left = SelectionLeaf(text = "a"))
        set_selection!(root, Reference(MFieldReferenceStep("left"),
                                       MFieldReferenceStep("text")))
        @test strip_reference_types(get_selection(root.left)) ==
              Reference(FieldReferenceStep("text"))
        clear_selection!(root)
        @test get_selection(root.left) === nothing
    end

    @testset "a path that does not match throws and writes no cell" begin
        root = SelectionPair(left = SelectionLeaf(text = "a"),
                             right = SelectionLeaf(text = "b"))
        set_selection!(root, Reference(FieldReferenceStep("left"),
                                       FieldReferenceStep("text")))
        before = getfield(root, :selection)[]
        before_left = getfield(root.left, :selection)[]

        missing_field = Reference(FieldReferenceStep("right"), FieldReferenceStep("none"))
        @test_throws SelectionMismatchException set_selection!(root, missing_field)
        @test_throws SelectionMismatchException replace_selection!(root, missing_field)
        @test getfield(root, :selection)[] === before
        @test getfield(root.left, :selection)[] === before_left
        @test getfield(root.right, :selection)[] === nothing

        list = SelectionList(items = Any[SelectionLeaf(text = "only")])
        past_end = Reference(FieldReferenceStep("items"), ElementReferenceStep(3))
        exception = try
            replace_selection!(list, past_end)
            nothing
        catch e
            e
        end
        @test exception isa SelectionMismatchException
        @test exception.document === list
        @test occursin("does not match", sprint(showerror, exception))
        @test get_selection(list) === nothing
    end

    @testset "replace_selection! clears the branch that the new path leaves" begin
        root = SelectionPair(left = SelectionLeaf(text = "a"),
                             right = SelectionLeaf(text = "b"))
        replace_selection!(root, Reference(FieldReferenceStep("left"),
                                           FieldReferenceStep("text")))
        @test strip_reference_types(get_selection(root.left)) ==
              Reference(FieldReferenceStep("text"))

        replace_selection!(root, Reference(FieldReferenceStep("right"),
                                           FieldReferenceStep("text")))
        @test get_selection(root.left) === nothing
        @test strip_reference_types(get_selection(root.right)) ==
              Reference(FieldReferenceStep("text"))
        @test strip_reference_types(get_selection(root)) ==
              Reference(FieldReferenceStep("right"), FieldReferenceStep("text"))

        replace_selection!(root, nothing)
        @test get_selection(root) === nothing
        @test get_selection(root.right) === nothing
    end

    @testset "a caret move in one leaf writes no selection cell of an ancestor" begin
        root = SelectionPair(left = SelectionLeaf(text = "abc"), right = nothing)
        replace_selection!(root, Reference(FieldReferenceStep("left"),
                                           FieldReferenceStep("text"),
                                           PositionReferenceStep(1)))
        root_reader = Cell(@computation getfield(root, :selection)[])
        leaf_reader = Cell(@computation getfield(root.left, :selection)[])
        root_reader[]
        leaf_reader[]

        replace_selection!(root, Reference(FieldReferenceStep("left"),
                                           FieldReferenceStep("text"),
                                           PositionReferenceStep(2)))
        @test is_cell_up_to_date(root_reader)
        @test !is_cell_up_to_date(leaf_reader)
        @test strip_reference_types(get_selection(root.left)) ==
              Reference(FieldReferenceStep("text"), PositionReferenceStep(2))
        @test strip_reference_types(get_selection(root)) ==
              Reference(FieldReferenceStep("left"), FieldReferenceStep("text"),
                        PositionReferenceStep(2))
    end

    @testset "a keeper keeps the branch dormant, and a later write makes it live" begin
        keeper = SelectionKeeper(page = SelectionLeaf(text = "a"))
        root = SelectionPair(left = keeper, right = SelectionLeaf(text = "b"))
        page_path = Reference(FieldReferenceStep("page"), FieldReferenceStep("text"))
        replace_selection!(root, Reference(FieldReferenceStep("left"),
                                           FieldReferenceStep("page"),
                                           FieldReferenceStep("text")))

        replace_selection!(root, Reference(FieldReferenceStep("right"),
                                           FieldReferenceStep("text")))
        @test get_selection(keeper) === nothing
        @test !is_live_selection(keeper)
        @test !is_live_selection(keeper.page)
        @test strip_reference_types(get_stored_selection(keeper)) == page_path
        @test getfield(keeper, :selection)[] isa SelectionDocument
        @test is_live_selection(root)

        # A write that ends on the keeper takes the dormant path back.
        replace_selection!(root, Reference(FieldReferenceStep("left")))
        @test is_live_selection(keeper)
        @test is_live_selection(keeper.page)
        @test strip_reference_types(get_selection(keeper)) == page_path
        @test strip_reference_types(get_selection(root)) ==
              Reference(FieldReferenceStep("left"), FieldReferenceStep("page"),
                        FieldReferenceStep("text"))
        @test get_selection(root.right) === nothing
    end

    @testset "map_selection_forward carries the live or dormant state" begin
        live = SelectionLeaf(text = "a")
        set_selection!(live, Reference(FieldReferenceStep("text")))
        @test map_selection_forward(live, path -> :image) === :image

        dormant = SelectionLeaf(text = "a")
        getfield(dormant, :selection)[] =
            SelectionDocument(; primary = Reference(FieldReferenceStep("text")),
                              live = false)
        image = map_selection_forward(dormant, path -> :image)
        @test image isa SelectionDocument
        @test !image.live
        @test image.primary === :image
        @test map_selection_forward(dormant, path -> nothing) === nothing

        # With no selection the map runs only when the caller asks for it.
        none = SelectionLeaf(text = "a")
        calls = Ref(0)
        @test map_selection_forward(none, path -> (calls[] += 1; :image)) === nothing
        @test calls[] == 0
        @test map_selection_forward(none, path -> (path, :image);
                                    map_missing = true) == (nothing, :image)
    end

    @testset "@with_selection builds a path typed against the new document" begin
        caret = @with_selection SelectionLeaf(text = "abc") text{1}
        @test caret isa SelectionLeaf
        path = get_selection(caret)
        @test is_fully_typed_reference(path)
        @test path.type === SelectionLeaf
        @test strip_reference_types(path) ==
              Reference(FieldReferenceStep("text"), PositionReferenceStep(1))

        whole = @with_selection SelectionLeaf(text = "abc")
        @test get_selection(whole) == EmptyReference(SelectionLeaf)
        @test_throws LoadError @eval @with_selection SelectionLeaf() text other
    end

end
end # test_selection
