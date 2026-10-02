# The drag of a part, through the loop of a real editor.
#
# A part starts its drag at the press. The drag tracker keeps the path of the
# part, and gives the part each held move as `DragMove`, the release as `DragEnd`,
# and Escape, the loss of the focus and a lost release as `DragCancel`, by that
# path, wherever the pointer is. The part keeps its own state of the drag.

_dt_measure() = FixedMeasure(10, 18, 6, 0)

# The window `W` holds `document` at its origin.
function _dt_editor(document; projection = make_widget_projection_example(measure = _dt_measure()))
    scene = make_window_scene(document, "W"; width = 400, height = 300)
    opened = make_opened_window_projections(; measure = _dt_measure())
    composed = make_window_scene_projection(projection; opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed)
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend,
                    devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

# One event in the window `W`, and one frame.
_dt_send!(editor, backend, event) =
    (push_event!(backend, WindowInput(:W, event)); run_frame!(editor))

const _DT_NONE = ModifierKeys()
_dt_down!(editor, backend, x, y, time) =
    _dt_send!(editor, backend, MouseDown(:left, x, y, _DT_NONE; time))
_dt_held!(editor, backend, x, y, time) =
    _dt_send!(editor, backend, MouseMove(x, y, MouseButtons(:left), _DT_NONE; time))
_dt_up!(editor, backend, x, y, time) =
    _dt_send!(editor, backend, MouseUp(:left, x, y, _DT_NONE; time))

# The path of the part whose drag is on, or `nothing`.
_dt_drag_path(editor) = editor.document.content.drag_path

_dt_force(value) = value isa Cell ? _dt_force(value[]) : value

# Where `text` is drawn in the window `W`, or `nothing`.
_dt_place_of(editor, text) =
    _dt_find_text(_dt_force(_dt_force(_dt_force(get_iomap_output(editor.iomap)).windows)[1].content),
                  text)

