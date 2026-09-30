# A scroll bar beside a content that it does not hold: it is as long as its
# parent offers, it moves its thumb with its value and prints nothing again, and
# a press or a move with the left button held writes the value under the pointer.

"""
    test_widget_scroll_bar()

A `WidgetScrollBar` with no authored size takes the extent that its parent
offers along it and the thickness of its theme across it. Its thumb reads the
value in cells, so a new value moves the thumb on the same canvas. A button
down, a press, and a move with the left button held put the middle of the
thumb under the pointer; a move with no button writes nothing.
"""
function test_widget_scroll_bar()
@testset "a scroll bar takes its length, and the pointer moves its thumb" begin
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    offer = with_exact_size(PrinterContext(); height = Cell(Int32(300)))
    bar = WidgetScrollBar(:vertical; value = 0.5, thumb_size = 0.2)
    iomap = print_document(projection, nothing, bar, offer)
    canvas = iomap.output
    @test (Int(canvas.w), Int(canvas.h)) == (12, 300)
    track, thumb = canvas.elements[end - 1], canvas.elements[end]
    @test (Int(track.y), Int(track.h)) == (0, 300)
    # The thumb is a fifth of the track, halfway along the rest.
    @test (Int(thumb.y), Int(thumb.h)) == (120, 60)
    getfield(bar, :value)[] = 0.0
    @test Int(thumb.y) == 0
    @test canvas.elements[end] === thumb
    # A button down near the end puts the thumb at the end; a move with the
    # button held takes it back; a move with no button does nothing.
    read(event) = read_intent(projection, iomap, event)
    mods = ModifierKeys()
    down = read(MouseDown(:left, 6, 290, mods; time = 0.0))
    @test down isa ReplaceReferencedValueOperation && down.value == 1.0
    getfield(bar, :value)[] = down.value
    moved = read(MouseMove(6, 150, MouseButtons(:left), mods; time = 0.0))
    @test moved.value ≈ 0.5
    @test read(MouseMove(6, 10, MouseButtons(), mods; time = 0.0)) === nothing
    # A press where the thumb already is writes nothing.
    getfield(bar, :value)[] = moved.value
    @test read(MouseClick(:left, 6, 150, mods; time = 0.0)) === nothing
    # An authored size wins over the offer.
    sized = print_document(projection, nothing,
                           WidgetScrollBar(:vertical; size = Point2D(20, 100)), offer)
    @test (Int(sized.output.w), Int(sized.output.h)) == (20, 100)
end
end
