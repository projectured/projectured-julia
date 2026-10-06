# A scroll bar beside or over a content that it does not hold: it is as long as
# its parent offers, it moves its thumb with its value and prints nothing again,
# a click on its track moves one page, Shift and a press jump, and a press on its
# thumb starts a drag that keeps the point where the pointer took the thumb.

"""
    test_widget_scroll_bar()

A `WidgetScrollBar` with no authored size takes the extent that its parent
offers along it and the thickness of its theme across it. Its thumb reads the
value in cells, so a new value moves the thumb on the same canvas. Its track is
transparent until the pointer is on the bar, and the pointer is an arrow over
it. A click on the track moves the value one page toward the pointer, Shift and a
click or a press put the middle of the thumb under the pointer, and a press on
the thumb starts a drag: each `DragMove` adds its distance to the value of the
press, and `DragCancel` puts that value back.
"""
function test_widget_scroll_bar()
@testset "a scroll bar takes its length, and the pointer moves its thumb" begin
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    offer = with_exact_size(PrinterContext(); height = Cell(Int32(300)))
    bar = WidgetScrollBar(:vertical; value = 0.5, thumb_size = 0.2)
    iomap = print_document(projection, nothing, bar, offer)
    canvas = iomap.output
    @test (Int(canvas.w), Int(canvas.h)) == (10, 300)
    track, thumb, shape = canvas.elements[end - 2], canvas.elements[end - 1], canvas.elements[end]
    @test (Int(track.y), Int(track.h)) == (0, 300)
    # The thumb is a fifth of the track, halfway along the rest.
    @test (Int(thumb.y), Int(thumb.h)) == (120, 60)
    getfield(bar, :value)[] = 0.0
    @test Int(thumb.y) == 0
    @test canvas.elements[end - 1] === thumb
    getfield(bar, :value)[] = 0.5

    @testset "the track shows while the pointer is on the bar" begin
        p = iomap.projection
        @test track.color == color_transparent
        @test thumb.color == p.thumb_color
        getfield(bar, :mouse_target)[] = EmptyReference()
        @test track.color == p.track_hovered_color
        @test thumb.color == p.thumb_hovered_color
        getfield(bar, :mouse_target)[] = nothing
        @test track.color == color_transparent
        @test shape isa GraphicsPointerShape && shape.shape === :arrow
        @test (Int(shape.w), Int(shape.h)) == (10, 300)
    end

    read(event) = read_intent(projection, iomap, event)
    plain = ModifierKeys()
    shift = ModifierKeys(shift = true)
    # The writes of an answer, each without its mark of view state.
    writes(op) = [o for o in (op isa CompoundOperation ? op.operations : Any[op])]
    bare(o) = o isa ReplaceViewStateOperation ? get_wrapped_operation(o) : o
    is_write(o, field) = (o = bare(o); o isa ReplaceReferencedValueOperation &&
                                       o.reference.head == FieldReferenceStep(field))
    # The value that an answer writes, or `nothing`.
    function written_value(op)
        op === nothing && return nothing
        for o in writes(op)
            is_write(o, "value") && return bare(o).value
        end
        nothing
    end
    # Evaluate the writes of the bar in an answer: the start of the drag and the
    # shape of the pointer need an editor, so they are left out.
    apply!(op) = foreach(o -> (is_write(o, "value") || is_write(o, "thumb_drag")) &&
                              evaluate_operation(nothing, o), writes(op))

    @testset "a click on the track moves one page toward the pointer" begin
        # One page is 0.2 / 0.8 of the value: the thumb is at 120 to 180.
        @test written_value(read(MouseClick(:left, 5, 250, 1, plain; time = 0.0))) ≈ 0.75
        @test written_value(read(MouseClick(:left, 5, 50, 1, plain; time = 0.0))) ≈ 0.25
        # A click on the thumb, and a press on the track, move nothing.
        @test read(MouseClick(:left, 5, 150, 1, plain; time = 0.0)) === nothing
        @test read(MouseDown(:left, 5, 250, plain; time = 0.0)) === nothing
        # The page stops at the end.
        getfield(bar, :value)[] = 0.9
        @test written_value(read(MouseClick(:left, 5, 10, 1, plain; time = 0.0))) ≈ 0.65
        getfield(bar, :value)[] = 0.95
        @test written_value(read(MouseClick(:left, 5, 2, 1, plain; time = 0.0))) ≈ 0.7
        getfield(bar, :value)[] = 0.9
        @test written_value(read(MouseClick(:left, 5, 299, 1, plain; time = 0.0))) == 1.0
        # A thumb that fills the track moves nothing.
        getfield(bar, :value)[] = 0.0
        getfield(bar, :thumb_size)[] = 1.0
        @test read(MouseClick(:left, 5, 299, 1, plain; time = 0.0)) === nothing
        getfield(bar, :thumb_size)[] = 0.2
        getfield(bar, :value)[] = 0.5
    end

    @testset "Shift and a click or a press jump" begin
        # The middle of the thumb goes under the pointer: (90 - 30) / 240.
        @test written_value(read(MouseClick(:left, 5, 270, 1, shift; time = 0.0))) ≈ 1.0
        @test written_value(read(MouseClick(:left, 5, 90, 1, shift; time = 0.0))) ≈ 0.25
        # Shift and a press jump and take the thumb there.
        press = read(MouseDown(:left, 5, 90, shift; time = 0.0))
        @test written_value(press) ≈ 0.25
        @test any(o -> o isa StartDragOperation, writes(press))
        apply!(press)
        @test bar.thumb_drag == (along = 90, value = 0.25, travel = 240)
        apply!(read(DragEnd(5, 90, plain; time = 0.0)))
        @test bar.thumb_drag === nothing
        getfield(bar, :value)[] = 0.5
    end

    @testset "a press on the thumb starts a drag that keeps the grab point" begin
        press = read(MouseDown(:left, 5, 170, plain; time = 0.0))
        @test press isa CompoundOperation
        @test written_value(press) === nothing
        @test any(o -> o isa StartDragOperation, writes(press))
        apply!(press)
        @test bar.thumb_drag == (along = 170, value = 0.5, travel = 240)
        # The thumb moves with the pointer: 60 pixels of 240 is a quarter.
        moved = read(DragMove(5, 230, plain; time = 0.0))
        @test written_value(moved) ≈ 0.75
        apply!(moved)
        # A move off the bar still moves the thumb, up to each end.
        @test written_value(read(DragMove(400, 900, plain; time = 0.0))) == 1.0
        @test written_value(read(DragMove(5, -500, plain; time = 0.0))) == 0.0
        # Escape puts back the value of the press.
        cancel = read(DragCancel(; time = 0.0))
        @test written_value(cancel) == 0.5
        apply!(cancel)
        @test bar.thumb_drag === nothing
        @test bar.value == 0.5
        # With no drag on, a drag gesture and a move with the button held do nothing.
        @test read(DragMove(5, 230, plain; time = 0.0)) === nothing
        @test read(DragEnd(5, 230, plain; time = 0.0)) === nothing
        @test read(MouseMove(5, 10, MouseButtons(:left), plain; time = 0.0)) === nothing
        # A press of another button, and a press off the bar, do nothing.
        @test read(MouseDown(:right, 5, 150, plain; time = 0.0)) === nothing
        @test read(MouseDown(:left, 50, 150, plain; time = 0.0)) === nothing
    end

    # An authored size wins over the offer.
    sized = print_document(projection, nothing,
                           WidgetScrollBar(:vertical; size = Point2D(20, 100)), offer)
    @test (Int(sized.output.w), Int(sized.output.h)) == (20, 100)
end
end
