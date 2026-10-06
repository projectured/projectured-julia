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

import ProjecturedKernelExample: HeadlessBackend, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

# An editor with a window of a fixed size, where the context menu window opens
# the list of choices in a window of its own.
function _nav_window_editor(document)
    backend = HeadlessBackend()
    editor = build_editor(document, _nav_natural(); backend, devices = Device[Keyboard(), Mouse(), Display()],
                          appearance = false, settings = false,
                          window = (; title = "W", width = 700, height = 400,
                                    opened_window_projections = Pair{Type,Any}[Document => _nav_natural()]))
    run_frame!(editor)
    (editor, backend)
end

_nav_force(value) = value isa AbstractCell ? _nav_force(value[]) : value
_nav_windows(editor) = collect(_nav_force(_nav_force(get_iomap_output(editor.iomap)).windows))
_nav_window_texts(window) = first.(_nav_drawn(_nav_force(window.content)))
_nav_others(editor, main) = [window for window in _nav_windows(editor) if window.id !== main]

# Each event in the window `id`, one frame each.
function _nav_send!(editor, backend, id, events...)
    for event in events
        push_event!(backend, WindowInput(id, event))
        run_frame!(editor)
    end
end

# A press and a release on the first text `text` that the window `window` draws,
# or on the last with `pick = last`.
function _nav_press_text!(editor, backend, window, text, time; pick = first)
    (_, x, y) = pick([entry for entry in _nav_drawn(_nav_force(window.content)) if entry[1] == text])
    _nav_send!(editor, backend, window.id, MouseDown(:left, x + 2, y + 2, ModifierKeys(); time),
               MouseUp(:left, x + 2, y + 2, ModifierKeys(); time = time + 0.05))
end

# The glyph of the arrow before a name of the address.
const _NAV_CHOICES = string(Char(0xe06f))

# A navigator on the chapter "A1" of the shelf in an editor, with the list of the
# choices of the book "A" open: the main window and the window of the list.
function _nav_open_book_choices()
    shelf = _nav_make_shelf()
    navigator = Navigator(shelf, @reference(shelf, books[1].chapters[1]))
    editor, backend = _nav_window_editor(navigator)
    main = only(_nav_windows(editor))
    # An arrow stands before "A" and before "A1".
    @test count(==(_NAV_CHOICES), _nav_window_texts(main)) == 2
    _nav_press_text!(editor, backend, main, _NAV_CHOICES, 1.0)
    (shelf, navigator, editor, backend, main.id)
end

_nav_key_down(key; time) = KeyDown(key, ModifierKeys(); time)

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

    @testset "the arrow before a name lists the parts at its place, and typing narrows the list" begin
        shelf, navigator, editor, backend, main = _nav_open_book_choices()
        list = only(_nav_others(editor, main))
        texts = _nav_window_texts(list)
        @test "Find: type a name or a number" in texts && "A" in texts && "B" in texts
        # The window under the list keeps the keys, and the list takes them first.
        _nav_send!(editor, backend, main, _nav_key_down(:b; time = 1.2), KeyPress('b'; time = 1.2))
        texts = _nav_window_texts(only(_nav_others(editor, main)))
        @test "Find: b" in texts && "B" in texts && !("A" in texts)
        _nav_send!(editor, backend, main, _nav_key_down(:return; time = 1.3))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test isempty(_nav_others(editor, main))
        @test length(navigator.back) == 1
    end

    @testset "Down moves the row from the current part, and Return chooses it" begin
        shelf, navigator, editor, backend, main = _nav_open_book_choices()
        _nav_send!(editor, backend, main, _nav_key_down(:down; time = 1.2), _nav_key_down(:return; time = 1.3))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
    end

    @testset "a press on a row chooses it" begin
        shelf, navigator, editor, backend, main = _nav_open_book_choices()
        _nav_press_text!(editor, backend, only(_nav_others(editor, main)), "B", 1.5)
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test isempty(_nav_others(editor, main))
    end

    @testset "Escape closes the list, and a key with Ctrl goes on to the navigator" begin
        shelf, navigator, editor, backend, main = _nav_open_book_choices()
        # A key reaches the navigator along the selection, so the chapter in the
        # page is selected first, and the list opens again.
        _nav_send!(editor, backend, main, _nav_key_down(:escape; time = 1.1))
        window = only(_nav_windows(editor))
        _nav_press_text!(editor, backend, window, "A1", 1.15; pick = last)
        _nav_press_text!(editor, backend, window, _NAV_CHOICES, 1.2)
        @test length(_nav_others(editor, main)) == 1
        _nav_send!(editor, backend, main, KeyDown(:up, ModifierKeys(ctrl = true); time = 1.25))
        @test get_navigator_page(navigator) === shelf.books[1]
        _nav_send!(editor, backend, main, _nav_key_down(:escape; time = 1.3))
        @test isempty(_nav_others(editor, main))
        @test get_navigator_page(navigator) === shelf.books[1]
    end
end
end
