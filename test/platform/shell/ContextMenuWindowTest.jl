# The context menu window, through the loop of a real editor.
#
# The tracking screen recognizes the right click, the screen gives it to the part
# at its point, the part and the parts around it answer from their own gesture
# tables, and the wrapper that keeps the context menu window opens the window. A
# menu is a window of its own on every backend — PAR-MANY-WINDOWS — so the proof is
# the window that appears, not the operation that comes back.

_cm_measure() = FixedMeasure(10, 18, 6, 0)

_cm_menu(labels...) = WidgetMenu(Any[WidgetMenuItem(label) for label in labels])

# A label with a menu of its own, and below it a label with none.
_cm_parts(; menu = _cm_menu("Cut", "Copy")) = WidgetComposite(Any[
    WidgetContextMenu(WidgetLabel("has a menu"), menu),
    WidgetLabel("has none"; position = Point2D(0, 40)),
])

# The window `W` at (100, 100) holds `document`, drawn with `projection`.
function _cm_editor(document = _cm_parts();
                    projection = make_widget_projection_example(measure = _cm_measure()))
    scene = make_window_scene(document, "W"; width = 400, height = 300)
    opened = make_opened_window_projections(; measure = _cm_measure())
    composed = make_window_scene_projection(projection;
                                            opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed;
        inner_wrappers = [wrap_context_menu_window])
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend,
                    devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend, scene)
end

# One event in the window `window`, and one frame.
_cm_send!(editor, backend, event; window = :W) =
    (push_event!(backend, WindowInput(window, event)); run_frame!(editor))

# A press and a release of `button` in place: the gesture tracker makes a click of
# them, in the frame of the release.
function _cm_click!(editor, backend, button::Symbol, x, y, time; window = :W)
    none = ModifierKeys()
    _cm_send!(editor, backend, MouseDown(button, x, y, none; time = time); window)
    _cm_send!(editor, backend, MouseUp(button, x, y, none; time = time + 0.05); window)
end

_cm_menus(scene) = [window for window in scene.windows if window.style === :popup]

# The labels of the items of a menu, the marks of the layers among them.
_cm_labels(menu) = [string(item.action.label) for item in menu.elements
                    if item isa WidgetMenuItem]

_cm_force(value) = value isa Cell ? _cm_force(value[]) : value

# The state of the context menu wrapper: one `.content` below the drag tracker,
# which is one below the gesture tracker at the root of the editor's document.
_cm_state(editor) = editor.document.content.content

# The drawn content of the window `id`, as the editor printed it.
function _cm_drawn_window(editor, scene, id::Symbol)
    windows = _cm_force(_cm_force(get_iomap_output(editor.iomap)).windows)
    index = findfirst(window -> window.id === id, collect(scene.windows))
    _cm_force(windows[index].content)
end

