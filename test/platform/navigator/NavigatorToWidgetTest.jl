# The view of a navigator: the grid of the bar and the page, the maps between a
# path in the content and a path in the grid, and an editor that a person drives
# with the keys and the buttons of the navigator. The content is the shelf of
# `NavigatorVisitsTest.jl`.

import ProjecturedKernelExample: HeadlessBackend, rendered_output, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

_nav_natural() = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))

# An editor whose document is `document`, after its first frame.
function _nav_editor(document; keywords...)
    backend = HeadlessBackend()
    editor = build_editor(document, _nav_natural(); backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false,
                          keywords...)
    run_frame!(editor)
    (editor, backend)
end

# Each text of a canvas, at its place, also inside the viewport of a pane.
function _nav_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _nav_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _nav_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                       y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_nav_texts(backend) = _nav_drawn(last(rendered_output(backend)))
_nav_has_text(backend, text) = any(entry -> occursin(text, entry[1]), _nav_texts(backend))

_nav_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

_nav_key(key) = KeyDown(key, ModifierKeys(ctrl = true); time = 0.0)

# A click on the first text `text` that the frame draws.
function _nav_click(backend, text)
    index = findfirst(entry -> entry[1] == text, _nav_texts(backend))
    index === nothing && return nothing
    (_, x, y) = _nav_texts(backend)[index]
    MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)
end

function test_navigator_to_widget()
@testset "NavigatorToWidget" begin

    @testset "the grid holds the bar and the page" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        iomap = print_document(make_navigator_projection(), nothing, navigator, nothing)
        output = iomap.output
        @test output isa GridLayout
        @test output.children[2] === shelf.books[2]
        # The page follows the address, and the IO map stays.
        navigator.address = @reference(shelf, books[1].chapters[2])
        @test output.children[2] === shelf.books[1].chapters[2]
    end

    @testset "the maps put the address before a path in the page" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[1]))
        p = make_navigator_projection()
        iomap = print_document(p, nothing, navigator, nothing)
        forward(path) = map_reference_forward(p, iomap, path)
        backward(path) = map_reference_backward(p, iomap, path)
        @test _nav_is(forward(@reference(navigator, content.books[1].chapters[2].title)),
                      @reference(iomap.output, children[2].chapters[2].title))
        @test _nav_is(forward(@reference(navigator, content.books[1])), @reference(iomap.output, children[2]))
        # A path outside the page has no image.
        @test forward(@reference(navigator, content.books[2].title)) === nothing
        @test forward(@reference(navigator, content)) === nothing
        @test forward(EmptyReference()) isa EmptyReference
        @test _nav_is(backward(@reference(iomap.output, children[2].chapters[2].title)),
                      @reference(navigator, content.books[1].chapters[2].title))
        @test _nav_is(backward(@reference(iomap.output, children[2])), @reference(navigator, content.books[1]))
        # A path into the bar names nothing; the grid itself is the navigator.
        @test backward(@reference(iomap.output, children[1].children[1])) === nothing
        @test backward(EmptyReference()) isa EmptyReference
        for path in (@reference(navigator, content.books[1].title), @reference(navigator, content.books[1].chapters[1]))
            @test _nav_is(backward(forward(path)), path)
        end
        # The maps follow the address.
        navigator.address = @reference(shelf, books[2])
        @test _nav_is(backward(@reference(iomap.output, children[2].title)), @reference(navigator, content.books[2].title))
    end

    @testset "an editor: keys, buttons and the address" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        editor, backend = _nav_editor(navigator)
        root_iomap = editor.iomap
        @test _nav_has_text(backend, "Back")
        @test _nav_has_text(backend, "Shelf")

        # Ctrl+Return opens the selected part.
        evaluate_operation(editor, ReplaceSelectionOperation(@reference(navigator, content.books[2].title)))
        _nav_press!(editor, backend, _nav_key(:return))
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        @test _nav_has_text(backend, "Shelf › B")

        # Ctrl+Up opens the parent, with the book selected.
        _nav_press!(editor, backend, _nav_key(:up))
        @test navigator.address isa EmptyReference
        @test _nav_is(navigator.selection, @reference(navigator, content.books[2]))

        # Ctrl+[ and Ctrl+] go back and forward.
        _nav_press!(editor, backend, _nav_key(:left_bracket))
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        _nav_press!(editor, backend, _nav_key(:right_bracket))
        @test navigator.address isa EmptyReference

        # A press on the Back button goes back.
        click = _nav_click(backend, "Back")
        @test click !== nothing
        _nav_press!(editor, backend, click)
        @test _nav_is(navigator.address, @reference(shelf, books[2]))
        @test _nav_has_text(backend, "Shelf › B")

        # No visit printed the navigator again.
        @test editor.iomap === root_iomap
    end

    @testset "undo records no visit in an editor" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf)
        editor, backend = _nav_editor(navigator; undo = true)
        buffer = editor.document
        @test buffer isa UndoBuffer
        evaluate_operation(editor, ReplaceSelectionOperation(@reference(buffer, content.content.books[1].title)))
        _nav_press!(editor, backend, _nav_key(:return))
        @test _nav_is(navigator.address, @reference(shelf, books[1]))
        _nav_press!(editor, backend, _nav_key(:left_bracket))
        @test navigator.address isa EmptyReference
        @test length(buffer.undo_entries) == 0
    end
end
end

"""
    test_navigator()

The navigator: its visits and its view.
"""
function test_navigator()
    test_navigator_visits()
    test_navigator_to_widget()
end
