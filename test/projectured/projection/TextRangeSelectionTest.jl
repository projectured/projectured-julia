# Shift and the motion keys select a range of characters where a projection maps
# it, through the editor's own loop and a headless backend: a plain string maps a
# range, and a JSON string, whose syntax chain maps a caret only, declines one.

const _TR_SHIFT = ModifierKeys(shift = true)
const _TR_NONE = ModifierKeys()

function _tr_editor(document, projection)
    backend = HeadlessBackend()
    scene = make_window_scene(document, "W"; width = 1200, height = 800)
    editor = Editor(backend, scene, make_window_scene_projection(projection),
                    Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

function _tr_press!(editor, backend, event)
    push_event!(backend, WindowInput(:W, event))
    run_frame!(editor)
end

_tr_window(backend) = last(rendered_output(backend)).windows[1].content

# Every text a window drew, with its place.
function _tr_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    node isa Cell && return _tr_texts(node[], ox, oy, found)
    if node isa GraphicsCanvas
        for element in node.elements
            _tr_texts(element, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _tr_texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), node.text))
    end
    found
end

# How many rectangles a window drew. A caret is one; a range adds its highlight.
function _tr_rects(node)
    node isa Cell && return _tr_rects(node[])
    node isa GraphicsRect && return 1
    node isa GraphicsCanvas && return sum(_tr_rects, node.elements; init = 0)
    node isa GraphicsViewport && return _tr_rects(node.content)
    0
end

# The `(start, stop)` that the document's own selection ends in.
function _tr_range(document)
    steps = get_reference_steps(strip_reference_types(getfield(document, :selection)[]))
    last(steps) isa RangeReferenceStep || return nothing
    (last(steps).start, last(steps).stop)
end

function test_text_range_selection()
@testset "Shift selects a range where a projection maps it" begin
    measure = measure_truetype_text
    font = font_ubuntu_monospace_regular_20

    @testset "a plain string maps the range, and an edit replaces it" begin
        s = PrimitiveString("hello world")
        projection = ChainingProjection(PrimitiveStringToTextBlock(),
                                        WordWrapping(measure = measure),
                                        TextToGraphics(measure = measure))
        (editor, backend) = _tr_editor(s, projection)
        (x, y, _) = only(_tr_texts(_tr_window(backend)))
        # A press between "hello" and " world".
        _tr_press!(editor, backend,
                   MousePress(:left, x + first(measure("hello", font)), y + 8, _TR_NONE))
        @test _tr_range(s) == (5, 5)
        caret_rects = _tr_rects(_tr_window(backend))

        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT))
        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT))
        @test _tr_range(s) == (3, 5)
        # The window's own path names the same range: there is one selection.
        root = get_reference_steps(strip_reference_types(editor.document.selection))
        @test (last(root).start, last(root).stop) == (3, 5)
        @test _tr_rects(_tr_window(backend)) == caret_rects + 1

        # The right key moves the stop.
        _tr_press!(editor, backend, KeyDown(:right, _TR_SHIFT))
        @test _tr_range(s) == (3, 6)
        _tr_press!(editor, backend, KeyDown(:end, _TR_SHIFT))
        @test _tr_range(s) == (3, 11)

        # Typing replaces the range, and the caret follows the typed text.
        _tr_press!(editor, backend, KeyPress('X'))
        @test s.value == "helX"
        @test _tr_range(s) == (4, 4)

        _tr_press!(editor, backend, KeyDown(:home, _TR_SHIFT))
        @test _tr_range(s) == (0, 4)
        _tr_press!(editor, backend, KeyDown(:backspace, _TR_NONE))
        @test s.value == ""
        @test _tr_range(s) == (0, 0)
    end

    @testset "a plain arrow collapses the range" begin
        s = PrimitiveString("abcdef")
        projection = ChainingProjection(PrimitiveStringToTextBlock(),
                                        WordWrapping(measure = measure),
                                        TextToGraphics(measure = measure))
        (editor, backend) = _tr_editor(s, projection)
        (x, y, _) = only(_tr_texts(_tr_window(backend)))
        _tr_press!(editor, backend,
                   MousePress(:left, x + first(measure("abcd", font)), y + 8, _TR_NONE))
        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT))
        @test _tr_range(s) == (3, 4)
        _tr_press!(editor, backend, KeyDown(:left, _TR_NONE))
        @test _tr_range(s) == (3, 3)
    end

    @testset "a JSON string declines a range, and the caret stays" begin
        document = make_json_document_example()
        (editor, backend) = _tr_editor(document, make_json_projection_example())
        texts = _tr_texts(_tr_window(backend))
        (x, y, _) = texts[findfirst(t -> t[3] == "name", texts)]
        _tr_press!(editor, backend,
                   MousePress(:left, x + first(measure("na", font)), y + 8, _TR_NONE))
        # The path is a live value that changes in place, so its printed form is
        # what is kept.
        @test editor.document.selection !== nothing
        before = repr(editor.document.selection)
        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT))
        @test editor.operation === nothing
        @test repr(editor.document.selection) == before
        # A plain arrow still moves the caret there.
        _tr_press!(editor, backend, KeyDown(:left, _TR_NONE))
        @test repr(editor.document.selection) != before
    end
end
end

export test_text_range_selection