# Where `text` is drawn in `node`, in the frame of `node`, or `nothing`.
function _cm_place_of(node, text, ox = 0, oy = 0)
    node = _cm_force(node)
    node === nothing && return nothing
    x = hasproperty(node, :x) ? ox + Int(_cm_force(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_cm_force(node.y)) : oy
    hasproperty(node, :text) && _cm_force(node.text) == text && return (x, y)
    if hasproperty(node, :elements)
        for element in _cm_force(node.elements)
            found = _cm_place_of(element, text, x, y)
            found === nothing || return found
        end
    end
    nothing
end

function test_context_menu_window()
@testset "the context menu window" begin

@testset "a right click on a part with a menu opens the menu at the pointer" begin
    editor, backend, scene = _cm_editor()
    _cm_click!(editor, backend, :right, 20, 10, 1.0)
    window = only(_cm_menus(scene))
    # At the point of the click, in the coordinates of the screen: the window is
    # at (100, 100).
    @test (window.x, window.y) == (100 + 20, 100 + 10)
    @test window.auto_dismiss
    @test _cm_labels(window.content) == ["Cut", "Copy"]
    # The state of the wrapper keeps what the window shows.
    state = _cm_state(editor)
    @test state isa ContextMenuWindowState
    @test state.shown == 1
    @test [title for (title, _) in state.layers] == ["WidgetContextMenu"]
end

# A menu has no position of its own, so a composite places it by the position of
# its part, and the menu stands where the part stands.
@testset "a part that has its own position lights, and a right click on it opens its menu" begin
    menu = WidgetContextMenu(WidgetLabel("placed"; position = Point2D(40, 60)), _cm_menu("Cut", "Copy"))
    editor, backend, scene = _cm_editor(WidgetComposite(Any[menu]))
    (x, y) = _cm_place_of(_cm_drawn_window(editor, scene, :W), "placed")
    @test (x, y) == (40, 60)
    _cm_send!(editor, backend, MouseMove(x + 2, y + 2; time = 0.9))
    @test get_mouse_target(menu) !== nothing
    _cm_click!(editor, backend, :right, x + 2, y + 2, 1.0)
    @test _cm_labels(only(_cm_menus(scene)).content) == ["Cut", "Copy"]
    # Before the part, where nothing is drawn, the menu is not under the pointer.
    _cm_send!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 1.5))
    _cm_send!(editor, backend, MouseMove(5, 5; time = 2.0))
    @test get_mouse_target(menu) === nothing
    _cm_click!(editor, backend, :right, 5, 5, 2.1)
    @test isempty(_cm_menus(scene))
end

@testset "a right click on a part with no menu opens none" begin
    editor, backend, scene = _cm_editor()
    _cm_click!(editor, backend, :right, 20, 50, 1.0)
    @test isempty(_cm_menus(scene))
end

@testset "a left click opens no menu" begin
    editor, backend, scene = _cm_editor()
    _cm_click!(editor, backend, :left, 20, 10, 1.0)
    @test isempty(_cm_menus(scene))
end

# The window menu of the shell is the outermost layer, so F2 reaches it from any
# part of the window.
@testset "the window menu is the outermost layer; F2 shows more, Shift+F2 fewer" begin
    shell = WidgetShell(_cm_parts(); size = Point2D(400, 300),
                        context_menu = _cm_menu("Close window"))
    editor, backend, scene = _cm_editor(shell)
    (x, y) = _cm_place_of(_cm_drawn_window(editor, scene, :W), "has a menu")
    _cm_click!(editor, backend, :right, x + 2, y + 2, 1.0)
    state = _cm_state(editor)
    @test [title for (title, _) in state.layers] == ["WidgetContextMenu", "WidgetShell"]
    # The nearest menu shows first, alone and with no mark.
    @test _cm_labels(only(_cm_menus(scene)).content) == ["Cut", "Copy"]
    _cm_send!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 1.2))
    window = only(_cm_menus(scene))
    @test state.shown == 2
    # Each layer starts with the mark of its part, and a separator stands between
    # the two.
    @test _cm_labels(window.content) ==
          ["WidgetContextMenu", "Cut", "Copy", "WidgetShell", "Close window"]
    elements = collect(window.content.elements)
    @test count(element -> element isa WidgetSeparator, elements) == 1
    @test !first(item for item in elements if item isa WidgetMenuItem).enabled
    # The window stays where it opened.
    @test (window.x, window.y) == (100 + x + 2, 100 + y + 2)
    # With every layer shown, F2 changes nothing.
    _cm_send!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 1.3))
    @test state.shown == 2
    _cm_send!(editor, backend, KeyDown(:f2, ModifierKeys(shift = true); time = 1.4))
    @test state.shown == 1
    @test _cm_labels(only(_cm_menus(scene)).content) == ["Cut", "Copy"]
end

@testset "the window menu opens where no part has a menu" begin
    shell = WidgetShell(_cm_parts(); size = Point2D(400, 300),
                        context_menu = _cm_menu("Close window"))
    editor, backend, scene = _cm_editor(shell)
    (x, y) = _cm_place_of(_cm_drawn_window(editor, scene, :W), "has none")
    _cm_click!(editor, backend, :right, x + 2, y + 2, 1.0)
    @test [title for (title, _) in _cm_state(editor).layers] == ["WidgetShell"]
    @test _cm_labels(only(_cm_menus(scene)).content) == ["Close window"]
