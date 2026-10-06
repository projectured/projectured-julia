# The navigator as a document among the others: a save that keeps the content and
# the address, a duplicate that browses on its own, and a tab whose tooltip says
# the address of the page. The content is the shelf of `NavigatorVisitsTest.jl`.

function test_navigator_document()
@testset "Navigator document" begin

    @testset "a path as text, and back" begin
        for path in (EmptyReference(),
                     Reference(FieldReferenceStep("books")),
                     Reference(FieldReferenceStep("books"), ElementReferenceStep(2), FieldReferenceStep("title")))
            text = print_path_text(path)
            @test _nav_steps(parse_path_text(text)) == _nav_steps(path)
        end
        @test print_path_text(Reference(FieldReferenceStep("books"), ElementReferenceStep(2))) == "books[2]"
        @test print_path_text(EmptyReference()) == ""
        @test_throws ArgumentError parse_path_text("books{2}")
    end

    @testset "a save keeps the content and the address, and no visit" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        _nav_apply!(_NavHolder(navigator), make_navigator_open_operation(navigator, @reference(shelf, books[2])))
        @test length(navigator.back) == 1
        text = print_pred_text(navigator)
        @test occursin("books[2]", text)
        loaded = parse_pred_text(text)
        @test loaded isa Navigator
        @test _nav_steps(loaded.address) == _nav_steps(@reference(shelf, books[2]))
        @test get_navigator_page(loaded).title == "B"
        @test isempty(loaded.back) && isempty(loaded.forward)
    end

    @testset "a duplicate browses on its own over the same content" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        _nav_apply!(_NavHolder(navigator), make_navigator_open_operation(navigator, @reference(shelf, books[2])))
        @test has_document_duplicate(navigator)
        duplicate = make_document_duplicate(navigator)
        @test duplicate isa Navigator && duplicate !== navigator
        @test duplicate.content === shelf
        @test _nav_is(duplicate.address, @reference(shelf, books[2]))
        @test length(duplicate.back) == 1
        _nav_apply!(_NavHolder(duplicate), make_navigator_back_operation(duplicate))
        @test duplicate.address isa EmptyReference
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
    end

    @testset "the tooltip of a tab says the address of the page" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        title = make_pane_tab_title(navigator, "Books")
        @test title.name.value == "Books"
        @test title.tooltip == "Shelf"
        _nav_apply!(_NavHolder(navigator), make_navigator_open_operation(navigator, @reference(shelf, books[2])))
        @test title.tooltip == "Shelf › B"
        @test title.name.value == "Books"
    end
end
end
