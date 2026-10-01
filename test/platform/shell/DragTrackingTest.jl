# The drag of a part, through the loop of a real editor.
#
# A part starts its drag at the press. The drag tracker keeps the path of the
# part, and gives the part each held move as `DragMove`, the release as `DragEnd`,
# and Escape, the loss of the focus and a lost release as `DragCancel`, by that
# path, wherever the pointer is. The part keeps its own state of the drag.

_dt_measure() = FixedMeasure(10, 18, 6, 0)

# The window `W` holds `document` at its origin.
function _dt_editor(document)
    projection = make_widget_projection_example(measure = _dt_measure())
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

end # @testset
end # test_drag_tracking
