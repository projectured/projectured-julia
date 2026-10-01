mutable struct _WidgetSliderMockEditor
    document::Any
end

# A lone slider at 0.3 on a track of 240 px, printed by the widget renderer, and
# the height at which a pointer is on its track.
function _make_slider_iomap()
    slider = WidgetSlider(0.3; width = 240)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    iomap = print_document(projection, nothing, slider, PrinterContext())
    (slider, projection, iomap, Int(iomap.output.h[]) ÷ 2)
end

# Read `event` and evaluate what the slider answers; the answer is returned.
function _read_slider_event!(slider, projection, iomap, event)
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(_WidgetSliderMockEditor(slider), operation)
    operation
end

"""
    test_widget_slider_drag()

The slider reads the events a real mouse sends: a `MouseDown` takes the knob, a
move writes while it is held, and a `MouseUp` lets go. The `MouseClick` that the
gesture recognizer makes after a real click takes nothing.
"""
function test_widget_slider_drag()
@testset "a real drag moves the knob, and the release lets it go" begin
    slider, projection, iomap, y = _make_slider_iomap()
    _read_slider_event!(slider, projection, iomap, MouseDown(:left, 40, y, ModifierKeys(); time = 0.0))
    @test slider.dragging === true
    start = slider.value
    @test 0.0 < start < 0.3
    # 120 px along a track of 240 px is half of it.
    _read_slider_event!(slider, projection, iomap, DragMove(160, y; time = 0.0))
    @test slider.value ≈ start + 0.5
    _read_slider_event!(slider, projection, iomap, DragEnd(160, y; time = 0.0))
    @test slider.dragging === false
    # With the knob let go, a move is only a move.
    @test read_intent(projection, iomap, MouseMove(200, y, MouseButtons(), ModifierKeys(); time = 0.0)) === nothing
    @test slider.value ≈ start + 0.5
end

@testset "a real click sets the value and leaves the knob free" begin
    slider, projection, iomap, y = _make_slider_iomap()
    _read_slider_event!(slider, projection, iomap, MouseDown(:left, 100, y, ModifierKeys(); time = 0.0))
    _read_slider_event!(slider, projection, iomap, MouseUp(:left, 100, y, ModifierKeys(); time = 0.0))
    clicked = slider.value
    @test clicked != 0.3
    # The press the recognizer makes after the up finds the value in place: it
    # writes only the view state, so the history gets no second step.
    press = _read_slider_event!(slider, projection, iomap, MouseClick(:left, 100, y, ModifierKeys(); time = 0.0))
    @test press isa ReplaceViewStateOperation
    @test slider.dragging === false
    @test read_intent(projection, iomap, MouseMove(200, y, MouseButtons(), ModifierKeys(); time = 0.0)) === nothing
    @test slider.value == clicked
end

@testset "a press from a script sets the value and takes nothing" begin
    slider, projection, iomap, y = _make_slider_iomap()
    press = _read_slider_event!(slider, projection, iomap, MouseClick(:left, 100, y, ModifierKeys(); time = 0.0))
    @test press isa ReplaceReferencedValueOperation
    @test slider.value != 0.3
    @test slider.dragging === false
end
end # test_widget_slider_drag
