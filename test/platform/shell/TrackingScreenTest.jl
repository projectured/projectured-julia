# A press and a release on a button, through the loop of a real editor. The
# tracking screen of the screen package recognizes the click; the editor itself
# recognizes none, so a screen with no tracker gets no click.

function _ts_editor(tracking::Bool)
    count = Ref(0)
    button = WidgetButton("Go"; size = Point2D(120, 40), action = (_editor) -> (count[] += 1))
    scene = make_window_scene(button, "W"; width = 400, height = 300)
    composed = make_window_scene_projection(
        make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0)))
    document, projection = make_tracking_screen(scene, composed; gesture_tracking = tracking,
                                                mouse_target_tracking = tracking)
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend,
                    devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend, count)
end

_ts_press!(editor, backend, event) =
    (push_event!(backend, WindowInput(:W, event)); run_frame!(editor))

function test_tracking_screen()
@testset "the tracking screen recognizes a click through the editor's loop" begin
    @testset "with the tracker, a press and a release in place click the button once" begin
        editor, backend, count = _ts_editor(true)
        # The gesture tracker is outside the mouse target tracker.
        @test editor.document isa GestureTrackingState
        @test editor.document.content isa MouseTargetTrackingState
        @test get_wrapped_document(editor.document) isa ScreenDocument
        _ts_press!(editor, backend, MouseDown(:left, 10, 10, ModifierKeys(); time = 1.0))
        @test count[] == 0
        # The click waits for the operation of the release, and the same frame
        # reads it.
        _ts_press!(editor, backend, MouseUp(:left, 10, 10, ModifierKeys(); time = 1.1))
        @test count[] == 1
        @test isempty(editor.timers)
    end

    @testset "with no tracker, the editor recognizes no click" begin
        editor, backend, count = _ts_editor(false)
        @test editor.document isa ScreenDocument
        _ts_press!(editor, backend, MouseDown(:left, 10, 10, ModifierKeys(); time = 1.0))
        _ts_press!(editor, backend, MouseUp(:left, 10, 10, ModifierKeys(); time = 1.1))
        @test count[] == 0
    end
end
end # test_tracking_screen
