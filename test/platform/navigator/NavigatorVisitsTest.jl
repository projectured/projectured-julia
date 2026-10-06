# The visits of a navigator: open, Back, Forward and Parent, the selection that
# each puts into its page, the page of an address that an edit removed, and the
# undo that records none of them. Each operation is evaluated against a holder of
# the navigator, as the editor evaluates it.

@document struct NavigatorTestChapter
    title::String
end

@document struct NavigatorTestBook
    title::String
    chapters::CellVector
end

# Another kind of part with the fields of a book.
@document struct NavigatorTestVolume
    title::String
    chapters::CellVector
end

@document struct NavigatorTestShelf
    title::String
    books::CellVector
end

ProjecturedKernel.DocumentModule.get_document_title(x::NavigatorTestChapter) = x.title
ProjecturedKernel.DocumentModule.get_document_title(x::NavigatorTestBook) = x.title
ProjecturedKernel.DocumentModule.get_document_title(x::NavigatorTestShelf) = x.title

_nav_vector(elements) = CellVector(Cell[Cell(element) for element in elements])

# A shelf of two books: "A" with the chapters "A1" and "A2", "B" with "B1".
_nav_make_shelf() =
    NavigatorTestShelf("Shelf", _nav_vector([
        NavigatorTestBook("A", _nav_vector([NavigatorTestChapter("A1", nothing),
                                            NavigatorTestChapter("A2", nothing)]), nothing),
        NavigatorTestBook("B", _nav_vector([NavigatorTestChapter("B1", nothing)]), nothing)]),
        nothing)

# What an operation is evaluated against: an object that holds the document.
mutable struct _NavHolder
    document::Any
end

function _nav_apply!(holder, operation)
    @test operation !== nothing
    evaluate_operation(holder, operation)
end

_nav_steps(reference) = get_reference_steps(strip_reference_types(reference))
_nav_is(reference, expected) = reference !== nothing && _nav_steps(reference) == _nav_steps(expected)

function test_navigator_visits()
@testset "Navigator visits" begin

    @testset "a new navigator shows the whole content" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        @test get_navigator_page_address(navigator) isa EmptyReference
        @test get_navigator_page(navigator) === shelf
        @test isempty(navigator.back) && isempty(navigator.forward)
        @test find_navigator_parent_address(navigator) === nothing
        @test make_navigator_parent_operation(navigator) === nothing
        @test make_navigator_back_operation(navigator) === nothing
        @test make_navigator_forward_operation(navigator) === nothing
        @test get_document_title(navigator) == "Shelf"
    end

    @testset "open, Back and Forward" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[2])))
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        @test get_navigator_page(navigator) === shelf.books[2]
        @test get_document_title(navigator) == "B"
        @test length(navigator.back) == 1 && isempty(navigator.forward)
        @test _nav_is(navigator.selection, @reference(navigator, content.books[2]))
        # An open of the page that the navigator shows makes no visit.
        @test make_navigator_open_operation(navigator, @reference(shelf, books[2])) === nothing

        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[2].chapters[1])))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test length(navigator.back) == 2

        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        @test length(navigator.back) == 1 && length(navigator.forward) == 1
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test navigator.address isa EmptyReference
        @test isempty(navigator.back) && length(navigator.forward) == 2
        @test make_navigator_back_operation(navigator) === nothing

        _nav_apply!(holder, make_navigator_forward_operation(navigator))
        _nav_apply!(holder, make_navigator_forward_operation(navigator))
        @test _nav_is(navigator.address, @reference(shelf, books[2].chapters[1]))
        @test length(navigator.back) == 2 && isempty(navigator.forward)

        # An open after Back clears the forward list, as in a browser.
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[1])))
        @test isempty(navigator.forward)
        @test length(navigator.back) == 2
    end

    @testset "Back puts back the selection that the page had" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        holder = _NavHolder(navigator)
        # The person selects the second book on the shelf and opens it.
        replace_selection!(navigator, @reference(navigator, content.books[2].title))
        @test _nav_is(find_navigator_selected_address(navigator), @reference(shelf, books[2]))
        _nav_apply!(holder, make_navigator_open_operation(navigator,
                                                         find_navigator_selected_address(navigator)))
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        @test _nav_is(navigator.back[end].selection, @reference(shelf, books[2].title))
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test _nav_is(navigator.selection, @reference(navigator, content.books[2].title))
    end

    @testset "the selected part" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1]))
        # No selection, or a selection outside the page, opens nothing.
        @test find_navigator_selected_address(navigator) === nothing
        replace_selection!(navigator, @reference(navigator, content.books[2].title))
        @test find_navigator_selected_address(navigator) === nothing
        # The page itself is not a part below the page.
        replace_selection!(navigator, @reference(navigator, content.books[1]))
        @test find_navigator_selected_address(navigator) === nothing
        # The innermost document on the selection, past the collection.
        replace_selection!(navigator, @reference(navigator, content.books[1].chapters[2].title))
        @test _nav_is(find_navigator_selected_address(navigator), @reference(shelf, books[1].chapters[2]))
    end

    @testset "Parent skips a collection and selects the page that it leaves" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1].chapters[2]))
        holder = _NavHolder(navigator)
        @test _nav_is(find_navigator_parent_address(navigator), @reference(shelf, books[1]))
        _nav_apply!(holder, make_navigator_parent_operation(navigator))
        @test _nav_is(navigator.address, @reference(shelf, books[1]))
        @test _nav_is(navigator.selection, @reference(navigator, content.books[1].chapters[2]))
        @test length(navigator.back) == 1
        _nav_apply!(holder, make_navigator_parent_operation(navigator))
        @test navigator.address isa EmptyReference
        @test make_navigator_parent_operation(navigator) === nothing
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test _nav_is(navigator.address, @reference(shelf, books[1].chapters[2]))
    end

    @testset "a page that an edit removed" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2].chapters[1]))
        shelf.books[2].chapters = _nav_vector(NavigatorTestChapter[])
        @test _nav_is(get_navigator_page_address(navigator), @reference(shelf, books[2].chapters))
        @test get_navigator_page(navigator) === shelf.books[2].chapters
        # Back still works from the page that is left.
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[1])))
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test _nav_is(navigator.address, @reference(shelf, books[2].chapters))
    end

    @testset "another kind of part on the address cuts it there" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2].chapters[1]))
        volume = NavigatorTestVolume("V", _nav_vector([NavigatorTestChapter("V1", nothing)]), nothing)
        shelf.books[2] = volume
        # Every step still reaches a node, but the second book is a volume now.
        @test _nav_is(get_navigator_page_address(navigator), @reference(shelf, books[2]))
        @test get_navigator_page(navigator) === volume
        # An address that a navigator opens records the types it has then.
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[1].chapters[2])))
        shelf.books[1] = NavigatorTestVolume("W", _nav_vector([NavigatorTestChapter("W1", nothing),
                                                               NavigatorTestChapter("W2", nothing)]), nothing)
        @test _nav_is(get_navigator_page_address(navigator), @reference(shelf, books[1]))
    end

    @testset "undo records no visit" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1].chapters[1]))
        operations = Any[make_navigator_parent_operation(navigator),
                         make_navigator_open_operation(navigator, @reference(shelf, books[2]))]
        _nav_apply!(_NavHolder(navigator), operations[2])
        push!(operations, make_navigator_back_operation(navigator))
        for operation in operations
            @test operation !== nothing
            @test !ProjecturedPlatform.UndoModule.is_undo_step(nothing, operation)
        end
    end
end
end
