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

# A part whose page keeps state of its own, and the view document of that page: it
# names the part by its field `page`, keeps the place of the page, and holds the
# part while it shows.
@document struct NavigatorTestRuns
    title::String
end

@document struct NavigatorTestRunsView
    page::Any
    anchor::Int = 1
end

ProjecturedKernel.DocumentModule.get_edited_field(::NavigatorTestRunsView) = :page
ProjecturedPlatform.DomainModule.make_document_view(runs::NavigatorTestRuns) = NavigatorTestRunsView(runs)
ProjecturedPlatform.DomainModule.acquire_document!(editor, view::NavigatorTestRunsView) =
    ProjecturedPlatform.DomainModule.hold_documents!(editor, view, Any[getfield(view, :page)[]])
ProjecturedPlatform.DomainModule.release_document!(editor, view::NavigatorTestRunsView) =
    ProjecturedPlatform.DomainModule.release_held_documents!(editor, view, Any[getfield(view, :page)[]])

# A container of chapters, which a navigator passes over.
@document struct NavigatorTestFolder
    items::CellVector
end

ProjecturedPlatform.NavigatorModule.is_navigator_stop(::NavigatorTestFolder) = false

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

    @testset "a page with a view of its own shows the view, the view holds the page, and Back returns to it" begin
        runs = NavigatorTestRuns("R", nothing)
        shelf = NavigatorTestShelf("Shelf", _nav_vector([
            NavigatorTestBook("A", _nav_vector([NavigatorTestChapter("A1", nothing), runs]), nothing)]), nothing)
        navigator = Navigator(shelf)
        editor = Editor(navigator, IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
        evaluate_operation(editor, AcquireDocumentOperation(navigator))
        # The shelf shows as itself, and the navigator holds it.
        @test navigator.page_view === nothing && get_navigator_page_view(navigator) === shelf
        @test is_document_held(editor, shelf)
        address = Reference(FieldReferenceStep("books"), RangeReferenceStep(0, 1),
                            FieldReferenceStep("chapters"), RangeReferenceStep(1, 2))
        evaluate_operation(editor, make_navigator_open_operation(navigator, address))
        view = get_navigator_page_view(navigator)
        @test view isa NavigatorTestRunsView && getfield(view, :page)[] === runs
        @test get_navigator_page(navigator) === runs && navigator.page_view.view === view
        @test is_document_held(editor, view) && is_document_held(editor, runs) && !is_document_held(editor, shelf)
        # The selection keeps going through the content, and the view follows it.
        @test _nav_is(navigator.selection, Reference(FieldReferenceStep("content"), get_reference_steps(address)...))
        @test _nav_is(view.selection, Reference(FieldReferenceStep("page")))
        evaluate_operation(editor, ReplaceSelectionOperation(annotate_reference_types(navigator,
            Reference(FieldReferenceStep("content"), get_reference_steps(address)..., FieldReferenceStep("title")))))
        @test _nav_is(view.selection, Reference(FieldReferenceStep("page"), FieldReferenceStep("title")))
        # A selection that the page keeps while it is not live keeps the field too.
        getfield(runs, :selection)[] = SelectionDocument(; primary = runs.selection, live = false)
        kept = getfield(view, :selection)[]
        @test kept isa SelectionDocument && !kept.live && view.selection === nothing
        @test _nav_is(kept.primary, Reference(FieldReferenceStep("page"), FieldReferenceStep("title")))
        # No walk of the navigator goes through the view.
        @test is_walk_opaque(navigator.page_view)
        # Back shows the shelf as itself and releases the view; Forward shows the
        # same view again, with its place.
        getfield(view, :anchor)[] = 7
        evaluate_operation(editor, make_navigator_back_operation(navigator))
        @test navigator.page_view === nothing && is_document_held(editor, shelf)
        @test !is_document_held(editor, view) && !is_document_held(editor, runs)
        evaluate_operation(editor, make_navigator_forward_operation(navigator))
        @test get_navigator_page_view(navigator) === view && view.anchor == 7 && is_document_held(editor, runs)
        # A new visit of the page makes a new view.
        evaluate_operation(editor, make_navigator_open_operation(navigator, EmptyReference()))
        evaluate_operation(editor, make_navigator_open_operation(navigator, address))
        @test get_navigator_page_view(navigator) isa NavigatorTestRunsView && get_navigator_page_view(navigator) !== view
        # A navigator whose view another navigator holds makes a view of its own at
        # its acquire.
        other = Navigator(shelf, annotate_reference_types(shelf, address))
        getfield(other, :page_view)[] = navigator.page_view
        evaluate_operation(editor, AcquireDocumentOperation(other))
        @test get_navigator_page_view(other) isa NavigatorTestRunsView
        @test get_navigator_page_view(other) !== get_navigator_page_view(navigator)
        @test is_document_held(editor, get_navigator_page_view(other))
        # A duplicate keeps no view, also in its visits, so Back makes its own.
        duplicate = make_document_duplicate(navigator)
        @test duplicate.page_view === nothing && all(visit -> visit.page_view === nothing, duplicate.back)
        @test !isempty(navigator.back) && any(visit -> visit.page_view !== nothing, navigator.back)
        # A file keeps no view: the navigator that it gives makes one when it is held.
        @test !any(entry -> first(entry) === :page_view, last(ProjecturedPlatform.SerializationModule.pred_arguments(navigator)))
    end

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

    @testset "a navigator passes over a document that is no stop, and can show it" begin
        chapter = NavigatorTestChapter("C1", nothing)
        folder = NavigatorTestFolder(_nav_vector([chapter]), nothing)
        shelf = NavigatorTestShelf("Shelf", _nav_vector([folder]), nothing)
        navigator = Navigator(shelf, @reference(shelf, books[1].items[1]))
        # Parent passes over the folder and the collections, to the shelf.
        @test _nav_is(find_navigator_parent_address(navigator), EmptyReference())
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_parent_operation(navigator))
        @test navigator.address isa EmptyReference
        # The folder is still a page at its own address.
        _nav_apply!(holder, make_navigator_open_operation(navigator, @reference(shelf, books[1])))
        @test get_navigator_page(navigator) === folder
        # The selected part below the page passes over a folder too.
        navigator = Navigator(shelf)
        replace_selection!(navigator, @reference(navigator, content.books[1].items[1].title))
        @test _nav_is(find_navigator_selected_address(navigator), @reference(shelf, books[1].items[1]))
        replace_selection!(navigator, @reference(navigator, content.books[1]))
        @test find_navigator_selected_address(navigator) === nothing
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
