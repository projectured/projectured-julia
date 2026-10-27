# The draft of an assistant takes a press anywhere on its field: a press on its
# text places the caret there, and a press on the field beside the text places the
# caret at the end of what is written.

function _draft_press_editor(document, projection)
    backend = HeadlessBackend()
    scene = make_window_scene(document, "W"; width = 1200, height = 800)
    editor = Editor(scene, make_window_scene_projection(projection);
                    backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

# The assistant alone, its transcript and its draft each through its chain of
# widgets to graphics.
function _make_draft_press_projection(; measure = FontFileMeasure())
    widget_graphics = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure)
    rows = RecursiveProjection(TypeDispatchingProjection(vcat(widget_graphics.dispatch,
        Pair{Type,Any}[make_conversation_draft_row(; measure), make_conversation_row(; measure)])))
    ChainingProjection(RecursiveProjection(AssistantToWidgetSplitPane()), rows)
end

function _press_draft!(editor, backend, event)
    push_event!(backend, WindowInput(:W, event))
    run_frame!(editor)
end

# Every text that the window drew, with its place.
function _collect_draft_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    node isa Cell && return _collect_draft_texts(node[], ox, oy, found)
    if node isa GraphicsCanvas
        for element in node.elements
            _collect_draft_texts(element, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _collect_draft_texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), node.text))
    end
    found
end

"""
    test_draft_press()

A press on the text of the draft of an assistant places the caret where it was
aimed, and a press on the field of the draft beside its text places the caret at
the end of what is written.
"""
function test_draft_press()
    @testset "a press on the draft of an assistant" begin
        a = Assistant(; llm = FakeLlm("ok"))
        (editor, backend) = _draft_press_editor(a, _make_draft_press_projection())
        press(event) = _press_draft!(editor, backend, event)
        none = ModifierKeys()
        texts() = _collect_draft_texts(last(rendered_output(backend)).windows[1].content)
        function caret()
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            (last(steps).start, last(steps).stop)
        end
        drawn = texts()
        (x, y, _) = drawn[findfirst(t -> occursin("type here", t[3]), drawn)]
        press(MouseClick(:left, x + 30, y + 8, none; time = 0.0))
        foreach(c -> press(KeyPress(c; time = 0.0)), "hello")
        press(KeyDown(:left, none; time = 0.0))
        press(KeyDown(:left, none; time = 0.0))
        @test caret() == (3, 3)

        # A press on the field, far to the right of the text.
        drawn = texts()
        (x, y, _) = drawn[findfirst(t -> t[3] == "hello", drawn)]
        press(MouseClick(:left, x + 400, y + 8, none; time = 0.0))
        @test a.draft.parts[end].content.value == "hello"
        @test caret() == (5, 5)
    end
end
