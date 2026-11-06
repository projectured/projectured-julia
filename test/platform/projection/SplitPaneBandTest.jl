# The band of a splitter: a divider is a 1 px line at rest. A band of the width of
# the theme shows on it, in the ring color, after the pointer rested on its grab
# area for 0.3 s, and at once while it is dragged. It fades in and out over 0.1 s,
# and a split that shows no band reads no clock.

# Every operation of type `T` that `operation` holds, inside compounds and wrappers.
function _find_band_members(operation, T)
    operation isa T && return Any[operation]
    operation isa CompoundOperation &&
        return reduce(vcat, (_find_band_members(member, T) for member in operation.operations); init = Any[])
    operation isa WrappingOperation && return _find_band_members(get_wrapped_operation(operation), T)
    Any[]
end

# The bands of a split that `iomap` draws: its rects as wide as `width`, one for
# each divider, in the order of the dividers.
_find_split_bands(iomap, width) =
    [element for element in iomap.output.elements
     if element isa GraphicsRect && Int(element.w) == width && Int(element.h) > width]

"""
    test_split_pane_band()

A pointer move on the grab area of a divider writes `splitter_under_pointer`, a
move inside it writes nothing, and a leave writes 0; the move still reaches the
slot under the pointer. The band of the divider has no color before the delay,
rises over the fade time, shows in the ring color, falls after the pointer leaves,
and is at full at once while the divider is dragged. The cells of a band that
does not show read no clock.
"""
function test_split_pane_band()
@testset "the band of a splitter" begin
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(; measure = FixedMeasure(10, 18, 6, 0)).dispatch))
    clock = Clock()
    set_time!(seconds) = ProjecturedKernel.ClockModule.set_clock_time!(clock, seconds)
    offer = ProjecturedKernel.ProjectionModule.with_clock(PrinterContext(), clock)
    reads_clock() = has_dependent_cells(getfield(clock, :time))
    apply!(answer) = answer isa Operation && evaluate_operation(nothing, answer)
    set_time!(10.0)

    function make_split(orientation, sizes)
        doc = WidgetSplitPane(orientation, Any[WidgetLabel("slot $i") for i in 1:length(sizes)]; sizes)
        iomap = print_document(projection, nothing, doc, offer)
        doc, iomap, iomap.projection
    end
    move(iomap, x, y) = read_intent(projection, iomap, MouseMove(x, y; time = 0.0))

    @testset "the pointer on a grab area writes the divider, once" begin
        doc = WidgetSplitPane(:horizontal, Any[WidgetList(["row 1", "row 2"]; selected = 0, width = 250),
                                               WidgetLabel("slot 2")]; sizes = [300, 300])
        iomap = print_document(projection, nothing, doc, offer)
        # The divider is the line at x = 300 and its grab area is x = 297 to 304.
        first_move = move(iomap, 298, 5)
        writes = _find_band_members(first_move, SetSplitterUnderPointerOperation)
        @test length(writes) == 1 && writes[1].splitter_index == 1
        @test !is_undo_step(nothing, first_move)
        apply!(first_move)
        @test doc.splitter_under_pointer == 1
        @test isempty(_find_band_members(move(iomap, 301, 5), SetSplitterUnderPointerOperation))
        @test !isempty(_find_band_members(move(iomap, 296, 5), SetSplitterUnderPointerOperation))
        apply!(move(iomap, 296, 5))
        @test doc.splitter_under_pointer == 0
        apply!(move(iomap, 300, 5))
        @test doc.splitter_under_pointer == 1
        # A leave writes 0.
        leave = read_intent(projection, iomap, MouseMove(-1, -1; time = 0.0))
        @test only(_find_band_members(leave, SetSplitterUnderPointerOperation)).splitter_index == 0
        apply!(leave)
        @test doc.splitter_under_pointer == 0
    end

    @testset "the slot under the pointer keeps its hover, and a leave clears the divider" begin
        list = WidgetList(["row 1", "row 2"]; selected = 0, width = 300)
        doc = WidgetSplitPane(:horizontal, Any[list, WidgetLabel("slot 2")]; sizes = [300, 300])
        driver = MttDriver(projection, doc)
        # The point is 2 px inside the list, on the grab area of the divider.
        _mtt_move!(driver, 298, 10, 1.0)
        @test doc.splitter_under_pointer == 1
        @test WidgetModule._widget_element_selected(get_mouse_target(list), "items") > 0
        _mtt_move!(driver, 100, 10, 2.0)
        @test doc.splitter_under_pointer == 0
        _mtt_move!(driver, 300, 10, 3.0)
        @test doc.splitter_under_pointer == 1
        _mtt_leave!(driver, 4.0)
        @test doc.splitter_under_pointer == 0
    end

    @testset "the band shows after the delay, and fades in" begin
        doc, iomap, p = make_split(:horizontal, [300, 300])
        band = only(_find_split_bands(iomap, p.splitter_band_width))
        ring = p.splitter_band_color
        color() = band.color
        set_time!(10.0)
        @test color() == color_transparent
        # The band is centred on the line: 4 px across a line of 1 px at x = 300.
        @test (Int(band.x), Int(band.w), Int(band.y), Int(band.h)) == (299, 4, 0, Int(iomap.output.h))
        apply!(move(iomap, 300, 5))
        @test color() == color_transparent
        @test reads_clock()
        set_time!(10.0 + p.band_delay - 0.01)
        @test color() == color_transparent
        set_time!(10.0 + p.band_delay + p.fade_duration / 2)
        @test (color().red, color().green, color().blue) == (ring.red, ring.green, ring.blue)
        @test color().alpha ≈ ring.alpha / 2
        set_time!(10.0 + p.band_delay + p.fade_duration + 0.01)
        @test color() == ring
        @test !reads_clock()
    end

    @testset "the band falls after the pointer leaves, and then reads no clock" begin
        doc, iomap, p = make_split(:horizontal, [300, 300])
        band = only(_find_split_bands(iomap, p.splitter_band_width))
        ring = p.splitter_band_color
        set_time!(20.0)
        @test band.color == color_transparent
        apply!(move(iomap, 300, 5))
        @test band.color == color_transparent
        set_time!(20.5)
        @test band.color == ring
        set_time!(21.0)
        apply!(move(iomap, 100, 5))
        @test doc.splitter_under_pointer == 0
        @test band.color == ring
        set_time!(21.0 + p.fade_duration / 2)
        @test band.color.alpha ≈ ring.alpha / 2
        @test reads_clock()
        set_time!(21.0 + p.fade_duration + 0.01)
        @test band.color == color_transparent
        @test !reads_clock()
        # With nothing to show, a write of the clock computes no cell of the band.
        @test is_cell_valid(getfield(band, :color))
        set_time!(50.0)
        @test is_cell_valid(getfield(band, :color))
    end

    @testset "a dragged divider shows its band at once, and the band falls after the release" begin
        doc, iomap, p = make_split(:horizontal, [300, 300])
        band = only(_find_split_bands(iomap, p.splitter_band_width))
        ring = p.splitter_band_color
        set_time!(30.0)
        @test band.color == color_transparent
        apply!(read_intent(projection, iomap, MouseDown(:left, 300, 5, ModifierKeys(); time = 0.0)))
        @test doc.active_splitter == 1
        @test band.color == ring
        @test !reads_clock()
        apply!(read_intent(projection, iomap, DragMove(320, 5; time = 0.0)))
        @test Int(band.x) == 319
        set_time!(31.0)
        @test band.color == ring
        apply!(read_intent(projection, iomap, DragEnd(320, 5; time = 0.0)))
        @test doc.active_splitter == 0
        @test band.color == ring
        set_time!(31.0 + p.fade_duration / 2)
        @test band.color.alpha ≈ ring.alpha / 2
        set_time!(31.0 + p.fade_duration + 0.01)
        @test band.color == color_transparent
        @test !reads_clock()
    end

    @testset "two dividers: only the one under the pointer shows a band" begin
        doc, iomap, p = make_split(:horizontal, [200, 200, 200])
        bands = _find_split_bands(iomap, p.splitter_band_width)
        @test length(bands) == 2
        set_time!(40.0)
        @test all(band -> band.color == color_transparent, bands)
        # The second divider is the line at x = 401.
        apply!(move(iomap, 401, 5))
        @test doc.splitter_under_pointer == 2
        @test all(band -> band.color == color_transparent, bands)
        set_time!(40.0 + p.band_delay + p.fade_duration + 0.01)
        @test bands[1].color == color_transparent
        @test bands[2].color == p.splitter_band_color
        @test Int(bands[2].x) == 400
        apply!(move(iomap, 200, 5))
        @test doc.splitter_under_pointer == 1
    end

    @testset "a vertical split shows its band across its divider" begin
        doc, iomap, p = make_split(:vertical, [100, 100])
        band = only(element for element in iomap.output.elements
                    if element isa GraphicsRect && Int(element.h) == p.splitter_band_width &&
                       Int(element.w) > p.splitter_band_width)
        set_time!(60.0)
        @test band.color == color_transparent
        apply!(move(iomap, 5, 100))
        @test doc.splitter_under_pointer == 1
        @test band.color == color_transparent
        set_time!(60.0 + p.band_delay + p.fade_duration + 0.01)
        @test band.color == p.splitter_band_color
        @test (Int(band.y), Int(band.h), Int(band.x), Int(band.w)) == (99, 4, 0, Int(iomap.output.w))
    end

    @testset "with a clock that nothing writes the band shows during a drag and not on hover" begin
        doc = WidgetSplitPane(:horizontal, Any[WidgetLabel("a"), WidgetLabel("b")]; sizes = [300, 300])
        iomap = print_document(projection, nothing, doc, PrinterContext())
        p = iomap.projection
        band = only(_find_split_bands(iomap, p.splitter_band_width))
        @test band.color == color_transparent
        apply!(move(iomap, 300, 5))
        @test doc.splitter_under_pointer == 1
        @test band.color == color_transparent
        apply!(read_intent(projection, iomap, MouseDown(:left, 300, 5, ModifierKeys(); time = 0.0)))
        @test band.color == p.splitter_band_color
    end
end
end
