# The keys of the text domain, pressed through the loop of an editor: a plain text
# in a history and in a scroll pane, a string of a JSON document, the draft of the
# chat and the name of a tab. The checks read the document and the caret that the
# frame draws.

# A character of `_tk_measure` is 10 pixels wide, and a line is 18 pixels high.
_tk_measure() = FixedMeasure(10, 18, 6, 0)

# An editor on `history`, an `UndoBuffer`, with the widgets and the text drawn at
# `_tk_measure`, after its first frame.
function _tk_build(history)
    measure = _tk_measure()
    projection = RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()],
        LayoutToGraphics().dispatch,
        WidgetToGraphics(; measure).dispatch,
        Pair{Type,Any}[TextBlock => TextToGraphics(measure = measure)])))
    backend = HeadlessBackend()
    editor = build_editor(history, projection;
        backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
        window = false, appearance = false, settings = false, tabs = false, focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

_tk_press!(editor, backend, events...) = (foreach(event -> push_event!(backend, event), events); run_frame!(editor))
_tk_key(key; modifiers...) = KeyDown(key, ModifierKeys(; modifiers...); time = 0.0)
_tk_typed(char; modifiers...) = KeyPress(char, ModifierKeys(; modifiers...); time = 0.0)

# The places of the carets that a frame draws: the text domain draws a caret as a
# rectangle 2 pixels wide. A viewport draws its content moved by its transform.
function _tk_carets(node, ox = 0, oy = 0, found = Tuple{Int,Int}[])
    node isa Cell && return _tk_carets(node[], ox, oy, found)
    if node isa GraphicsRect
        Int(node.w) == 2 && Int(node.h) > 0 && push!(found, (ox + Int(node.x), oy + Int(node.y)))
    elseif node isa GraphicsCanvas
        foreach(element -> _tk_carets(element, ox + Int(node.x), oy + Int(node.y), found), node.elements)
    elseif node isa GraphicsViewport
        shift = node.transform
        _tk_carets(node.content, ox + Int(node.x) + round(Int, shift.e), oy + Int(node.y) + round(Int, shift.f), found)
    end
    found
end

# The column and the line of the one caret that the last frame draws.
_tk_place(backend) = (caret = only(_tk_carets(last(rendered_output(backend)))); (caret[1] ÷ 10, caret[2] ÷ 18))

mutable struct _TextKeysPaneEditor
    document::Any
end

function test_text_keys()
@testset "The keys of the text domain through an editor" begin

@testset "a plain text in a history" begin
    block = make_text_block("foo bar baz\n    qux")
    history = UndoBuffer(block)
    set_selection!(history, Reference(FieldReferenceStep("content"), TextRangeReferenceStep(11, 11)))
    editor, backend = _tk_build(history)
    press!(events...) = _tk_press!(editor, backend, events...)
    @test _tk_place(backend) == (11, 0)
    # Ctrl+Backspace removes the word before the caret, and one undo takes it back.
    press!(_tk_key(:backspace; ctrl = true))
    @test get_flat_string(block) == "foo bar \n    qux"
    @test _tk_place(backend) == (8, 0)
    press!(_tk_key(:z; ctrl = true))
    @test get_flat_string(block) == "foo bar baz\n    qux"
    # Ctrl+Delete removes the word after the caret.
    press!(_tk_key(:home; ctrl = true), _tk_key(:right; ctrl = true))
    press!(_tk_key(:delete; ctrl = true))
    @test get_flat_string(block) == "foo baz\n    qux"
    @test _tk_place(backend) == (4, 0)
    # Home goes to the first character of the line that is not a space, and a
    # second press to the start of the line.
    press!(_tk_key(:end; ctrl = true), _tk_key(:home))
    @test _tk_place(backend) == (4, 1)
    press!(_tk_key(:home))
    @test _tk_place(backend) == (0, 1)
    # Shift+Tab takes the spaces away, and Tab puts them back.
    press!(_tk_key(:home))
    press!(_tk_typed('\t'; shift = true))
    @test get_flat_string(block) == "foo baz\nqux"
    @test _tk_place(backend) == (0, 1)
    press!(_tk_typed('\t'))
    @test get_flat_string(block) == "foo baz\n    qux"
    @test _tk_place(backend) == (4, 1)
    # Ctrl+A selects the whole text, and a typed key replaces it.
    press!(_tk_key(:a; ctrl = true), _tk_typed('x'))
    @test get_flat_string(block) == "x"
    @test _tk_place(backend) == (1, 0)
end

@testset "Page Down in a scroll pane moves the caret a page and keeps its row on the screen" begin
    block = make_text_block(join(("line $k" for k in 1:20), "\n"))
    history = UndoBuffer(WidgetScrollPane(block; size = Point2D(300, 90)))
    set_selection!(history, Reference(FieldReferenceStep("content"), FieldReferenceStep("content"),
                                      TextRangeReferenceStep(1, 1)))
    editor, backend = _tk_build(history)
    before = only(_tk_carets(last(rendered_output(backend))))
    _tk_press!(editor, backend, _tk_key(:page_down))
    @test get_flat_selection(block)[1] > 1
    @test only(_tk_carets(last(rendered_output(backend))))[2] == before[2]
    _tk_press!(editor, backend, _tk_key(:page_up))
    @test get_flat_selection(block)[1] == 1
end

@testset "a string of a JSON document" begin
    document = JsonObject("name" => JsonString("Alice Smith"))
    caret = only(filter(s -> endswith(string(strip_reference_types(s)), "entries[1].value.value{11}"),
                        collect_position_selections(document)))
    set_selection!(document, caret)
    editor, backend = _tr_editor(document, make_json_projection_example())
    _tr_press!(editor, backend, _tk_key(:backspace; ctrl = true))
    @test document.entries[1].value.value == "Alice "
end

@testset "the draft of the chat" begin
    assistant = Assistant(; llm = FakeLlm("ok"))
    editor, backend = _tr_editor(assistant, make_assistant_projection_example())
    texts = _tr_texts(_tr_window(backend))
    (x, y, _) = texts[findfirst(t -> occursin("type here", t[3]), texts)]
    _tr_press!(editor, backend, MouseClick(:left, x + 30, y + 8, ModifierKeys(); time = 0.0))
    foreach(c -> _tr_press!(editor, backend, _tk_typed(c)), "hello world")
    _tr_press!(editor, backend, _tk_key(:backspace; ctrl = true))
    @test assistant.draft.parts[end].content.value == "hello "
    _tr_press!(editor, backend, _tk_key(:a; ctrl = true))
    _tr_press!(editor, backend, _tk_typed('x'))
    @test assistant.draft.parts[end].content.value == "x"
end

@testset "the name of a tab" begin
    group = PaneGroup(PaneTab[PaneTab("notes today", PrimitiveString("body"))])
    tree = PaneTree(group)
    editor = _TextKeysPaneEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 1))
    function press!(event)
        projection = make_pane_projection_example(measure = _tk_measure())
        operation = read_intent(projection, print_document(projection, editor.document), event)
        operation === nothing || evaluate_operation(editor, operation)
    end
    press!(_tk_key(:f2))
    press!(_tk_key(:backspace; ctrl = true))
    @test get_pane_tab_title_string(group.tabs[1]) == "notes "
    press!(_tk_key(:a; ctrl = true))
    press!(_tk_typed('x'))
    @test get_pane_tab_title_string(group.tabs[1]) == "x"
    @test group.tabs[1].content.value == "body"
end

end # testset
end # function

export test_text_keys
