# The choices at a step of the address, and a choice that opens in place of the
# step: the rest of the address stays as far as it reaches nodes of the types that
# it records. The content is the shelf of `NavigatorVisitsTest.jl`, and a library
# of two shelves for the choices of a field.

@document struct NavigatorTestLibrary
    title::String
    fiction::Any
    science::Any
end

ProjecturedKernel.DocumentModule.get_document_title(x::NavigatorTestLibrary) = x.title

# A library with the shelf of `_nav_make_shelf` as "Fiction" and a shelf "Science"
# of one book "S" with the chapters "S1" and "S2".
function _nav_make_library()
    fiction = _nav_make_shelf()
    fiction.title = "Fiction"
    science = NavigatorTestShelf("Science", _nav_vector([
        NavigatorTestBook("S", _nav_vector([NavigatorTestChapter("S1", nothing),
                                            NavigatorTestChapter("S2", nothing)]), nothing)]), nothing)
    NavigatorTestLibrary("Library", fiction, science, nothing)
end

# A book of the chapters "c1" to "c`count`".
_nav_make_long_book(count) =
    NavigatorTestBook("Long", _nav_vector([NavigatorTestChapter("c$(i)", nothing) for i in 1:count]), nothing)

_nav_element(i) = RangeReferenceStep(i - 1, i)

function test_navigator_choices()
@testset "Navigator choices" begin

    @testset "the choices of a field are the fields that hold a document" begin
        library = _nav_make_library()
        choices = find_navigator_choices(library, FieldReferenceStep("fiction"))
        @test choices == ["Fiction" => FieldReferenceStep("fiction"), "Science" => FieldReferenceStep("science")]
        @test find_navigator_choices(library, FieldReferenceStep("fiction"); query = "sci") ==
              ["Science" => FieldReferenceStep("science")]
        @test find_navigator_choices(library, FieldReferenceStep("fiction"); limit = 1) ==
              ["Fiction" => FieldReferenceStep("fiction")]
    end

    @testset "the choices of an element are the elements, from about the current one" begin
        shelf = _nav_make_shelf()
        @test find_navigator_choices(shelf.books, _nav_element(2)) == ["A" => _nav_element(1), "B" => _nav_element(2)]
        book = _nav_make_long_book(10)
        # Two before the current element, and on up to the limit.
        @test first.(find_navigator_choices(book.chapters, _nav_element(8); limit = 4)) == ["c6", "c7", "c8", "c9"]
        # The walk ends at the first element that is not there.
        @test first.(find_navigator_choices(book.chapters, _nav_element(9); limit = 6)) == ["c6", "c7", "c8", "c9", "c10"]
        # Words search from the first element; a number goes to that element alone.
        @test first.(find_navigator_choices(book.chapters, _nav_element(8); query = "C1")) == ["c1", "c10"]
        @test find_navigator_choices(book.chapters, _nav_element(8); query = "3") == ["c3" => _nav_element(3)]
        @test isempty(find_navigator_choices(book.chapters, _nav_element(8); query = "11"))
        @test isempty(find_navigator_choices(book.chapters, _nav_element(8); query = "0"))
        # A range names no page, so it has no choices.
        @test isempty(find_navigator_choices(book.chapters, RangeReferenceStep(0, 2)))
    end

    @testset "a choice keeps the rest of the address where it still reaches" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1].chapters[1]))
        holder = _NavHolder(navigator)
        # Step 2 of `books[1].chapters[1]` is the `[1]` of the first book.
        _nav_apply!(holder, make_navigator_choice_operation(navigator, 2, _nav_element(2)))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test _nav_steps(navigator.selection) == [FieldReferenceStep("content"),
                                                  _nav_steps(@reference(shelf, books[2].chapters[1]))...]
        @test length(navigator.back) == 1
        _nav_apply!(holder, make_navigator_back_operation(navigator))
        @test get_navigator_page(navigator) === shelf.books[1].chapters[1]
        # The choice of the current element changes no page.
        @test make_navigator_choice_operation(navigator, 2, _nav_element(1)) === nothing
    end

    @testset "a choice cuts the rest at the first step that reaches no node" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1].chapters[2]))
        _nav_apply!(_NavHolder(navigator), make_navigator_choice_operation(navigator, 2, _nav_element(2)))
        # The second book has one chapter: the page is its chapters, and the address
        # keeps the step that reaches no node.
        @test _nav_is(get_navigator_page_address(navigator), @reference(shelf, books[2].chapters))
        @test _nav_steps(navigator.address) == [FieldReferenceStep("books"), _nav_element(2),
                                                FieldReferenceStep("chapters"), _nav_element(2)]
        @test _nav_steps(navigator.selection) == [FieldReferenceStep("content"),
                                                  _nav_steps(@reference(shelf, books[2].chapters))...]
    end

    @testset "a choice cuts the rest at a node of another type" begin
        shelf = _nav_make_shelf()
        volume = NavigatorTestVolume("V", _nav_vector([NavigatorTestChapter("V1", nothing)]), nothing)
        push!(shelf.books, volume)
        navigator = Navigator(shelf, @reference(shelf, books[2].chapters[1]))
        # The volume has the fields of a book, but the address records a book there.
        _nav_apply!(_NavHolder(navigator), make_navigator_choice_operation(navigator, 2, _nav_element(3)))
        @test get_navigator_page(navigator) === volume
    end

    @testset "a choice of a field keeps the rest in the other document" begin
        library = _nav_make_library()
        navigator = Navigator(library, @reference(library, fiction.books[1].chapters[2]))
        _nav_apply!(_NavHolder(navigator), make_navigator_choice_operation(navigator, 1, FieldReferenceStep("science")))
        @test get_navigator_page(navigator) === library.science.books[1].chapters[2]
    end
end
end