end

# A right click moves no selection: the row under the pointer is lit, and the
# binding of the part computes the menu from that part, so the menu needs no
# selection.
@testset "a right click on a row selects no row, and the menu around it opens" begin
    list = WidgetList(["one", "two", "three"]; width = 200)
    editor, backend, scene = _cm_editor(WidgetComposite(Any[
        WidgetContextMenu(list, _cm_menu("Remove"))]))
    @test get_widget_list_selected(list) == 0
    (x, y) = _cm_place_of(_cm_drawn_window(editor, scene, :W), "two")
    _cm_click!(editor, backend, :right, x + 2, y + 2, 1.0)
    @test get_widget_list_selected(list) == 0
    @test _cm_labels(only(_cm_menus(scene)).content) == ["Remove"]
    # A left click on the same row selects it, and its press closes the menu.
    _cm_click!(editor, backend, :left, x + 2, y + 2, 2.0)
    @test isempty(_cm_menus(scene))
    @test get_widget_list_selected(list) == 2
end

@testset "Escape closes the window and nothing else" begin
    editor, backend, scene = _cm_editor()
    _cm_click!(editor, backend, :right, 20, 10, 1.0)
    @test length(_cm_menus(scene)) == 1
    _cm_send!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 1.2))
    @test isempty(_cm_menus(scene))
    # The Escape closes the popup, so the editor does not quit.
    @test !(editor.operation isa QuitEditorOperation)
    # The state forgets the window that is gone.
    @test _cm_state(editor).shown == 0
end

@testset "a choice runs the item and closes the window" begin
    chosen = Ref(0)
    menu = WidgetMenu(Any[WidgetMenuItem("Count"; action = editor -> (chosen[] += 1))])
    editor, backend, scene = _cm_editor(_cm_parts(; menu))
    _cm_click!(editor, backend, :right, 20, 10, 1.0)
    window = only(_cm_menus(scene))
    (x, y) = _cm_place_of(_cm_drawn_window(editor, scene, window.id), "Count")
    _cm_click!(editor, backend, :left, x + 2, y + 2, 2.0; window = window.id)
    @test chosen[] == 1
    @test isempty(_cm_menus(scene))
    @test _cm_state(editor).shown == 0
end

@testset "a command runs the binding with no pointer, and the menu opens below" begin
    menu = _cm_menu("Cut", "Copy")
    wrap = WidgetContextMenu(WidgetButton("Run"; size = Point2D(80, 24)), menu)
    # The wrapper is as tall as what it draws, at the top left of the window.
    twin = WidgetContextMenu(WidgetButton("Run"; size = Point2D(80, 24)), menu)
    alone = print_document(make_widget_projection_example(measure = _cm_measure()), twin)
    height = Int(unwrap_cell(get_iomap_output(alone)).h[])
    editor, backend, scene = _cm_editor(WidgetComposite(Any[wrap]))
    # The path of the wrapper from the root of the editor: through the gesture
    # tracker, the drag tracker and the context menu wrapper to the screen.
    place = extend_reference(EmptyReference(),
                             FieldReferenceStep("content"), FieldReferenceStep("content"),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("windows"), ElementReferenceStep(1),
                             FieldReferenceStep("content"),
                             FieldReferenceStep("elements"), ElementReferenceStep(1))
    @test evaluate_reference(editor.document, place) === wrap
    binding = only(filter(binding -> binding.domain == "context menu",
                          get_document_gesture_bindings(WidgetContextMenu)))
    operation = read_rooted_operation(editor, place, binding.operation(wrap, nothing))
    @test operation !== nothing
    evaluate_operation(editor, operation)
    window = only(_cm_menus(scene))
    @test _cm_labels(window.content) == ["Cut", "Copy"]
    # With no point, the window stands below the wrapper, with the left edges
    # aligned and a gap of 4 pixels.
    @test (window.x, window.y) == (100, 100 + height + 4)
end

end # @testset
end # function
