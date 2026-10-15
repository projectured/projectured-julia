# A scroll pane draws a bar over its content on each axis whose content is
# larger than its view, at the inner edge of its border. The bar is a part of the
# pane: the pointer on it lights it and does not reach the content, a click on it
# scrolls the pane, and the drag of its thumb comes back to the pane.

# A content taller than a view of 200 pixels: forty lines, and `width` pixels
# at least.
_make_bar_test_content(; width = 0) =
    WidgetTextarea(join(("line $i" for i in 1:40), "\n"); width, rows = 40)

# The bar of a pane printed through `iomap` on the axis of `field`.
_find_test_pane_bar(iomap, field) = only(bar for bar in iomap.bars if bar.field == field)

# The place of a bar in its pane: `(x, y, w, h)`.
_get_test_bar_place(bar) = (Int(bar.place.x), Int(bar.place.y), Int(bar.place.w), Int(bar.place.h))

# The writes of an answer, each without its mark of view state.
_bar_test_writes(op) = op === nothing ? Any[] :
    [o isa ReplaceViewStateOperation ? get_wrapped_operation(o) : o
     for o in (op isa CompoundOperation ? op.operations : Any[op])]

# The value that an answer writes into `field` of `document`, or `nothing`.
function _bar_test_written(op, document, field)
    for o in _bar_test_writes(op)
        (o isa ReplaceReferencedValueOperation && o.document === document &&
         o.reference.head == FieldReferenceStep(field)) && return o.value
    end
    nothing
end

# The coordinates of a point, or `nothing`.
_bar_test_xy(point) = point === nothing ? nothing : (Int(point.x[]), Int(point.y[]))

# Evaluate the writes of an answer: the start of the drag and the shape of the
# pointer need an editor, so they are left out.
_bar_test_apply!(op) = foreach(o -> o isa ReplaceReferencedValueOperation && evaluate_operation(nothing, o),
                               _bar_test_writes(op))