function _dt_find_text(node, text, ox = 0, oy = 0)
    node = _dt_force(node)
    node === nothing && return nothing
    x = hasproperty(node, :x) ? ox + Int(_dt_force(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_dt_force(node.y)) : oy
    hasproperty(node, :text) && _dt_force(node.text) == text && return (x, y)
    for field in (:elements, :content)
        hasproperty(node, field) || continue
        children = _dt_force(getproperty(node, field))
        for child in (children isa AbstractVector ? children : (children,))
            found = _dt_find_text(child, text, x, y)
            found === nothing || return found
        end
    end
    nothing
end

# Two groups side by side: the left one holds the tabs `a` and `b`, the right one
# the tab `c`.
function _dt_pane_scene()
    tab(name) = PaneTab(name, WidgetLabel(name))
    left = PaneGroup(PaneTab[tab("a"), tab("b")])
    right = PaneGroup(PaneTab[tab("c")])
    (PaneTree(PaneSplit(:vertical, [left, right])), left, right)
end

_dt_pane_editor(tree) =
    _dt_editor(tree; projection = make_pane_projection_example(measure = _dt_measure()))

# A slider at (20, 20) on the left, and a button below it.
function _dt_slider_scene()
    slider = WidgetSlider(0.5; position = Point2D(20, 20), width = 240)
    button = WidgetButton("Other"; position = Point2D(20, 120))
    (WidgetComposite(Any[slider, button]), slider, button)
end

function test_drag_tracking()
@testset "a part keeps its drag, wherever the pointer is" begin

@testset "a slider thumb dragged past the end of the slider stops at the end, and the release over another widget ends the drag" begin
    root, slider, button = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dt_down!(editor, backend, 60, 28, 1.0)
    @test slider.dragging === true
    @test _dt_drag_path(editor) isa Reference
    # Far to the right of the slider and below it, over nothing.
    _dt_held!(editor, backend, 390, 200, 1.1)
    @test slider.value == 1.0
    # Back past the start of the slider, then over the button.
    _dt_held!(editor, backend, 5, 130, 1.2)
    @test slider.value == 0.0
    _dt_up!(editor, backend, 30, 130, 1.3)
    @test slider.dragging === false
    @test slider.value == 0.0
    @test _dt_drag_path(editor) === nothing
    @test button.pressed === false
end

@testset "Escape ends a drag with no change" begin
    root, slider, _ = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dt_down!(editor, backend, 60, 28, 1.0)
    _dt_held!(editor, backend, 200, 28, 1.1)
    @test slider.value != 0.5
    _dt_send!(editor, backend, KeyDown(:escape, _DT_NONE; time = 1.2))
    @test slider.value == 0.5
    @test slider.dragging === false
    @test _dt_drag_path(editor) === nothing
    # The next move with the button held moves nothing.
    _dt_held!(editor, backend, 250, 28, 1.3)
    @test slider.value == 0.5
end

@testset "a release that the window never gets ends a drag with no change" begin
    root, slider, _ = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dt_down!(editor, backend, 60, 28, 1.0)
    _dt_held!(editor, backend, 200, 28, 1.1)
    # A move with no button held: the release was lost.
    _dt_send!(editor, backend, MouseMove(210, 28; time = 1.2))
    @test slider.value == 0.5
    @test slider.dragging === false
    @test _dt_drag_path(editor) === nothing
end

@testset "the loss of the focus of the window ends a drag with no change" begin
    root, slider, _ = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dt_down!(editor, backend, 60, 28, 1.0)
    _dt_held!(editor, backend, 200, 28, 1.1)
    _dt_send!(editor, backend, WindowDefocus(; time = 1.2))
    @test slider.value == 0.5
    @test slider.dragging === false
    @test _dt_drag_path(editor) === nothing
end

@testset "a divider follows the pointer past the edge of its pane, and Escape puts its sizes back" begin
    split = WidgetSplitPane(:horizontal, Any[WidgetLabel("left"), WidgetLabel("right")];
                            sizes = [200, 199])
    editor, backend = _dt_editor(split)
    _dt_down!(editor, backend, 200, 50, 1.0)
    @test split.active_splitter == 1
    _dt_held!(editor, backend, 250, 50, 1.1)
    moved = collect(split.sizes)
    @test moved[1] > 200
    _dt_send!(editor, backend, KeyDown(:escape, _DT_NONE; time = 1.2))
    @test split.active_splitter == 0
    @test collect(split.sizes)[1] == 200
    # A second drag, released far outside the pane, keeps the new sizes.
    _dt_down!(editor, backend, 200, 50, 2.0)
    _dt_held!(editor, backend, 260, 290, 2.1)
    _dt_up!(editor, backend, 260, 290, 2.2)
    @test split.active_splitter == 0
    @test collect(split.sizes)[1] > 200
    @test _dt_drag_path(editor) === nothing
end

@testset "the part under the pointer lights during a drag" begin
    root, slider, button = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dt_down!(editor, backend, 60, 28, 1.0)
    # The thumb follows the pointer over the button, and the button lights.
    _dt_held!(editor, backend, 40, 130, 1.1)
    @test slider.dragging === true
    @test get_mouse_target(button) !== nothing
    @test get_mouse_target(slider) === nothing
    _dt_held!(editor, backend, 390, 280, 1.2)
    @test get_mouse_target(button) === nothing
    _dt_up!(editor, backend, 390, 280, 1.3)
end

@testset "a button that is pressed and dragged off is no longer drawn pressed" begin
    root, slider, button = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    # The pointer comes onto the button, as it does before a press.
    _dt_send!(editor, backend, MouseMove(30, 130; time = 0.9))
    _dt_down!(editor, backend, 30, 130, 1.0)
    @test button.pressed === true
    _dt_held!(editor, backend, 390, 280, 1.1)
    @test button.pressed === false
    _dt_up!(editor, backend, 390, 280, 1.2)
    @test button.pressed === false
end

# The drag goes to the part by its path, so the path passes the views of the
# panes, and each of them checks the type of each node on it.
@testset "a slider in a tab of a pane tree follows a held move, and the release and Escape end its drag" begin
    root, slider, _ = _dt_slider_scene()
    tree = PaneTree(PaneSplit(:vertical, [PaneGroup(PaneTab[PaneTab("a", root)]),
                                          PaneGroup(PaneTab[PaneTab("c", WidgetLabel("c"))])]))
    editor, backend = _dt_pane_editor(tree)
    # The tab draws the composite at an offset: the place of the button label in
    # the tab, less its place in a window of its own.
    alone, _ = _dt_editor(_dt_slider_scene()[1])
    place, alone_place = _dt_place_of(editor, "Other"), _dt_place_of(alone, "Other")
    @test place !== nothing && alone_place !== nothing
    if place !== nothing && alone_place !== nothing
        dx, dy = place[1] - alone_place[1], place[2] - alone_place[2]
        x, y = 60 + dx, 28 + dy
        _dt_send!(editor, backend, MouseMove(x, y; time = 0.9))
        _dt_down!(editor, backend, x, y, 1.0)
        @test slider.dragging === true
        @test _dt_drag_path(editor) isa Reference
        _dt_held!(editor, backend, 390, 280, 1.1)
        @test slider.value == 1.0
        _dt_held!(editor, backend, 2, 280, 1.2)
        @test slider.value == 0.0
        _dt_up!(editor, backend, 2, 280, 1.3)
        @test slider.dragging === false
        @test _dt_drag_path(editor) === nothing
        # Escape ends a drag with no change.
        _dt_send!(editor, backend, MouseMove(x, y; time = 1.9))
        _dt_down!(editor, backend, x, y, 2.0)
        _dt_held!(editor, backend, x + 60, y, 2.1)
        @test slider.value != 0.0
        _dt_send!(editor, backend, KeyDown(:escape, _DT_NONE; time = 2.2))
        @test slider.value == 0.0
        @test slider.dragging === false
        @test _dt_drag_path(editor) === nothing
    end
end

@testset "a tab dragged past the small move drops into the group under the pointer" begin
    tree, left, right = _dt_pane_scene()
    editor, backend = _dt_pane_editor(tree)
    place = _dt_place_of(editor, "b")
    @test place !== nothing
    if place !== nothing
        x, y = place[1] + 3, place[2] + 4
        _dt_send!(editor, backend, MouseMove(x, y; time = 0.9))
        _dt_down!(editor, backend, x, y, 1.0)
        # The press keeps the tab, and no drag is on before the small move.
        @test tree.drag !== nothing && tree.drag.started == false
        @test _dt_drag_path(editor) === nothing
        _dt_held!(editor, backend, x + 12, y, 1.1)
        @test tree.drag.started
        @test _dt_drag_path(editor) isa Reference
        # Over the middle of the right group: the tab would land there, and the
        # rectangle of the drop zone shows it.
        _dt_held!(editor, backend, 300, 150, 1.2)
        @test tree.drag.target === right
        _dt_up!(editor, backend, 300, 150, 1.3)
        @test tree.drag === nothing
        @test _dt_drag_path(editor) === nothing
        @test [get_pane_tab_title_string(right.tabs[i]) for i in 1:length(right.tabs)] == ["c", "b"]
        @test length(left.tabs) == 1
    end
end

@testset "a press on a tab that does not move is a click, and Escape drops a tab nowhere" begin
    tree, left, right = _dt_pane_scene()
    editor, backend = _dt_pane_editor(tree)
    place = _dt_place_of(editor, "b")
    @test place !== nothing
    if place !== nothing
        x, y = place[1] + 3, place[2] + 4
        _dt_send!(editor, backend, MouseMove(x, y; time = 0.9))
        _dt_down!(editor, backend, x, y, 1.0)
        _dt_up!(editor, backend, x, y, 1.05)
        @test tree.drag === nothing
        @test get_pane_shown_tab_index(left) == 2
        @test length(left.tabs) == 2
        # A drag that Escape ends moves no tab.
        _dt_down!(editor, backend, x, y, 2.0)
        _dt_held!(editor, backend, x + 12, y, 2.1)
        _dt_held!(editor, backend, 300, 150, 2.2)
        _dt_send!(editor, backend, KeyDown(:escape, _DT_NONE; time = 2.3))
        @test tree.drag === nothing
        @test length(left.tabs) == 2 && length(right.tabs) == 1
    end
end

end # @testset
end # test_drag_tracking
