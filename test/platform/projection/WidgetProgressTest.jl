# The elements of type `T` that a printed widget draws, from the top of its
# canvas down, and through the viewports of its panes.
function _collect_progress_elements(T, element, found = Any[])
    element isa T && push!(found, element)
    element isa GraphicsCanvas && foreach(child -> _collect_progress_elements(T, child, found), element.elements)
    element isa GraphicsViewport && _collect_progress_elements(T, element.content, found)
    found
end

_print_progress_widget(widget, context = PrinterContext()) = print_document(
    RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch)),
    nothing, widget, context)

# A printer context whose clock is `clock`, and a write of its time.
_make_progress_context(clock) = ProjecturedKernel.ProjectionModule.with_clock(PrinterContext(), clock)
_set_progress_time!(clock, seconds) = ProjecturedKernel.ClockModule.set_clock_time!(clock, seconds)

"""
    test_widget_progress()

The two progress widgets. A `WidgetProgressRing` is one line of text high and
shows a known value as an arc from the top, clockwise. While the value of a ring
or of a `WidgetProgressBar` is `nothing`, a quarter of the ring turns, or a
quarter of the track moves, with the clock of the printer, and only then does
the widget read the clock.
"""
function test_widget_progress()
@testset "the ring is one line of text high" begin
    line = compute_line_box(FixedMeasure(10, 18, 6, 0), "", StyleFont("Ubuntu Mono", 20)).height
    @test line == 24
    ring = _print_progress_widget(WidgetProgressRing(0.5)).output
    @test (ring.w, ring.h) == (24, 24)
    track = only(_collect_progress_elements(GraphicsCircle, ring))
    @test (track.cx, track.cy, track.radius) == (12, 12, 12)
    @test track.color.alpha == 0
    @test track.border_width == 2
end

@testset "a table row that holds a ring is as high as a row of text" begin
    with_ring = _print_progress_widget(WidgetTable(["job", "done"], [["a", WidgetProgressRing(0.5)]])).output
    with_text = _print_progress_widget(WidgetTable(["job", "done"], [["a", "half"]])).output
    @test with_ring.h == with_text.h
    arc = only(_collect_progress_elements(GraphicsArc, with_ring))
    @test arc.radius == 12
end

@testset "a known value is an arc from the top, clockwise" begin
    draw_arcs(value) = _collect_progress_elements(GraphicsArc, _print_progress_widget(WidgetProgressRing(value)).output)
    quarter = only(draw_arcs(0.25))
    @test (quarter.cx, quarter.cy, quarter.radius, quarter.width) == (12, 12, 12, 2)
    @test (quarter.start_angle, quarter.sweep_angle) == (0.0, 90.0)
    @test only(draw_arcs(0.0)).sweep_angle == 0.0
    @test only(draw_arcs(1.0)).sweep_angle == 360.0
    @test only(draw_arcs(1.7)).sweep_angle == 360.0
    # A function that answers `nothing` is a value that is not known.
    @test WidgetProgressRing(() -> nothing).value === nothing
    @test WidgetProgressRing().value === nothing
end

@testset "a ring with no value turns a quarter with the clock of its printer" begin
    clock = Clock()
    value = Cell(nothing)
    canvas = _print_progress_widget(WidgetProgressRing(value), _make_progress_context(clock)).output
    find_arc() = only(_collect_progress_elements(GraphicsArc, canvas))
    @test (find_arc().start_angle, find_arc().sweep_angle) == (0.0, 90.0)
    _set_progress_time!(clock, 0.25)
    @test find_arc().start_angle == 90.0
    _set_progress_time!(clock, 1.5)
    @test find_arc().start_angle == 180.0
    @test has_dependent_cells(getfield(clock, :time))
    # A known value stops the turn. The same arc shows it, and once the arc is
    # drawn again nothing reads the clock, so the editor can sleep.
    arc = find_arc()
    value[] = 0.5
    @test find_arc() === arc
    @test (arc.start_angle, arc.sweep_angle) == (0.0, 180.0)
    @test !has_dependent_cells(getfield(clock, :time))
    _set_progress_time!(clock, 1.75)
    @test arc.start_angle == 0.0
    @test !has_dependent_cells(getfield(clock, :time))
    # A value that is not known again turns again.
    value[] = nothing
    @test arc.start_angle == 270.0
    @test has_dependent_cells(getfield(clock, :time))
end

@testset "a ring with a known value never reads the clock" begin
    clock = Clock()
    canvas = _print_progress_widget(WidgetProgressRing(0.3), _make_progress_context(clock)).output
    @test only(_collect_progress_elements(GraphicsArc, canvas)).sweep_angle ≈ 108.0
    _set_progress_time!(clock, 0.5)
    @test !has_dependent_cells(getfield(clock, :time))
    # A ring that is not visible draws nothing and reads nothing.
    hidden = _print_progress_widget(WidgetProgressRing(; visible = false), _make_progress_context(clock)).output
    @test isempty(_collect_progress_elements(GraphicsArc, hidden))
    @test !has_dependent_cells(getfield(clock, :time))
end

@testset "a bar with no value moves a quarter of its track with the clock of its printer" begin
    clock = Clock()
    value = Cell(nothing)
    canvas = _print_progress_widget(WidgetProgressBar(value; width = 200), _make_progress_context(clock)).output
    # The track, the part of the quarter before the end of the track, and the
    # part that passed the end and shows at the start.
    track, head, tail = _collect_progress_elements(GraphicsRect, canvas)[end - 2:end]
    @test (track.x, track.w) == (0, 200)
    find_places() = (head.x, head.w, tail.x, tail.w)
    @test find_places() == (0, 50, 0, 0)
    _set_progress_time!(clock, 0.5)
    @test find_places() == (100, 50, 0, 0)
    _set_progress_time!(clock, 0.875)
    @test find_places() == (175, 25, 0, 25)
    @test has_dependent_cells(getfield(clock, :time))
    # A known value fills the track from the start, with the same two rectangles,
    # and the bar stops reading the clock.
    value[] = 0.3
    @test _collect_progress_elements(GraphicsRect, canvas)[end - 1] === head
    @test find_places() == (0, 60, 0, 0)
    @test !has_dependent_cells(getfield(clock, :time))
    @test WidgetProgressBar().value === nothing
end
end # test_widget_progress
