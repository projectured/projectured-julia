# The tooltip window, through the loop of a real editor.
#
# The tracking screen recognizes the dwell, the screen gives it to the part at its
# point, the part answers from its own gesture table, and the wrapper that keeps
# the tooltip window opens the window. A tooltip is a window of its own on every
# backend — PAR-MANY-WINDOWS — so the proof is the window that appears, not the
# operation that comes back.

# A group that can say something, with a label that says something and one that
# says nothing inside it.
_tw_labels(; group = nothing) = WidgetComposite(Any[
    WidgetLabel("speaks"; tooltip = "what this label is for"),
    WidgetLabel("silent"; position = Point2D(0, 40)),
]; tooltip = group)

_tw_measure() = FixedMeasure(10, 18, 6, 0)

# The window `W` at (100, 100) holds `document`, drawn with `projection`, and the
# window `V`, when asked for, holds `other` at (600, 100).
function _tw_editor(document = _tw_labels(); other = nothing,
                    projection = make_widget_projection_example(measure = _tw_measure()))
    scene = make_window_scene(document, "W"; width = 400, height = 300)
    other === nothing ||
        push!(scene.windows, WindowDocument(; id = :V, title = "V", x = 600, y = 100,
                                              width = 300, height = 200, content = other))
    composed = make_window_scene_projection(
        projection;
        opened_window_projections = make_opened_window_projections(;
            content = Pair{Type,Any}[make_natural_tooltip_row(measure = _tw_measure())],
            measure = _tw_measure()))
    document, projection = make_tracking_screen(scene, composed;
                                                inner_wrappers = [wrap_tooltip_window])
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend,
                    devices = Device[Keyboard(), Mouse()])
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

# The state of the tooltip wrapper: one `.content` below the drag tracker,
# which is one below the gesture tracker at the root of the editor's document.
_tw_state(editor) = editor.document.content.content

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
    state = _tw_state(editor)
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

