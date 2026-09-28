# The tooltip window, through the loop of a real editor.
#
# The tracking screen recognizes the dwell, the target tracker sends it to the
# part under the pointer, the part answers from its own gesture table, and the
# wrapper that keeps the tooltip window opens the window. A tooltip is a window of
# its own on every backend — PAR-MANY-WINDOWS — so the proof is the window that
# appears, not the operation that comes back.

# A group that can say something, with a label that says something and one that
# says nothing inside it.
_tw_labels(; group = nothing) = WidgetComposite(Any[
    WidgetLabel("speaks"; tooltip = "what this label is for"),
    WidgetLabel("silent"; position = Point2D(0, 40)),
]; tooltip = group)

_tw_measure() = FixedMeasure(10, 18, 6, 0)

# The window `W` at (100, 100) holds `document`, and the window `V`, when asked
# for, holds `other` at (600, 100).
function _tw_editor(document = _tw_labels(); other = nothing)
    scene = make_window_scene(document, "W"; width = 400, height = 300)
    other === nothing ||
        push!(scene.windows, WindowDocument(; id = :V, title = "V", x = 600, y = 100,
                                              width = 300, height = 200, content = other))
    composed = make_window_scene_projection(
        make_widget_projection_example(measure = _tw_measure());
        opened_window_projections = make_opened_window_projections(;
            content = Pair{Type,Any}[make_natural_tooltip_row(measure = _tw_measure())],
            measure = _tw_measure()))
    document, projection = make_tracking_screen(scene, composed;
                                                inner_wrappers = [wrap_tooltip_window])
    backend = HeadlessBackend()
    editor = Editor(backend, document, projection, Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend, scene)
end

# One event in the window `window`, and one frame. The frame reads every timer
# that is due, and the times of these events are long past, so the wait of the
# dwell ends in the same frame.
_tw_send!(editor, backend, event; window = :W) =
    (push_event!(backend, WindowInput(window, event)); run_frame!(editor))

_tw_rest!(editor, backend, x, y, time; window = :W) =
    _tw_send!(editor, backend, MouseMove(x, y; time = time); window)

_tw_tooltips(scene) = [window for window in scene.windows if window.style === :tooltip]

# Every string a printed window holds, so a case can ask what was drawn rather
# than what was stored.
_tw_force(value) = value isa Cell ? _tw_force(value[]) : value

function _tw_drawn_strings(node, found = String[])
    node = _tw_force(node)
    node === nothing && return found
    if hasproperty(node, :elements)
        for element in node.elements
            _tw_drawn_strings(element, found)
        end
    elseif hasproperty(node, :text) && _tw_force(node.text) isa AbstractString
        push!(found, String(_tw_force(node.text)))
    elseif hasproperty(node, :content)
        _tw_drawn_strings(node.content, found)
    end
    found
end

function _tw_drawn_tooltip(editor)
    output = _tw_force(get_iomap_output(editor.iomap))
    windows = _tw_force(output.windows)
    _tw_drawn_strings(windows[length(windows)].content)
end

function test_tooltip_window()
@testset "the tooltip window" begin

@testset "a move alone opens nothing" begin
    editor, backend, scene = _tw_editor()
    # A move an hour from now: the wait of its dwell can not end in this frame.
    _tw_send!(editor, backend, MouseMove(20, 10; time = time() + 3600.0))
    @test isempty(_tw_tooltips(scene))
end

@testset "a dwell on a part that says something opens a window of its own" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    tips = _tw_tooltips(scene)
    @test length(tips) == 1
    tip = only(tips)
    # Beside the pointer, in the coordinates of the screen: the window is at
    # (100, 100).
    @test (tip.x, tip.y) == (100 + 20 + 16, 100 + 10 + 20)
    @test tip.content isa TooltipContent
    @test tip.content.shown == 1
    title, content = only(tip.content.layers)
    @test title == "WidgetLabel"
    @test content.value == "what this label is for"
    # It says its bounds rather than a size: it is printed at the maximum, and the
    # backend gives it the extent of what it printed, never below the minimum.
    @test tip.minimum_size == (120, 32)
    @test tip.maximum_size == (560, 400)
    # The state of the wrapper keeps what the window shows.
    state = editor.document.content
    @test state isa TooltipWindowState
    @test state.shown == 1
end

@testset "the window draws what the part said" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    @test any(text -> occursin("what this label is for", text), _tw_drawn_tooltip(editor))
end

