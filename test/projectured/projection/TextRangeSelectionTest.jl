# Shift and the motion keys select a range of characters where a projection maps
# it, through the editor's own loop and a headless backend: a plain string, a JSON
# string, a Markdown text and a finished message of the assistant each take a range
# in one part, and a range across two parts declines.

const _TR_SHIFT = ModifierKeys(shift = true)
const _TR_NONE = ModifierKeys()

function _tr_editor(document, projection)
    backend = HeadlessBackend()
    scene = make_window_scene(document, "W"; width = 1200, height = 800)
    editor = Editor(scene, make_window_scene_projection(projection);
                    backend = backend, devices = Device[Keyboard(), Mouse()])
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

# The `(start, stop, direction)` that the window's own path ends in.
function _tr_root_range(editor)
    step = last(get_reference_steps(strip_reference_types(editor.document.selection)))
    step isa Union{RangeReferenceStep,TextRangeReferenceStep} ? (step.start, step.stop, step.direction) : nothing
end

# The time of the next gesture of the mouse: each one starts a second after the
# last, so two of them never make one double click.
const _TR_TIME = Ref(0.0)

# An editor whose screen has the gesture tracker, as an application has it: a press
# and a release make a click, and a press can take the pointer for a drag.
function _tr_tracking_editor(document, projection)
    backend = HeadlessBackend()
    scene = make_window_scene(document, "W"; width = 1200, height = 800)
    tracked, tracking = make_tracking_screen(scene, make_window_scene_projection(projection))
    editor = Editor(tracked, tracking; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

# A press of the left button at `(x, y)`, a move to each point of `points` with the
# button held, and the release at the last point, as a backend sends them.
function _tr_drag!(editor, backend, x, y, points; modifiers = _TR_NONE)
    time = (_TR_TIME[] += 1.0)
    _tr_press!(editor, backend, MouseDown(:left, x, y, modifiers; time))
    for (px, py) in points
        time += 0.05
        _tr_press!(editor, backend, MouseMove(px, py, MouseButtons(:left), modifiers; time))
    end
    (ex, ey) = isempty(points) ? (x, y) : last(points)
    _tr_press!(editor, backend, MouseUp(:left, ex, ey, modifiers; time = time + 0.05))
end

# `count` clicks at `(x, y)` in a row, each a press and a release.
function _tr_clicks!(editor, backend, x, y, count; modifiers = _TR_NONE)
    time = (_TR_TIME[] += 1.0)
    for k in 1:count
        _tr_press!(editor, backend, MouseDown(:left, x, y, modifiers; time = time + 0.1k))
        _tr_press!(editor, backend, MouseUp(:left, x, y, modifiers; time = time + 0.1k + 0.02))
    end
end

# A click at the start of the drawn text `text`, then `k` plain moves to the right,
# so the caret stands before character `k + 1` of it whatever the font. With
# `tracking`, the click is a press and a release, for an editor with the tracker.
function _tr_place!(editor, backend, text::AbstractString, k::Int; tracking::Bool = false)
    texts = _tr_texts(_tr_window(backend))
    (x, y, _) = texts[findfirst(t -> t[3] == text, texts)]
    tracking ? _tr_clicks!(editor, backend, x + 1, y + 8, 1) :
               _tr_press!(editor, backend, MouseClick(:left, x + 1, y + 8, _TR_NONE; time = 0.0))
    foreach(_ -> _tr_press!(editor, backend, KeyDown(:right, _TR_NONE; time = 0.0)), 1:k)
end

function test_text_range_selection()
@testset "Shift selects a range where a projection maps it" begin
    measure = FontFileMeasure()
    font = StyleFont("Ubuntu Mono", 14)

    @testset "a plain string maps the range, and an edit replaces it" begin
        s = PrimitiveString("hello world")
        projection = ChainingProjection(PrimitiveStringToTextBlock(),
                                        WordWrapping(measure = measure),
                                        TextToGraphics(measure = measure))
        (editor, backend) = _tr_editor(s, projection)
        (x, y, _) = only(_tr_texts(_tr_window(backend)))
        # A press between "hello" and " world".
        _tr_press!(editor, backend,
                   MouseClick(:left, x + first(compute_text_extent("hello", font)), y + 8, _TR_NONE; time = 0.0))
        @test _tr_range(s) == (5, 5)
        caret_rects = _tr_rects(_tr_window(backend))

        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT; time = 0.0))
        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT; time = 0.0))
        @test _tr_range(s) == (3, 5)
        # The window's own path names the same range: there is one selection.
        root = get_reference_steps(strip_reference_types(editor.document.selection))
        @test (last(root).start, last(root).stop) == (3, 5)
        @test _tr_rects(_tr_window(backend)) == caret_rects + 1

        # The range grew to the left, so its start moves: the right key makes it
        # smaller, and the end key takes the moving end past the anchor.
        _tr_press!(editor, backend, KeyDown(:right, _TR_SHIFT; time = 0.0))
        @test _tr_range(s) == (4, 5)
        _tr_press!(editor, backend, KeyDown(:end, _TR_SHIFT; time = 0.0))
        @test _tr_range(s) == (5, 11)

        # Typing replaces the range, and the caret follows the typed text.
        _tr_press!(editor, backend, KeyPress('X'; time = 0.0))
        @test s.value == "helloX"
        @test _tr_range(s) == (6, 6)

        _tr_press!(editor, backend, KeyDown(:home, _TR_SHIFT; time = 0.0))
        @test _tr_range(s) == (0, 6)
        _tr_press!(editor, backend, KeyDown(:backspace, _TR_NONE; time = 0.0))
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
                   MouseClick(:left, x + first(compute_text_extent("abcd", font)), y + 8, _TR_NONE; time = 0.0))
        _tr_press!(editor, backend, KeyDown(:left, _TR_SHIFT; time = 0.0))
        @test _tr_range(s) == (3, 4)
        _tr_press!(editor, backend, KeyDown(:left, _TR_NONE; time = 0.0))
        @test _tr_range(s) == (3, 3)
    end

    @testset "the mouse selects a range: a drag, Shift and a press, a double and a triple click" begin
        s = PrimitiveString("hello world")
        projection = ChainingProjection(PrimitiveStringToTextBlock(),
                                        WordWrapping(measure = measure),
                                        TextToGraphics(measure = measure))
        (editor, backend) = _tr_tracking_editor(s, projection)
        (x, y, _) = only(_tr_texts(_tr_window(backend)))
        at(k) = x + first(compute_text_extent(first("hello world", k), font))
        # A drag from the start over "hello" selects it forward.
        _tr_drag!(editor, backend, at(0) + 1, y + 8, [(at(3), y + 8), (at(5), y + 8)])
        @test _tr_range(s) == (0, 5)
        @test _tr_root_range(editor)[3] === :forward
        # A drag to the left selects backward, and the caret is at the start.
        _tr_drag!(editor, backend, at(11) - 1, y + 8, [(at(6), y + 8)])
        @test _tr_range(s) == (6, 11)
        @test _tr_root_range(editor)[3] === :backward
        # A drag past the end of the text stops at its end.
        _tr_drag!(editor, backend, at(6), y + 8, [(at(11) + 400, y + 300)])
        @test _tr_range(s) == (6, 11)
        # Shift and a press move the moving end and keep the anchor.
        _tr_clicks!(editor, backend, at(2), y + 8, 1)
        @test _tr_range(s) == (2, 2)
        _tr_clicks!(editor, backend, at(5), y + 8, 1; modifiers = _TR_SHIFT)
        @test _tr_range(s) == (2, 5)
        _tr_clicks!(editor, backend, at(1), y + 8, 1; modifiers = _TR_SHIFT)
        @test _tr_range(s) == (1, 2)
        @test _tr_root_range(editor)[3] === :backward
        # A double click selects the word, and a triple click the line.
        _tr_clicks!(editor, backend, at(8), y + 8, 2)
        @test _tr_range(s) == (6, 11)
        _tr_clicks!(editor, backend, at(8), y + 8, 3)
        @test _tr_range(s) == (0, 11)
    end

    @testset "a drag selects over two lines of a text" begin
        block = make_text_block("first line\nsecond line", StyleText(font, color_black))
        (editor, backend) = _tr_tracking_editor(block, TextToGraphics(measure = measure))
        texts = _tr_texts(_tr_window(backend))
        (x1, y1, _) = texts[findfirst(t -> t[3] == "first line", texts)]
        (x2, y2, _) = texts[findfirst(t -> t[3] == "second line", texts)]
        _tr_drag!(editor, backend, x1 + first(compute_text_extent("first ", font)), y1 + 8,
                  [(x2 + first(compute_text_extent("second", font)), y2 + 8)])
        @test _tr_root_range(editor) == (6, 17, :forward)
    end

    @testset "a JSON string takes a range in its value, and a range past its quote declines" begin
        document = make_json_document_example()
        (editor, backend) = _tr_editor(document, make_json_projection_example())
        press(event) = _tr_press!(editor, backend, event)
        _tr_place!(editor, backend, "Alice", 2)
        press(KeyDown(:left, _TR_SHIFT; time = 0.0))
        @test _tr_root_range(editor) == (1, 2, :backward)
        @test _tr_rects(_tr_window(backend)) >= 2
        # Typing replaces the range, and the caret follows the typed text.
        press(KeyPress('X'; time = 0.0))
        @test any(t -> t[3] == "AXice", _tr_texts(_tr_window(backend)))
        @test _tr_root_range(editor) == (2, 2, :forward)
        # The range grows to the end of the value; the closing quote is no part of it.
        foreach(_ -> press(KeyDown(:right, _TR_SHIFT; time = 0.0)), 1:3)
        @test _tr_root_range(editor) == (2, 5, :forward)
        before = repr(editor.document.selection)
        press(KeyDown(:right, _TR_SHIFT; time = 0.0))
        @test editor.operation === nothing
        @test repr(editor.document.selection) == before
    end

    @testset "the mouse selects in a JSON string, and Alt and a click still select the whole string" begin
        (editor, backend) = _tr_tracking_editor(make_json_document_example(), make_json_projection_example())
        texts = _tr_texts(_tr_window(backend))
        (x, y, _) = texts[findfirst(t -> t[3] == "Alice", texts)]
        _tr_drag!(editor, backend, x + 1, y + 8, [(x + first(compute_text_extent("Al", font)), y + 8)])
        @test _tr_root_range(editor) == (0, 2, :forward)
        # A drag out of the value keeps the last range that the value holds.
        _tr_drag!(editor, backend, x + first(compute_text_extent("Al", font)), y + 8,
                  [(x + 1, y + 8), (x - 40, y + 8)])
        @test _tr_root_range(editor) == (0, 2, :backward)
        _tr_clicks!(editor, backend, x + 1, y + 8, 1; modifiers = ModifierKeys(alt = true))
        @test last(get_reference_steps(strip_reference_types(editor.document.selection))) isa FieldReferenceStep
    end

    @testset "a Markdown text takes a range, and a range into a strong word declines" begin
        document = make_markdown_document_example()
        (editor, backend) = _tr_editor(document, make_markdown_projection_example())
        press(event) = _tr_press!(editor, backend, event)
        _tr_place!(editor, backend, "Composable projections", 4)
        press(KeyDown(:right, _TR_SHIFT; time = 0.0))
        press(KeyDown(:right, _TR_SHIFT; time = 0.0))
        @test _tr_root_range(editor) == (4, 6, :forward)
        # "A " is a text of its own, and "projectional" is in a strong part.
        _tr_place!(editor, backend, "A ", 1)
        press(KeyDown(:right, _TR_SHIFT; time = 0.0))
        @test _tr_root_range(editor) == (1, 2, :forward)
        before = repr(editor.document.selection)
        press(KeyDown(:right, _TR_SHIFT; time = 0.0))
        @test repr(editor.document.selection) == before
    end

    @testset "a finished message of the assistant takes a range" begin
        a = Assistant(; llm = FakeLlm("Hello world"))
        (editor, backend) = _tr_tracking_editor(a, make_assistant_projection_example())
        press(event) = _tr_press!(editor, backend, event)
        texts = _tr_texts(_tr_window(backend))
        (x, y, _) = texts[findfirst(t -> occursin("type here", t[3]), texts)]
        _tr_clicks!(editor, backend, x + 30, y + 8, 1)
        foreach(c -> press(KeyPress(c; time = 0.0)), "hi")
        press(KeyPress('\n'; time = 0.0))
        _panel_wait_idle!(a)
        foreach(_ -> run_frame!(editor), 1:3)
        _tr_place!(editor, backend, "Hello world", 2; tracking = true)
        foreach(_ -> press(KeyDown(:right, _TR_SHIFT; time = 0.0)), 1:3)
        @test _tr_root_range(editor) == (2, 5, :forward)
        press(KeyDown(:left, _TR_SHIFT; time = 0.0))
        @test _tr_root_range(editor) == (2, 4, :forward)
        # A drag in the message selects too.
        texts = _tr_texts(_tr_window(backend))
        (x, y, _) = texts[findfirst(t -> t[3] == "Hello world", texts)]
        _tr_drag!(editor, backend, x + 1, y + 8, [(x + 200, y + 8)])
        @test _tr_root_range(editor) == (0, 11, :forward)
    end
end
end

export test_text_range_selection