# A dwell goes by its position, as a click does: each container gives it to the
# child at its point, not to the child that the selection names.
@testset "a dwell goes to the part at its point, not to the selected part" begin
    labels = _tw_labels()
    second = ConcreteReference(FieldReferenceStep("elements"),
                               ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
    replace_selection!(labels, annotate_reference_types(labels, second))
    editor, backend, scene = _tw_editor(labels)
    _tw_rest!(editor, backend, 20, 10, 1.0)
    @test only(only(_tw_tooltips(scene)).content.layers)[2].value == "what this label is for"
end

# A pane that scrolls gives the dwell to its content in the frame of the content,
# so the part drawn at the point answers, and the window opens beside the pointer.
@testset "a dwell in a scrolled pane reaches the part drawn at its point" begin
    content = WidgetComposite(Any[
        WidgetLabel("silent"),
        WidgetLabel("lower"; tooltip = "the lower label", position = Point2D(0, 40)),
    ])
    pane = WidgetScrollPane(content; size = Point2D(200, 30))
    getfield(pane, :scroll_position)[] = Point2D(0, 40)
    editor, backend, scene = _tw_editor(pane)
    _tw_rest!(editor, backend, 20, 10, 1.0)
    tip = only(_tw_tooltips(scene))
    @test only(tip.content.layers)[2].value == "the lower label"
    @test (tip.x, tip.y) == (100 + 20 + 16, 100 + 10 + 20)
end

@testset "a move on the part keeps the window, and a move off closes it" begin
    editor, backend, scene = _tw_editor()
    _tw_rest!(editor, backend, 20, 10, 1.0)
    _tw_send!(editor, backend, MouseMove(22, 11; time = 1.1))
    @test length(_tw_tooltips(scene)) == 1
    _tw_send!(editor, backend, MouseMove(20, 50; time = 1.2))
    @test isempty(_tw_tooltips(scene))
    @test _tw_state(editor).shown == 0
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

@testset "a command runs the binding with no pointer, and the window opens below the part" begin
    # A button of its own size, so its box is exact: 80 by 24 at (10, 30) of the
    # window at (100, 100).
    button = WidgetButton("Run"; size = Point2D(80, 24), position = Point2D(10, 30),
                          tooltip = "what this button is for")
    editor, backend, scene = _tw_editor(WidgetComposite(Any[button]))
    # The path of the button from the root of the editor: through the gesture
    # tracker, the drag tracker and the tooltip wrapper to the screen.
    place = extend_reference(EmptyReference(),
                             FieldReferenceStep("content"), FieldReferenceStep("content"),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("windows"), ElementReferenceStep(1),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("elements"), ElementReferenceStep(1))
    @test evaluate_reference(editor.document, place) === button
    binding = only(filter(binding -> binding.domain == "tooltip",
                          get_document_gesture_bindings(WidgetButton)))
    operation = read_rooted_operation(editor, place, binding.operation(button, nothing))
    @test operation !== nothing
    evaluate_operation(editor, operation)
    tip = only(_tw_tooltips(scene))
    @test only(tip.content.layers)[2].value == "what this button is for"
    # With no point, the window stands below the button, with the left edges
    # aligned and a gap of 4 pixels.
    @test (tip.x, tip.y) == (100 + 10, 100 + 30 + 24 + 4)
end

@testset "a command opens the tooltip below a label, which has the size of its text" begin
    # A label with no size of its own fits its text in the window, so the window
    # of its tooltip stands below the text, not at the bottom of the window.
    label = WidgetLabel("Name"; position = Point2D(10, 30), tooltip = "what this label is for")
    alone = print_document(make_widget_projection_example(measure = _tw_measure()), WidgetLabel("Name"))
    height = Int(unwrap_cell(get_iomap_output(alone)).h[])
    @test height < 300
    editor, backend, scene = _tw_editor(WidgetComposite(Any[label]))
    place = extend_reference(EmptyReference(),
                             FieldReferenceStep("content"), FieldReferenceStep("content"),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("windows"), ElementReferenceStep(1),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("elements"), ElementReferenceStep(1))
    @test evaluate_reference(editor.document, place) === label
    binding = only(filter(binding -> binding.domain == "tooltip",
                          get_document_gesture_bindings(WidgetLabel)))
    evaluate_operation(editor, read_rooted_operation(editor, place, binding.operation(label, nothing)))
    tip = only(_tw_tooltips(scene))
    @test (tip.x, tip.y) == (100 + 10, 100 + 30 + height + 4)
end

@testset "a command opens the signature of a Julia function below the function" begin
    # A pane of Julia source, drawn as syntax, text and graphics; the layout and
    # the box read the same font files. A line follows the function, so the image
    # of the function is the region of its rows and not the whole text.
    source = parse_julia("function add(a, b)\n    a + b\nend\nx = 1")
    julia = ChainingProjection(RecursiveProjection(JuliaToSyntax()), RecursiveProjection(SyntaxToText()),
                               TextToGraphics(measure = FontFileMeasure()))
    editor, backend, scene = _tw_editor(source; projection = julia)
    inside = strip_reference_types(first(search_references(source, node -> node isa JuliaFunction)))
    window_content = extend_reference(EmptyReference(), FieldReferenceStep("windows"),
                                      ElementReferenceStep(1), FieldReferenceStep("content"))
    # From the root of the editor, and from the state of the tooltip wrapper.
    place = concat_references(extend_reference(EmptyReference(), FieldReferenceStep("content"),
                                               FieldReferenceStep("content"),
                                               FieldReferenceStep("content")),
                              concat_references(window_content, inside))
    from_wrapper = concat_references(extend_reference(EmptyReference(), FieldReferenceStep("content")),
                                     concat_references(window_content, inside))
    function_ = evaluate_reference(editor.document, place)
    @test function_ isa JuliaFunction
    binding = only(filter(binding -> binding.name == "Show the signature",
                          get_document_gesture_bindings(JuliaFunction)))
    operation = read_rooted_operation(editor, place, binding.operation(function_, nothing))
    @test operation !== nothing
    evaluate_operation(editor, operation)
    tip = only(_tw_tooltips(scene))
    # The window stands below the function, where the place of the function says:
    # the operation carries the path of the function, not of the whole document.
    # One more hop than `wrapper` used to need, past the drag tracker that now
    # sits between the gesture tracker and the tooltip wrapper.
    wrapper = editor.projection.inner.inner
    below = find_part_place(wrapper, editor.iomap.child_iomap.child_iomap, from_wrapper)
    @test below !== nothing
    @test (tip.x, tip.y) == (below[1], below[2] + 4)
    # And above the bottom of the text, which `x = 1` ends.
    text = find_reference_box(get_iomap_output(editor.iomap.child_iomap), window_content)
    @test tip.y < text.y + text.height
end

end # @testset
end # function