@testset "a dwell on a part that says nothing opens none" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 50, 1.0)
    @test isempty(_tw_tooltips(scene))
end

@testset "a dwell opens a tooltip in any window" begin
    editor, backend, scene = _tw_editor(; other = _tw_labels())
    _tw_rest!(editor, backend, 20, 10, 1.0; window = :V)
    tip = only(_tw_tooltips(scene))
    @test (tip.x, tip.y) == (600 + 20 + 16, 100 + 10 + 20)
    @test only(tip.content.layers)[2].value == "what this label is for"
end

@testset "a move on the part keeps the window, and a move off closes it" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    _tw_send!(editor, backend, MouseMove(22, 11; time = 1.1))
    @test length(_tw_tooltips(scene)) == 1
    _tw_send!(editor, backend, MouseMove(20, 50; time = 1.2))
    @test isempty(_tw_tooltips(scene))
    @test editor.document.content.shown == 0
end

@testset "a press closes the window" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    _tw_send!(editor, backend, MouseDown(:left, 20, 10, ModifierKeys(); time = 1.1))
    @test isempty(_tw_tooltips(scene))
end

@testset "Escape closes the window and nothing else" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    _tw_send!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 1.1))
    @test isempty(_tw_tooltips(scene))
    # The wrapper takes the Escape, so the editor does not quit.
    @test !(editor.operation isa QuitEditorOperation)
end

@testset "another key passes on and leaves the window open" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    _tw_send!(editor, backend, KeyDown(:a, ModifierKeys(); time = 1.1))
    @test length(_tw_tooltips(scene)) == 1
end

@testset "each part around adds its layer, and F2 and Shift+F2 show more and fewer" begin
    editor, backend, scene = _tw_editor(_tw_labels(; group = "the group"))
    _tw_rest!(editor, backend, 20, 10, 1.0)
    tip = only(_tw_tooltips(scene))
    # The nearest part first, and the group after it; the window shows one.
    @test [title for (title, _) in tip.content.layers] == ["WidgetLabel", "WidgetComposite"]
    @test tip.content.shown == 1
    _tw_send!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 1.1))
    tip = only(_tw_tooltips(scene))
    @test tip.content.shown == 2
    # The window stays where it opened.
    @test (tip.x, tip.y) == (136, 130)
    drawn = _tw_drawn_tooltip(editor)
    @test any(text -> occursin("what this label is for", text), drawn)
    @test any(text -> occursin("the group", text), drawn)
    # With every layer shown, F2 changes nothing.
    _tw_send!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 1.2))
    @test only(_tw_tooltips(scene)).content.shown == 2
    _tw_send!(editor, backend, KeyDown(:f2, ModifierKeys(shift = true); time = 1.3))
    @test only(_tw_tooltips(scene)).content.shown == 1
end

@testset "the group speaks for a part that says nothing" begin
    editor, backend, scene = _tw_editor(_tw_labels(; group = "the group"))
    _tw_rest!(editor, backend, 20, 50, 1.0)
    tip = only(_tw_tooltips(scene))
    @test only(tip.content.layers)[2].value == "the group"
end

@testset "a command runs the binding with no pointer, and the window opens at the part" begin
    editor, backend, scene = _tw_editor()
    # The path of the label from the root of the editor: through the gesture
    # tracker, the tooltip wrapper and the target tracker to the screen.
    place = extend_reference(EmptyReference(),
                             FieldReferenceStep("content"), FieldReferenceStep("content"),
                             FieldReferenceStep("content"), FieldReferenceStep("windows"),
                             ElementReferenceStep(1), FieldReferenceStep("content"),
                             FieldReferenceStep("elements"), ElementReferenceStep(1))
    label = evaluate_reference(editor.document, place)
    @test label isa WidgetLabel
    binding = only(filter(binding -> binding.domain == "tooltip",
                          get_document_gesture_bindings(WidgetLabel)))
    operation = read_rooted_operation(editor, place, binding.operation(label, nothing))
    @test operation !== nothing
    evaluate_operation(editor, operation)
    tip = only(_tw_tooltips(scene))
    @test only(tip.content.layers)[2].value == "what this label is for"
    # With no point, the window opens beside the image of the part, in the window
    # at (100, 100).
    # @broken: no projection that ends in graphics maps a widget forward to its
    # image, so the window opens at the corner of the screen
    # (plan/pending/the-forward-image-of-a-part.md).
    @test_broken tip.x >= 100 + 16 && tip.y >= 100 + 20
end

end # @testset
end # function