"""
    test_scroll_pane_bar()

A `WidgetScrollPane` draws a bar on each axis whose content is larger than its
view, over the content, and none on an axis that fits; `nothing` draws no bar,
and a `WidgetScrollBar` of a maker is drawn as it is and keeps its writes. A
click on the track of a bar scrolls the pane one view, Shift and a click jump,
and a drag of the thumb scrolls the pane wherever the pointer goes and goes back
on Escape. A pane that follows its end stops following when its bar leaves the
end, and follows again at the end. The pointer on a bar names the bar as the part
under it and lights it, and a click there does not reach the content.
"""
function test_scroll_pane_bar()
    projection = _scroll_pane_projection()
    plain = ModifierKeys()
    shift = ModifierKeys(shift = true)

    @testset "a pane shows a bar on each axis whose content is larger than its view" begin
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200))
        iomap = print_document(projection, pane)
        thickness = iomap.projection.scroll_bar_thickness
        @test thickness > 0
        vertical = _find_test_pane_bar(iomap, "vertical_scroll_bar")
        horizontal = _find_test_pane_bar(iomap, "horizontal_scroll_bar")
        # The text is taller than the view and as wide as it.
        @test _get_test_bar_place(vertical) == (200 - thickness, 0, thickness, 200)
        @test _get_test_bar_place(horizontal)[3:4] == (0, 0)
        # The bar lies over the content, after the viewport.
        elements = collect(iomap.output.elements)
        @test findfirst(e -> e === vertical.place, elements) >
              findfirst(e -> e isa GraphicsViewport, elements)
        content_h = Int(iomap.content_iomap.output.h)
        @test vertical.document.value == 0.0
        @test vertical.document.thumb_size ≈ 200 / content_h
        # The value follows the offset of the pane.
        getfield(pane, :scroll_position)[] = Point2D(0, (content_h - 200) ÷ 2)
        @test abs(vertical.document.value - 0.5) < 0.01
        # A content wider than the view shows both bars, and each stops before
        # the corner.
        wide = print_document(projection,
            WidgetScrollPane(_make_bar_test_content(; width = 600); size = Point2D(200, 200)))
        @test _get_test_bar_place(_find_test_pane_bar(wide, "vertical_scroll_bar")) ==
              (200 - thickness, 0, thickness, 200 - thickness)
        @test _get_test_bar_place(_find_test_pane_bar(wide, "horizontal_scroll_bar")) ==
              (0, 200 - thickness, 200 - thickness, thickness)
        # A content that fits shows no bar.
        short = print_document(projection,
            WidgetScrollPane(WidgetTextarea("one"; rows = 2); size = Point2D(200, 200)))
        @test all(bar -> _get_test_bar_place(bar)[3:4] == (0, 0), short.bars)
    end

    @testset "nothing draws no bar, and the bar of a maker keeps its writes" begin
        none = print_document(projection,
            WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200),
                             vertical_scroll_bar = nothing, horizontal_scroll_bar = nothing))
        @test isempty(none.bars)
        mine = WidgetScrollBar(:vertical; value = 0.25, thumb_size = 0.5)
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200),
                                vertical_scroll_bar = mine)
        iomap = print_document(projection, pane)
        bar = _find_test_pane_bar(iomap, "vertical_scroll_bar")
        @test bar.document === mine
        x = _get_test_bar_place(bar)[1] + 2
        # One page is the whole room: 0.5 / (1 - 0.5).
        click = read_intent(projection, iomap, MouseClick(:left, x, 190, 1, plain; time = 0.0))
        @test _bar_test_written(click, mine, "value") == 1.0
        @test _bar_test_written(click, pane, "scroll_position") === nothing
        # A bar that its thumb fills shows nothing.
        getfield(mine, :thumb_size)[] = 1.0
        @test _get_test_bar_place(bar)[3:4] == (0, 0)
    end

    @testset "a click on the track scrolls one view, and Shift and a click jump" begin
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200))
        iomap = print_document(projection, pane)
        room = Int(iomap.content_iomap.output.h) - 200
        x = 200 - 2
        click(y, modifiers) = read_intent(projection, iomap, MouseClick(:left, x, y, 1, modifiers; time = 0.0))
        page = click(190, plain)
        @test _bar_test_xy(_bar_test_written(page, pane, "scroll_position")) == (0, 200)
        # The click is the bar's: the text under it gets no caret.
        @test all(o -> o isa ReplaceReferencedValueOperation && o.document === pane, _bar_test_writes(page))
        _bar_test_apply!(page)
        # Shift and a click at the end jump to the end.
        jump = click(199, shift)
        @test _bar_test_xy(_bar_test_written(jump, pane, "scroll_position")) == (0, room)
        # A press on the track does nothing until the click.
        @test read_intent(projection, iomap, MouseDown(:left, x, 190, plain; time = 0.0)) === nothing
    end

    @testset "a drag of the thumb scrolls the pane, and Escape puts it back" begin
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200))
        iomap = print_document(projection, pane)
        room = Int(iomap.content_iomap.output.h) - 200
        bar = _find_test_pane_bar(iomap, "vertical_scroll_bar").document
        thumb = round(Int, bar.thumb_size * 200)
        x = 200 - 2
        press = read_intent(projection, iomap, MouseDown(:left, x, 5, plain; time = 0.0))
        start = only(o for o in _bar_test_writes(press) if o isa StartDragOperation)
        # The drag comes back to the pane, which gives it on to its bar.
        @test start.path isa EmptyReference
        _bar_test_apply!(press)
        @test bar.thumb_drag == (along = 5, value = 0.0, travel = 200 - thumb)
        moved = read_intent(projection, iomap, DragMove(x, 5 + 40, plain; time = 0.0))
        expected = round(Int, 40 / (200 - thumb) * room)
        @test _bar_test_xy(_bar_test_written(moved, pane, "scroll_position")) == (0, expected)
        _bar_test_apply!(moved)
        # A move far off the pane takes the view to the end.
        far = read_intent(projection, iomap, DragMove(900, 900, plain; time = 0.0))
        @test _bar_test_xy(_bar_test_written(far, pane, "scroll_position")) == (0, room)
        # Escape puts the view back where the drag started.
        cancel = read_intent(projection, iomap, DragCancel(; time = 0.0))
        @test _bar_test_xy(_bar_test_written(cancel, pane, "scroll_position")) == (0, 0)
        _bar_test_apply!(cancel)
        @test bar.thumb_drag === nothing
        @test _bar_test_xy(getfield(pane, :scroll_position)[]) == (0, 0)
    end

    @testset "a pane that follows its end follows again at the end" begin
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200), follow_end = true)
        iomap = print_document(projection, pane)
        room = Int(iomap.content_iomap.output.h) - 200
        bar = _find_test_pane_bar(iomap, "vertical_scroll_bar").document
        @test bar.value == 1.0
        x = 200 - 2
        up = read_intent(projection, iomap, MouseClick(:left, x, 0, 1, shift; time = 0.0))
        @test _bar_test_xy(_bar_test_written(up, pane, "scroll_position")) == (0, 0)
        @test _bar_test_written(up, pane, "follow_end") == false
        _bar_test_apply!(up)
        @test bar.value == 0.0
        down = read_intent(projection, iomap, MouseClick(:left, x, 199, 1, shift; time = 0.0))
        @test _bar_test_xy(_bar_test_written(down, pane, "scroll_position")) == (0, room)
        @test _bar_test_written(down, pane, "follow_end") == true
    end

    @testset "a touchpad scrolls the pane by the fraction of a notch" begin
        pane = WidgetScrollPane(_make_bar_test_content(); size = Point2D(200, 200))
        iomap = print_document(projection, pane)
        turn(precise) = _bar_test_xy(_bar_test_written(
            read_intent(projection, iomap, MouseScroll(0, 0, 100, 100; time = 0.0, precise_dy = precise)),
            pane, "scroll_position"))
        whole = turn(-1.0)[2]
        @test whole > 0
        @test turn(-0.5) == (0, round(Int, whole / 2))
    end

    @testset "a fast run of notches scrolls more at each notch, up to the view less one line" begin
        pane = WidgetScrollPane(WidgetTextarea(join(("line $i" for i in 1:400), "\n"); rows = 400);
                                size = Point2D(200, 200))
        iomap = print_document(projection, pane)
        y() = Int(pane.scroll_position.y[])
        function turn!(notches, time; precise_dy = notches)
            before = y()
            _bar_test_apply!(read_intent(projection, iomap,
                                         MouseScroll(0, notches, 100, 100; time, precise_dy)))
            y() - before
        end
        step = turn!(-1, 1.0)
        @test step > 0
        # Sooner than 80 ms a notch scrolls more, and up to 150 ms as much.
        @test turn!(-1, 1.05) == round(Int, 1.25 * step)
        @test turn!(-1, 1.15) == round(Int, 1.25 * step)
        # A pause, and the other direction, start a new run.
        @test turn!(-1, 2.0) == step
        @test turn!(1, 2.05) == -step
        # A merged turn of two notches grows at its second notch.
        @test turn!(-2, 3.0) == round(Int, 2.25 * step)
        # A touchpad moves its fraction and ends the run.
        @test turn!(0, 3.05; precise_dy = -0.5) == round(Int, step / 2)
        @test turn!(-1, 3.1) == step
        # A long fast run stops growing at the view less one line: a notch is
        # three lines.
        for k in 1:20
            turn!(-1, 4.0 + 0.05 * k)
        end
        @test turn!(-1, 5.1) == 200 - step ÷ 3
    end

    @testset "the pointer on a bar names the bar and lights it" begin
        area = _make_bar_test_content()
        pane = WidgetScrollPane(area; size = Point2D(200, 200))
        # A clock that the test moves, so the thumb can fade out.
        clock = Clock()
        driver = MttDriver(projection, pane,
                           print_document(projection, nothing, pane,
                                          ProjecturedKernel.ProjectionModule.with_clock(PrinterContext(), clock)))
        found = _find_test_pane_bar(driver.iomap, "vertical_scroll_bar")
        bar = found.document
        thumb = found.iomap.output.elements[end - 1]
        rest = thumb.color
        @test rest == color_transparent
        @test strip_reference_types(compute_part_at_point(driver.iomap, 198, 100)) ==
              ConcreteReference(FieldReferenceStep("vertical_scroll_bar"), EmptyReference())
        _mtt_move!(driver, 198, 100, 1.0)
        @test get_mouse_target(pane) ==
              ConcreteReference(FieldReferenceStep("vertical_scroll_bar"), EmptyReference())
        @test get_mouse_target(bar) == EmptyReference()
        @test get_mouse_target(area) === nothing
        @test thumb.color != rest
        # Off the bar, the text has the pointer and the bar is at rest.
        _mtt_move!(driver, 20, 100, 1.1)
        @test get_mouse_target(bar) === nothing
        @test get_mouse_target(area) !== nothing
        # The paint of the next frame sees the leave, and the thumb fades out.
        @test thumb.color == found.iomap.projection.thumb_scrolled_color
        ProjecturedKernel.ClockModule.set_clock_time!(clock, 1.0)
        @test thumb.color == rest
    end
end
