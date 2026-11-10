# The sequence chart pipeline: SequenceChart → SequenceChartPlot → GraphicsCanvas.
#
# These drive the real projections and assert on the canvas that comes out —
# what appears, where it lands, that a data change repaints, and that a
# selection round-trips through both stages.
#
# Two properties carry the design and are worth stating plainly:
#
# - **Hover must not re-run the layout.** The whole three-cell split exists for
#   that, and the only way to know it holds is to move the pointer and check the
#   geometry object is the same one as before.
# - **The window must survive a data change.** Appending to a trace someone is
#   reading must not throw away where they had scrolled to.

using Test

const SCT = SequenceChartModule

_sequencechart_projection(; width::Integer=900, height::Integer=520) =
    ChainingProjection(
        SequenceChartToSequenceChartPlot(),
        SequenceChartPlotToGraphicsCanvas(measure=FontFileMeasure(),
                                          width=width, height=height))

# A recursion that prints the buttons and the bars of a sequence chart, as
# `make_sequence_chart_projection` gives its renderer: a test prints the two stages
# with it, so a hover can show them.
_sc_widgets() = TypeDispatchingProjection(
    WidgetToolbar => WidgetToolbarToGraphicsCanvas(WidgetTheme(); measure = FontFileMeasure()),
    WidgetToolbarItem => WidgetToolbarItemToGraphicsCanvas(WidgetTheme(); measure = FontFileMeasure()),
    WidgetScrollBar => WidgetScrollBarToGraphicsCanvas(WidgetTheme()))

_sequencechart_iomap(chart; kw...) = (p = _sequencechart_projection(; kw...);
                                      print_document(p, _sc_widgets(), chart, PrinterContext()))

# The IO map of the canvas of a sequence chart, found in an IO map tree.
function _find_sequence_chart_canvas_iomap(root)
    force(value) = value isa AbstractCell ? force(value[]) : value
    seen = Set{UInt}()
    stack = Any[root]
    while !isempty(stack)
        value = force(pop!(stack))
        value isa SequenceChartPlotToGraphicsCanvasIoMap && return value
        if value isa IoMap
            objectid(value) in seen && continue
            push!(seen, objectid(value))
            for name in fieldnames(typeof(value))
                name in (:projection, :input, :output) || push!(stack, getfield(value, name))
            end
        elseif value isa Union{AbstractVector,Tuple}
            append!(stack, value)
        end
    end
    nothing
end

# An answer as the editor takes it: a compound is taken part by part, and a mouse
# target goes to the chart.
function _sc_apply_answer!(chart, op)
    op isa CompoundOperation ? foreach(o -> _sc_apply_answer!(chart, o), op.operations) :
    op isa ReplaceMouseTargetOperation ? replace_mouse_target!(chart, op.path) :
    evaluate_operation(nothing, op)
end

# The pointer shape that an answer sets.
function _sc_pointer_shape(op)
    unwrap(o) = o isa ReplaceViewStateOperation ? get_wrapped_operation(o) : o
    only(unwrap(o).shape for o in op.operations if unwrap(o) isa ChangeScreenPointerShapeOperation)
end

_sequencechart_canvas(chart; kw...) = _sequencechart_iomap(chart; kw...).output

# The renderer's own iomap and its laid-out frame, reached the way the tests for
# the chart slice reach theirs.
_stage2_iomap(iomap) = iomap.step_iomaps[2][]
_geometry_of(iomap) = _stage2_iomap(iomap).geometry
_plot_of(iomap) = _stage2_iomap(iomap).input

# Every element of a canvas, descending into viewports and nested canvases.
function _sc_flatten(doc)
    out = Any[]
    _sc_flatten!(out, doc)
    out
end
function _sc_flatten!(out, doc)
    if doc isa GraphicsCanvas
        for e in doc.elements
            push!(out, e)
            _sc_flatten!(out, e)
        end
    elseif doc isa GraphicsViewport
        _sc_flatten!(out, doc.content)
    end
    out
end

_sc_count(els, T) = count(e -> e isa T, els)
_sc_texts(els) = String[e.text for e in els if e isa GraphicsText]

# A three-lane request flow: a burst of same-time events, a long gap after it,
# and a message that returns to the lane it left.
function _sc_chart(; orientation::Symbol=:horizontal, mode::Symbol=:nonlinear, extra_lanes::Integer=0)
    axes = Any[SequenceChartAxis("client"),
               SequenceChartAxis("server"),
               SequenceChartAxis("cache"),
               (SequenceChartAxis("lane$i") for i in 1:extra_lanes)...]
    events = SequenceChartEvents([0.0, 1.0, 1.0, 1.0, 5.0, 9.0],
                                 [1, 2, 3, 3, 2, 1];
                                 labels=["send", "recv", "look", "miss", "reply", "done"])
    arrows = SequenceChartArrows([1, 2, 3, 5], [2, 3, 4, 6];
                                 labels=["req", "lookup", "miss", "resp"])
    SequenceChart("trace", axes; events=events, arrows=arrows,
                  orientation=orientation,
                  timeline=SequenceChartTimeline(; mode=mode))
end

# Apply an operation against a chart that is not inside an editor: the chart is
# the root, so a document-rooted reference resolves against it directly.
function _sc_apply(root, op)
    editor = (; document = root)
    evaluate_operation(editor, op)
end

const _sc_no_modifier = ModifierKeys()
const _sc_shift = ModifierKeys(; shift=true)
const _sc_ctrl = ModifierKeys(; ctrl=true)

"""
    test_sequencechart_projection()

The sequence chart projection: frame composition, both orientations, arrow
routes, reactivity, hit testing and selection round-trips.
"""
function test_sequencechart_projection()
    @testset "sequencechart" begin
        @testset "frame composition" begin
            canvas = _sequencechart_canvas(_sc_chart())
            @test canvas isa GraphicsCanvas
            @test Int(canvas.w) == 900 && Int(canvas.h) == 520

            els = _sc_flatten(canvas)
            texts = _sc_texts(els)
            # The title, every lane's name, and every arrow's label.
            @test "trace" in texts
            for lane in ("client", "server", "cache")
                @test lane in texts
            end
            for label in ("req", "lookup", "miss", "resp")
                @test label in texts
            end
            # One line per lane, plus hairlines; one mark per drawn event.
            @test _sc_count(els, GraphicsCircle) >= 1
            @test _sc_count(els, GraphicsLine) >= 3
            # The body is clipped, so the scrolling content sits in a viewport.
            @test _sc_count(els, GraphicsViewport) == 1
        end

        @testset "lanes are placed in display order" begin
            g = _geometry_of(_sequencechart_iomap(_sc_chart()))
            @test g.order == [1, 2, 3]
            @test issorted(g.lanes)
            # Every lane inside the body, and each event on its own lane's line.
            @test all(0 <= p <= g.body_h for p in g.lanes)

            chart = _sc_chart()
            chart.axis_order = [3, 1, 2]
            reordered = _geometry_of(_sequencechart_iomap(chart))
            @test reordered.order == [3, 1, 2]
            # Reordering is a permutation edit: the event table is untouched.
            @test collect(chart.events.axes) == [1, 2, 3, 3, 2, 1]
        end

        @testset "orientation" begin
            horizontal = _geometry_of(_sequencechart_iomap(_sc_chart()))
            vertical = _geometry_of(_sequencechart_iomap(_sc_chart(; orientation=:vertical)))
            @test !horizontal.vertical
            @test vertical.vertical
            # Time runs along the long side in each case: the flow axis is the
            # body's width when horizontal and its height when vertical.
            @test horizontal.scale.p1 - horizontal.scale.p0 ≈ horizontal.body_w
            @test vertical.scale.p1 - vertical.scale.p0 ≈ vertical.body_h

            # Both draw the same things; only where they land differs.
            @test length(vertical.visible_events) == length(horizontal.visible_events)
            @test length(vertical.shapes) == length(horizontal.shapes)
        end

        @testset "arrow routes" begin
            # A message returning to the lane it left has to arc: a straight
            # line along a lane would be invisible inside it.
            chart = _sc_chart()
            g = _geometry_of(_sequencechart_iomap(chart))
            same_lane = [s for s in g.shapes if s.c0 == s.c1]
            @test !isempty(same_lane)
            @test all(s.route === :arc for s in same_lane)
            @test all(s.height > 0 for s in same_lane)
            @test all(s.route === :direct for s in g.shapes if s.c0 != s.c1)

            # An explicit route overrides the choice.
            direct = _sc_chart()
            direct.arrow_kinds = CellVector(Any[SequenceChartArrowKind("x"; route=:direct)])
            direct.arrows.kinds = [1, 1, 1, 1]
            gd = _geometry_of(_sequencechart_iomap(direct))
            @test all(s.route === :direct for s in gd.shapes)
        end

        @testset "kind visibility hides a class" begin
            chart = _sc_chart()
            chart.arrow_kinds = CellVector(Any[SequenceChartArrowKind("shown"),
                                               SequenceChartArrowKind("hidden"; visible=false)])
            chart.arrows.kinds = [1, 2, 2, 1]
            g = _geometry_of(_sequencechart_iomap(chart))
            # Clearing one boolean is the whole of the show-and-hide story.
            @test length(g.shapes) == 2
            @test all(s.index in (1, 4) for s in g.shapes)
        end

        @testset "an unknown kind is tolerated" begin
            # An upstream domain may still be writing; a kind index naming
            # nothing must draw a default rather than throw.
            chart = _sc_chart()
            chart.events.kinds = [9, 9, 9, 9, 9, 9]
            chart.arrows.kinds = [7, 7, 7, 7]
            canvas = _sequencechart_canvas(chart)
            @test canvas isa GraphicsCanvas
            @test !isempty(_sc_flatten(canvas))

            # So must an endpoint row that is out of range.
            broken = _sc_chart()
            broken.arrows.targets = [2, 3, 4, 999]
            g = _geometry_of(_sequencechart_iomap(broken))
            @test length(g.shapes) == 3
        end

        @testset "zero-time regions are marked" begin
            # Three events share an instant, so the stretch between them has
            # width but no duration — and the picture has to say so.
            g = _geometry_of(_sequencechart_iomap(_sc_chart()))
            @test !isempty(g.zero_spans)

            # Under a proportional axis they have no width, so there is nothing
            # to mark: the shading exists to explain the other mappings.
            linear = _geometry_of(_sequencechart_iomap(_sc_chart(; mode=:time)))
            @test isempty(linear.zero_spans)
        end

        @testset "ticks and gutters" begin
            g = _geometry_of(_sequencechart_iomap(_sc_chart()))
            @test length(g.ticks) >= 2
            @test length(g.tick_labels) == length(g.ticks)
            # Every tick inside the window it was computed for.
            @test all(g.lo - 1e-9 <= c <= g.hi + 1e-9 for (c, _) in g.ticks)

            els = _sc_flatten(_sequencechart_canvas(_sc_chart()))
            texts = _sc_texts(els)
            # Both gutters carry the labels, so each appears twice.
            for label in g.tick_labels
                isempty(label) && continue
                shown = isempty(g.prefix) ? label : string("+", label)
                @test count(==(shown), texts) == 2
            end
        end

        @testset "reactivity: a column change repaints" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            before = _geometry_of(iomap)
            @test length(before.visible_events) == 6

            # Appending is a column reassign — which is how a live producer
            # feeds a growing chart.
            chart.events.times = [0.0, 1.0, 1.0, 1.0, 5.0, 9.0, 12.0]
            chart.events.axes = [1, 2, 3, 3, 2, 1, 3]
            after = _geometry_of(iomap)
            @test after !== before
            @test length(after.visible_events) == 7
        end

        @testset "reactivity: hover does not re-run the layout" begin
            # The point of the three-cell split. If hover invalidated the
            # geometry, every pointer move would re-decimate the whole trace.
            iomap = _sequencechart_iomap(_sc_chart())
            before = _geometry_of(iomap)
            plot = _plot_of(iomap)
            getfield(plot, :mouse_target)[] = get_event_reference(plot.chart, 2)
            plot.cursor = 1.0
            @test _geometry_of(iomap) === before

            # Nor does scrolling the lanes: it is a translation of the body.
            plot.cross_offset = 40
            @test _geometry_of(iomap) === before

            # Zooming, on the other hand, must: the visible range, the ticks and
            # the decimation all change with the window.
            plot.view = SequenceChartView(1, 0.0, 0.5)
            @test _geometry_of(iomap) !== before
        end

        @testset "the window survives a data change" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)
            view = SequenceChartView(2, 0.0, 1.5)
            plot.view = view

            chart.events.times = [0.0, 1.0, 1.0, 1.0, 5.0, 9.0, 20.0]
            chart.events.axes = [1, 2, 3, 3, 2, 1, 2]
            # The plot keeps its identity across the change, so the window a
            # reader had scrolled to is still theirs.
            @test _plot_of(iomap) === plot
            @test plot.view === view
        end

        @testset "window resolution" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            plot = _plot_of(iomap)
            coordinates = g.coordinates

            # Fitting shows the whole trace.
            @test g.lo ≈ coordinates[1]
            @test g.hi ≈ coordinates[end]

            # A window is measured from its anchor event.
            plot.view = SequenceChartView(2, 0.5, 2.0)
            windowed = _geometry_of(iomap)
            @test windowed.lo ≈ coordinates[2] + 0.5
            @test windowed.hi ≈ coordinates[2] + 2.5

            # An anchor that no longer exists falls back to fitting rather than
            # showing an empty stretch of nothing.
            plot.view = SequenceChartView(99, 0.0, 1.0)
            @test _geometry_of(iomap).lo ≈ coordinates[1]

            # Following the end keeps the span and pins it to the newest event.
            plot.view = SequenceChartView(1, 0.0, 1.0)
            plot.follow_end = true
            followed = _geometry_of(iomap)
            @test followed.hi ≈ coordinates[end]
            @test followed.hi - followed.lo ≈ 1.0
        end

        @testset "zoom into a burst of same-time events" begin
            # The case a time-denominated window cannot express: three events
            # share one instant, and a reader wants to see between them.
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            plot = _plot_of(iomap)
            c2, c4 = g.coordinates[2], g.coordinates[4]
            @test c4 > c2                       # the burst has real width
            @test chart.events.times[2] == chart.events.times[4]   # …and no duration

            plot.view = SequenceChartView(2, 0.0, (c4 - c2) / 2)
            zoomed = _geometry_of(iomap)
            @test zoomed.lo ≈ c2
            @test zoomed.hi < c4                # strictly inside the burst
            @test !isempty(zoomed.visible_events)
        end

        @testset "hit testing" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            plot = _plot_of(iomap)

            # Aim at a drawn event, in canvas coordinates.
            row = first(g.visible_events)
            flow = to_pixel(g.scale, g.coordinates[row])
            cross = g.lane_of[get_event_axis(chart.events, row)]
            x = round(Int, flow + g.body_x)
            y = round(Int, cross + g.body_y)
            @test SCT.find_event_hit(g, plot, x, y) == row

            # Well away from anything, nothing is hit.
            @test SCT.find_event_hit(g, plot, x, round(Int, y + 40)) === nothing

            # A lane is hit along its line.
            @test SCT.find_lane_hit(g, plot, round(Int, g.body_x + g.body_w / 2), y) ==
                  get_event_axis(chart.events, row)
        end

        @testset "a point maps back to the part a click there selects" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            projection = stage2.projection
            row = first(g.visible_events)
            x = round(Int, to_pixel(g.scale, g.coordinates[row]) + g.body_x)
            y = round(Int, g.lane_of[get_event_axis(chart.events, row)] + g.body_y)
            back = map_reference_backward(projection, stage2, PointReferenceStep(x, y))
            click = read_intent(projection, stage2, MouseClick(:left, x, y, _sc_no_modifier; time = 0.0))
            @test click isa ReplaceSelectionOperation
            @test back == click.path
            # The whole chain maps the point on to the chart's own event.
            whole = map_reference_backward(iomap.projection, iomap, PointReferenceStep(x, y))
            @test whole == get_event_reference(chart, row)
            # Far outside the chart, nothing is there.
            @test map_reference_backward(projection, stage2, PointReferenceStep(-50, -50)) === nothing
        end

        @testset "click selects" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            plot = _plot_of(iomap)
            stage2 = _stage2_iomap(iomap)
            projection = stage2.projection

            row = first(g.visible_events)
            flow = to_pixel(g.scale, g.coordinates[row])
            cross = g.lane_of[get_event_axis(chart.events, row)]
            press = MouseClick(:left, round(Int, flow + g.body_x),
                               round(Int, cross + g.body_y), _sc_no_modifier; time = 0.0)
            op = read_intent(projection, stage2, press)
            @test op isa ReplaceSelectionOperation

            # The reader speaks the plot's vocabulary; stage one peels the one
            # step it owns, so what reaches the document is chart-rooted.
            stage1 = iomap.step_iomaps[1][]
            inner = map_reference_backward(stage1.projection, stage1, op.path)
            @test inner == get_event_reference(chart, row)

            # And that selection names the occurrence back.
            chart.selection = inner
            @test get_selected_event(chart) == row
        end

        @testset "double click clears the window" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)
            plot.view = SequenceChartView(1, 0.0, 0.5)

            press = MouseClick(:left, round(Int, g.body_x + g.body_w / 2),
                               round(Int, g.body_y + g.body_h / 2), 2, _sc_no_modifier; time = 0.0)
            op = read_intent(stage2.projection, stage2, press)
            @test op isa ReplaceViewStateOperation      # a zoom is view state
            _sc_apply(plot, op)
            @test plot.view === nothing
        end

        @testset "Ctrl and the wheel zoom about the pointer" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)
            span_before = g.hi - g.lo

            x = round(Int, g.body_x + g.body_w / 2)
            y = round(Int, g.body_y + g.body_h / 2)
            focus = to_data(g.scale, g.body_w / 2)
            op = read_intent(stage2.projection, stage2, MouseScroll(0, 1, x, y, _sc_ctrl; time = 0.0))
            @test op isa ReplaceViewStateOperation
            _sc_apply(plot, op)

            zoomed = _geometry_of(iomap)
            @test zoomed.hi - zoomed.lo < span_before
            # Whatever was under the pointer is still under it — the only zoom
            # that lets someone drive toward a detail.
            @test to_data(zoomed.scale, g.body_w / 2) ≈ focus rtol=1e-6
        end

        # A turn of the wheel at the middle of the body of `iomap`.
        function _sc_wheel(iomap, dx, dy, modifiers = _sc_no_modifier)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            x = round(Int, g.body_x + g.body_w / 2)
            y = round(Int, g.body_y + g.body_h / 2)
            read_intent(stage2.projection, stage2, MouseScroll(dx, dy, x, y, modifiers; time = 0.0))
        end

        @testset "the wheel moves the window only while there is time to move to" begin
            iomap = _sequencechart_iomap(_sc_chart())
            plot = _plot_of(iomap)
            # The whole trace in view, and three lanes that fit: no turn is the
            # chart's, so the page around it scrolls.
            @test _sc_wheel(iomap, 0, 1) === nothing
            @test _sc_wheel(iomap, 0, 1, _sc_shift) === nothing
            @test _sc_wheel(iomap, 1, 0) === nothing
            # After a zoom, Shift and the wheel move the window along the time, and
            # a turn away shows the earlier time.
            _sc_apply(plot, _sc_wheel(iomap, 0, 2, _sc_ctrl))
            zoomed = _geometry_of(iomap)
            _sc_apply(plot, _sc_wheel(iomap, 0, 1, _sc_shift))
            moved = _geometry_of(iomap)
            @test moved.lo < zoomed.lo
            @test moved.hi - moved.lo ≈ zoomed.hi - zoomed.lo
            # The move stops at the first event, and the next turn is not the chart's.
            for _ in 1:40
                op = _sc_wheel(iomap, 0, 1, _sc_shift)
                op === nothing && break
                _sc_apply(plot, op)
            end
            @test _geometry_of(iomap).lo ≈ zoomed.coordinates[1]
            @test _sc_wheel(iomap, 0, 1, _sc_shift) === nothing
            @test _sc_wheel(iomap, 0, -1, _sc_shift) !== nothing
        end

        @testset "in a vertical chart the wheel moves along the time" begin
            iomap = _sequencechart_iomap(_sc_chart(; orientation = :vertical))
            plot = _plot_of(iomap)
            _sc_apply(plot, _sc_wheel(iomap, 0, 2, _sc_ctrl))
            zoomed = _geometry_of(iomap)
            _sc_apply(plot, _sc_wheel(iomap, 0, 1))
            @test _geometry_of(iomap).lo < zoomed.lo
        end

        @testset "a move back from the end stops the follow" begin
            iomap = _sequencechart_iomap(_sc_chart())
            plot = _plot_of(iomap)
            plot.view = SequenceChartView(1, 0.0, 2.0)
            plot.follow_end = true
            g = _geometry_of(iomap)
            @test g.hi ≈ g.coordinates[end]
            @test _sc_wheel(iomap, 0, -1, _sc_shift) === nothing
            _sc_apply(plot, _sc_wheel(iomap, 0, 1, _sc_shift))
            @test !plot.follow_end
            @test _geometry_of(iomap).lo < g.lo
        end

        @testset "the wheel scrolls the lanes inside their extent" begin
            iomap = _sequencechart_iomap(_sc_chart(); height = 80)
            plot = _plot_of(iomap)
            room = _geometry_of(iomap).cross_room
            @test room > 0
            @test _sc_wheel(iomap, 0, 1) === nothing
            for _ in 1:10
                op = _sc_wheel(iomap, 0, -1)
                op === nothing && break
                _sc_apply(plot, op)
            end
            @test plot.cross_offset == ceil(Int, room)
            @test _sc_wheel(iomap, 0, -1) === nothing
            @test _sc_wheel(iomap, 0, 1) !== nothing
        end

        @testset "the limits of the window" begin
            iomap = _sequencechart_iomap(_sc_chart())
            plot = _plot_of(iomap)
            stage2 = _stage2_iomap(iomap)
            g = _geometry_of(iomap)
            send(event) = (op = read_intent(stage2.projection, stage2, event);
                           op === nothing || _sc_apply_answer!(plot.chart, op); op)
            x = round(Int, g.body_x + g.body_w / 2)
            y = round(Int, g.body_y + g.body_h / 2)
            out(notches) = MouseScroll(0, -notches, x, y, _sc_ctrl; time = 0.0)
            in_(notches) = MouseScroll(0, notches, x, y, _sc_ctrl; time = 0.0)
            # A window that shows the whole trace can not zoom out: the notch and the
            # key are not the chart's.
            @test send(out(1)) === nothing
            @test send(KeyPress('-'; time = 0.0)) === nothing
            # A notch zooms by 1.15 about the pointer, and a zoom out stops at the
            # whole trace, which is no window at all.
            send(in_(2))
            @test plot.view isa SequenceChartView
            zoomed = _geometry_of(iomap)
            @test zoomed.hi - zoomed.lo ≈ (g.hi - g.lo) / 1.15^2
            for _ in 1:10
                send(out(1)) === nothing && break
            end
            @test plot.view === nothing
            @test send(out(1)) === nothing
            # A zoom in stops at the smallest span, and the next notch is not the chart's.
            notches = 0
            while notches < 1000
                send(in_(10)) === nothing && break
                notches += 1
            end
            @test notches < 1000
            limit = _geometry_of(iomap)
            @test limit.hi - limit.lo > 0
            @test send(in_(1)) === nothing
            # A scroll along the time stops at the first and the last event.
            send(MouseScroll(0, -5, x, y, _sc_shift; time = 0.0))
            @test _geometry_of(iomap).hi <= g.coordinates[end]
        end

        @testset "a press and a release with no move still select" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)
            stage2 = _stage2_iomap(iomap)
            g = _geometry_of(iomap)
            send(event) = (op = read_intent(stage2.projection, stage2, event);
                           op === nothing || _sc_apply_answer!(chart, op); op)
            row = first(g.visible_events)
            x = round(Int, to_pixel(g.scale, g.coordinates[row]) + g.body_x)
            y = round(Int, g.lane_of[get_event_axis(chart.events, row)] + g.body_y)
            send(MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
            @test plot.drag_anchor !== nothing
            send(DragEnd(x, y; time = 0.0))
            @test plot.drag_anchor === nothing && plot.drag_rect === nothing
            @test plot.view === nothing
            @test read_intent(stage2.projection, stage2,
                              MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
        end

        @testset "the mouse moves the view" begin
            iomap = _sequencechart_iomap(_sc_chart(); height = 80)
            plot = _plot_of(iomap)
            stage2 = _stage2_iomap(iomap)
            g = _geometry_of(iomap)
            send(event) = (op = read_intent(stage2.projection, stage2, event);
                           op === nothing || _sc_apply_answer!(plot.chart, op); op)
            mid_x = round(Int, g.body_x + g.body_w / 2)
            mid_y = round(Int, g.body_y + g.body_h / 2)
            body_y, body_h = round(Int, g.body_y), round(Int, g.body_h)
            zoomed = SequenceChartView(2, 0.0, (g.coordinates[end] - g.coordinates[1]) / 4)
            @test g.cross_room > 0

            # The middle button pans the time and the lanes, and a pan shows the
            # closed hand. The time follows the pointer along it, the lanes across.
            plot.view = zoomed
            before = _geometry_of(iomap)
            op = send(MouseDown(:middle, mid_x, mid_y, ModifierKeys(); time = 0.0))
            @test _sc_pointer_shape(op) === :closed_hand
            send(DragMove(mid_x - 40, mid_y - 10; time = 0.0))
            moved = _geometry_of(iomap)
            @test moved.lo > before.lo
            @test moved.hi - moved.lo ≈ before.hi - before.lo
            @test moved.lo - before.lo ≈ 40 / (before.scale.p1 - before.scale.p0) * (before.hi - before.lo)
            @test plot.cross_offset == 10
            send(DragEnd(mid_x - 40, mid_y - 10; time = 0.0))
            @test plot.drag_anchor === nothing
            # Shift and the left button pan too, and Escape puts back the view of the press.
            plot.view = zoomed
            plot.cross_offset = 0
            op = send(MouseDown(:left, mid_x, mid_y, _sc_shift; time = 0.0))
            @test _sc_pointer_shape(op) === :closed_hand
            send(DragMove(mid_x + 30, mid_y - 10; time = 0.0))
            @test plot.view != zoomed && plot.cross_offset == 10
            send(DragCancel(; time = 0.0))
            @test plot.view == zoomed && plot.cross_offset == 0
            @test plot.drag_anchor === nothing

            # A plain drag is a band along the time, drawn across all the lanes, and
            # the release zooms the time to it. The lanes stay.
            plot.view = nothing
            op = send(MouseDown(:left, mid_x, mid_y, ModifierKeys(); time = 0.0))
            @test _sc_pointer_shape(op) === :arrow
            send(DragMove(mid_x + 100, mid_y + 30; time = 0.0))
            @test plot.drag_rect == (mid_x, body_y, 100, body_h)
            send(DragEnd(mid_x + 100, mid_y + 30; time = 0.0))
            band = _geometry_of(iomap)
            @test band.lo ≈ to_data(g.scale, mid_x - g.body_x)
            @test band.hi ≈ to_data(g.scale, mid_x + 100 - g.body_x)
            @test plot.drag_rect === nothing && plot.cross_offset == 0
            # A band that did not grow is a click and leaves the window.
            plot.view = nothing
            send(MouseDown(:left, mid_x, mid_y, ModifierKeys(); time = 0.0))
            send(DragMove(mid_x + 3, mid_y; time = 0.0))
            send(DragEnd(mid_x + 3, mid_y; time = 0.0))
            @test plot.view === nothing

            # A drag on the time scale pans the time alone.
            @test g.gutter_h > 0
            axis_y = round(Int, g.body_y - g.gutter_h / 2)
            plot.view = zoomed
            before = _geometry_of(iomap)
            op = send(MouseDown(:left, mid_x, axis_y, ModifierKeys(); time = 0.0))
            @test _sc_pointer_shape(op) === :closed_hand
            send(DragMove(mid_x - 40, axis_y - 5; time = 0.0))
            @test _geometry_of(iomap).lo > before.lo
            @test plot.cross_offset == 0
            send(DragEnd(mid_x - 40, axis_y - 5; time = 0.0))
            # A double click on the time scale shows the whole trace; at the whole
            # trace it is nothing.
            plot.view = zoomed
            send(MouseClick(:left, mid_x, axis_y, 2, ModifierKeys(); time = 0.0))
            @test plot.view === nothing
            @test send(MouseClick(:left, mid_x, axis_y, 2, ModifierKeys(); time = 0.0)) === nothing
        end

        @testset "the keys move the view" begin
            iomap = _sequencechart_iomap(_sc_chart(); height = 80)
            plot = _plot_of(iomap)
            stage2 = _stage2_iomap(iomap)
            g = _geometry_of(iomap)
            send(event) = (op = read_intent(stage2.projection, stage2, event);
                           op === nothing || _sc_apply_answer!(plot.chart, op); op)
            page = (g.coordinates[end] - g.coordinates[1]) / 4
            zoomed = SequenceChartView(1, 0.0, page)
            whole = g.hi - g.lo

            # At the whole trace Ctrl+- and Ctrl+0 are not the chart's: they go on to
            # the zoom of the interface.
            @test send(KeyDown(:minus, _sc_ctrl; time = 0.0)) === nothing
            @test send(KeyDown(:zero, _sc_ctrl; time = 0.0)) === nothing
            # Ctrl+= zooms about the middle, Ctrl+- zooms out, Ctrl+0 shows the whole trace.
            @test send(KeyDown(:equals, _sc_ctrl; time = 0.0)) !== nothing
            v = _geometry_of(iomap)
            @test v.hi - v.lo ≈ whole / 1.15
            @test (v.lo + v.hi) / 2 ≈ (g.lo + g.hi) / 2
            send(KeyDown(:minus, _sc_ctrl; time = 0.0))
            @test plot.view === nothing
            plot.view = zoomed
            send(KeyDown(:zero, _sc_ctrl; time = 0.0))
            @test plot.view === nothing
            # A typed character with Ctrl is not a second zoom; `+`, `-` and `0` are keys.
            @test send(KeyPress('=', _sc_ctrl; time = 0.0)) === nothing
            @test send(KeyPress('+', _sc_shift; time = 0.0)) !== nothing
            send(KeyPress('-'; time = 0.0))
            @test plot.view === nothing
            send(KeyPress('='; time = 0.0))
            send(KeyPress('0'; time = 0.0))
            @test plot.view === nothing

            # Page Down scrolls the lanes a page, as far as their room goes; Page Up
            # brings them back.
            room = ceil(Int, g.cross_room)
            @test room > 0
            send(KeyDown(:page_down, ModifierKeys(); time = 0.0))
            @test plot.cross_offset == min(round(Int, g.body_h), room)
            send(KeyDown(:page_up, ModifierKeys(); time = 0.0))
            @test plot.cross_offset == 0
            @test send(KeyDown(:page_up, ModifierKeys(); time = 0.0)) === nothing
            # Alt and the page keys scroll the time a page, the window, inside the trace.
            plot.view = zoomed
            send(KeyDown(:page_down, ModifierKeys(; alt = true); time = 0.0))
            moved = _geometry_of(iomap)
            @test moved.lo ≈ g.coordinates[1] + page && moved.hi - moved.lo ≈ page
            send(KeyDown(:page_up, ModifierKeys(; alt = true); time = 0.0))
            @test _geometry_of(iomap).lo ≈ g.coordinates[1]
            @test send(KeyDown(:page_up, ModifierKeys(; alt = true); time = 0.0)) === nothing
            # The arrows and Shift with them stay the navigation along the events.
            for key in (:left, :right, :up, :down)
                @test send(KeyDown(key, ModifierKeys(); time = 0.0)) === nothing
                @test send(KeyDown(key, _sc_shift; time = 0.0)) === nothing
            end
            # In a vertical chart the time runs down: the page keys scroll it, and Alt the lanes.
            vertical = _sequencechart_iomap(_sc_chart(; orientation = :vertical))
            vplot = _plot_of(vertical)
            vstage = _stage2_iomap(vertical)
            vplot.view = zoomed
            op = read_intent(vstage.projection, vstage, KeyDown(:page_down, ModifierKeys(); time = 0.0))
            _sc_apply_answer!(vplot.chart, op)
            @test _geometry_of(vertical).lo ≈ _geometry_of(vertical).coordinates[1] + page
        end

        @testset "the menu and the buttons" begin
            chart = _sc_chart()
            view = make_sequence_chart_projection(; measure = FontFileMeasure())
            iomap = print_document(view, view, chart, PrinterContext())
            canvas_iomap = _find_sequence_chart_canvas_iomap(iomap)
            plot = canvas_iomap.input
            send(event) = (op = read_intent(view, iomap, event); op === nothing || _sc_apply_answer!(chart, op); op)
            viewports() = [e for e in canvas_iomap.output.elements if e isa GraphicsViewport]

            # The menu holds the view actions, and an action that changes nothing is
            # disabled: a chart that shows its whole trace can not zoom out.
            menu = compute_context_menu(plot)
            labels = [String(string(item.action.label)) for item in menu.elements]
            @test labels == ["Zoom in", "Zoom out", "Show the whole trace"]
            @test [item.keys for item in menu.elements] == [["Ctrl+="], ["Ctrl+-"], ["Ctrl+0"]]
            @test [item.enabled for item in menu.elements] == [true, false, false]
            evaluate_operation(nothing, menu.elements[1].operation)
            @test plot.view isa SequenceChartView
            menu = compute_context_menu(plot)
            @test menu.elements[3].enabled
            evaluate_operation(nothing, menu.elements[3].operation)
            @test plot.view === nothing
            # A right click on the body opens that menu.
            g = canvas_iomap.geometry
            op = read_intent(view, iomap, MouseClick(:right, round(Int, g.body_x) + 20, round(Int, g.body_y) + 20,
                                                     1, ModifierKeys(); time = 0.0))
            @test op !== nothing
            @test compute_context_menu(SequenceChartPlot(nothing)) === nothing

            # The buttons: their icons, and the disabled state of an action at a limit.
            buttons = plot.toolbar.elements
            @test [item.action.icon for item in buttons] == [:zoom_in, :zoom_out, :maximize]
            @test [item.enabled for item in buttons] == [true, false, false]
            @test all(item -> item.tooltip isa AbstractString && occursin("(Ctrl+", item.tooltip), buttons)
            # They show only while the pointer is over the chart.
            @test length(viewports()) == 1
            replace_mouse_target!(chart, EmptyReference())
            @test length(viewports()) == 2
            shown = first(SCT._find_shown_sequence_chart_parts(canvas_iomap))
            @test shown.field == "toolbar"
            @test shown.x + shown.w < canvas_iomap.output.w && shown.y < g.body_y
            # A click on the first button zooms in; the third then shows the whole trace.
            centre(k) = (shown.x + (2k - 1) * shown.w ÷ 6, shown.y + shown.h ÷ 2)
            bx, by = centre(1)
            # The button under the pointer lights, and a press holds it down.
            send(MouseMove(bx, by, MouseButtons(), ModifierKeys(); time = 0.0))
            @test get_mouse_target(buttons[1]) !== nothing
            @test get_mouse_target(buttons[2]) === nothing
            @test length(viewports()) == 2
            send(MouseDown(:left, bx, by, ModifierKeys(); time = 0.0))
            @test plot.drag_anchor === nothing
            @test buttons[1].pressed
            send(MouseUp(:left, bx, by, ModifierKeys(); time = 0.0))
            @test !buttons[1].pressed
            send(MouseClick(:left, bx, by, 1, ModifierKeys(); time = 0.0))
            @test plot.view isa SequenceChartView
            @test buttons[3].enabled
            cx, cy = centre(3)
            send(MouseClick(:left, cx, cy, 1, ModifierKeys(); time = 0.0))
            @test plot.view === nothing
            # A drag hides them, and so does the leave of the pointer.
            plot.drag_anchor = (0, 0, :zoom, (g.lo, g.hi), g.scale, 0, nothing, false)
            @test length(viewports()) == 1
            plot.drag_anchor = nothing
            replace_mouse_target!(chart, nothing)
            @test length(viewports()) == 1
            # A chart too small for the buttons shows none.
            small = _sc_chart()
            small_view = make_sequence_chart_projection(; measure = FontFileMeasure(), width = 160, height = 100)
            small_iomap = _find_sequence_chart_canvas_iomap(print_document(small_view, small_view, small, PrinterContext()))
            replace_mouse_target!(small, EmptyReference())
            @test !any(part -> part.field == "toolbar", SCT._find_shown_sequence_chart_parts(small_iomap))
        end

        @testset "the bars of a scrolled chart" begin
            for orientation in (:horizontal, :vertical)
                # Twelve lanes do not fit across a narrow vertical chart.
                chart = _sc_chart(; orientation, extra_lanes = orientation === :vertical ? 9 : 0)
                view = make_sequence_chart_projection(; measure = FontFileMeasure(), height = orientation === :horizontal ? 90 : 520,
                                                      width = orientation === :horizontal ? 900 : 160)
                iomap = print_document(view, view, chart, PrinterContext())
                canvas_iomap = _find_sequence_chart_canvas_iomap(iomap)
                plot = canvas_iomap.input
                send(event) = (op = read_intent(view, iomap, event); op === nothing || _sc_apply_answer!(chart, op); op)
                bars() = Dict(part.field => part for part in SCT._find_shown_sequence_chart_parts(canvas_iomap))
                time_bar, lane_bar = plot.time_scroll_bar, plot.lane_scroll_bar
                g = canvas_iomap.geometry
                extent = (g.coordinates[1], g.coordinates[end])
                body_x, body_y = round(Int, g.body_x), round(Int, g.body_y)
                body_w, body_h = round(Int, g.body_w), round(Int, g.body_h)
                across_time = orientation === :horizontal

                # The time runs along one edge of the body and the lanes along the
                # other.
                @test time_bar.orientation === orientation
                @test lane_bar.orientation === (across_time ? :vertical : :horizontal)
                # At the whole trace the bar of the time is not there; the lanes do not
                # fit, so their bar is.
                @test time_bar.thumb_size == 1.0
                @test lane_bar.thumb_size < 1.0
                @test lane_bar.thumb_size ≈ (across_time ? body_h : body_w) / ((across_time ? body_h : body_w) + g.cross_room)
                @test lane_bar.value == 0.0
                shown = bars()
                @test collect(keys(shown)) == ["lane_scroll_bar"]
                # A zoom: the bar of the time holds the place of the window, and the bar
                # of the lanes is the one along the other edge, which the time bar stops before.
                span = extent[2] - extent[1]
                window = span / 4
                plot.view = SequenceChartView(1, 0.0, window)
                @test time_bar.thumb_size ≈ 0.25
                @test time_bar.value == 0.0
                shown = bars()
                @test Set(keys(shown)) == Set(["time_scroll_bar", "lane_scroll_bar"])
                time_part, lane_part = shown["time_scroll_bar"], shown["lane_scroll_bar"]
                if across_time
                    @test lane_part.x + lane_part.w == body_x + body_w && lane_part.y == body_y && lane_part.h == body_h
                    @test time_part.x == body_x && time_part.y + time_part.h == body_y + body_h
                    @test time_part.x + time_part.w == lane_part.x
                else
                    @test time_part.x + time_part.w == body_x + body_w && time_part.y == body_y && time_part.h == body_h
                    @test lane_part.x == body_x && lane_part.y + lane_part.h == body_y + body_h
                    @test lane_part.x + lane_part.w == time_part.x
                end
                plot.view = SequenceChartView(2, 0.0, window)
                lo = canvas_iomap.geometry.lo
                @test time_bar.value ≈ (lo - extent[1]) / (span - window)

                # A click on the track of the time bar moves the window a page; a press
                # there starts no band.
                plot.view = SequenceChartView(1, 0.0, window)
                part = bars()["time_scroll_bar"]
                far = across_time ? (part.x + part.w - 2, part.y + part.h ÷ 2) : (part.x + part.w ÷ 2, part.y + part.h - 2)
                send(MouseDown(:left, far..., ModifierKeys(); time = 0.0))
                @test plot.drag_anchor === nothing
                send(MouseUp(:left, far..., ModifierKeys(); time = 0.0))
                send(MouseClick(:left, far..., 1, ModifierKeys(); time = 0.0))
                moved = canvas_iomap.geometry
                @test moved.lo > g.coordinates[1] && moved.hi - moved.lo ≈ window

                # A drag of the thumb moves the window with the pointer, and the plot
                # keeps the drag.
                plot.view = SequenceChartView(1, 0.0, window)
                part = bars()["time_scroll_bar"]
                at = time_bar.value * (1 - time_bar.thumb_size) + time_bar.thumb_size / 2
                along = across_time ? (part.x + round(Int, part.w * at), part.y + part.h ÷ 2) :
                                      (part.x + part.w ÷ 2, part.y + round(Int, part.h * at))
                send(MouseDown(:left, along..., ModifierKeys(); time = 0.0))
                @test time_bar.thumb_drag !== nothing
                @test plot.drag_anchor === nothing
                shift = across_time ? (40, 0) : (0, 40)
                send(DragMove((along .+ shift)...; time = 0.0))
                dragged = canvas_iomap.geometry
                @test dragged.lo > g.coordinates[1] && dragged.hi - dragged.lo ≈ window
                send(DragEnd((along .+ shift)...; time = 0.0))
                @test time_bar.thumb_drag === nothing

                # A click on the track of the lane bar scrolls the lanes a page, and a
                # drag of its thumb scrolls them with the pointer.
                plot.view = nothing
                part = bars()["lane_scroll_bar"]
                far = across_time ? (part.x + part.w ÷ 2, part.y + part.h - 2) : (part.x + part.w - 2, part.y + part.h ÷ 2)
                send(MouseDown(:left, far..., ModifierKeys(); time = 0.0))
                send(MouseUp(:left, far..., ModifierKeys(); time = 0.0))
                send(MouseClick(:left, far..., 1, ModifierKeys(); time = 0.0))
                @test plot.cross_offset > 0
                plot.cross_offset = 0
                at = lane_bar.thumb_size / 2
                along = across_time ? (part.x + part.w ÷ 2, part.y + round(Int, part.h * at)) :
                                      (part.x + round(Int, part.w * at), part.y + part.h ÷ 2)
                send(MouseDown(:left, along..., ModifierKeys(); time = 0.0))
                @test lane_bar.thumb_drag !== nothing
                shift = across_time ? (0, 10) : (10, 0)
                send(DragMove((along .+ shift)...; time = 0.0))
                @test plot.cross_offset > 0
                send(DragEnd((along .+ shift)...; time = 0.0))
                @test lane_bar.thumb_drag === nothing
                # The lanes scrolled to the end: the thumb is at the end of its track.
                plot.cross_offset = ceil(Int, g.cross_room)
                @test lane_bar.value ≈ 1.0
            end
        end

        @testset "hover writes overlay state only" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)

            row = first(g.visible_events)
            flow = to_pixel(g.scale, g.coordinates[row])
            cross = g.lane_of[get_event_axis(chart.events, row)]
            move = MouseMove(round(Int, flow + g.body_x), round(Int, cross + g.body_y); time = 0.0)
            op = read_intent(stage2.projection, stage2, move)
            @test op !== nothing
            _sc_apply(plot, op)
            @test plot.cursor !== nothing

            # Repeating the same move says nothing new, so it declines rather
            # than writing a value that would invalidate cells for no reason.
            @test read_intent(stage2.projection, stage2, move) === nothing

            # A move off the plot, as the move to (-1, -1) that the pointer
            # leaving gives, clears the readout, so no stale readout outlives the
            # pointer.
            leave = read_intent(stage2.projection, stage2, MouseMove(-1, -1; time = 0.0))
            _sc_apply(plot, leave)
            @test plot.cursor === nothing
        end

        @testset "reader declines outside its business" begin
            iomap = _sequencechart_iomap(_sc_chart())
            stage2 = _stage2_iomap(iomap)
            # A click on the background is not a selection of anything.
            @test read_intent(stage2.projection, stage2,
                              MouseClick(:left, 2, 2, _sc_no_modifier; time = 0.0)) === nothing
        end

        @testset "long arrows split" begin
            # An arrow far longer than the window says nothing its two ends do
            # not: its angle carries no information and its middle is off
            # screen. Each end keeps a stub instead.
            chart = SequenceChart("long",
                Any[SequenceChartAxis("a"), SequenceChartAxis("b")];
                events=SequenceChartEvents(collect(0.0:1.0:200.0),
                                           [1 + (i % 2) for i in 0:200]),
                arrows=SequenceChartArrows([1], [201]),
                timeline=SequenceChartTimeline(; mode=:step))
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)
            # Zoom in until the arrow's ends are far outside the window.
            plot.view = SequenceChartView(1, 0.0, 4.0)
            g = _geometry_of(iomap)
            shape = only(g.shapes)
            @test shape.split !== nothing
            near, far = shape.split
            @test abs(near[2] - near[1]) ≈ chart.style.split_stub_px
            @test abs(far[2] - far[1]) ≈ chart.style.split_stub_px

            # Zoomed back out to the whole trace it is drawn whole again.
            plot.view = nothing
            @test only(_geometry_of(iomap).shapes).split === nothing
        end

        @testset "the overlay marks what is selected and what is under the pointer" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)
            before = length(_sc_flatten(_sequencechart_canvas(_sc_chart())))

            # A selected occurrence gets a ring rather than a recolour: the
            # mark's own colour carries its kind, and overwriting it would cost
            # the reader the thing they selected it to see.
            plot.selection = lift_sequence_chart_reference(plot, get_event_reference(chart, 2))
            selected = _sc_flatten(iomap.output)
            rings = [e for e in selected
                     if e isa GraphicsCircle && Int(e.border_width) > 0]
            @test length(rings) == 1
            @test Int(rings[1].radius) > chart.style.event_radius

            # The arrow that the mouse target names is re-stroked thicker.
            plot.selection = nothing
            getfield(plot, :mouse_target)[] = lift_sequence_chart_reference(plot, get_arrow_reference(chart, 1))
            lit = _sc_flatten(iomap.output)
            @test any(e -> e isa GraphicsPolyline && Int(e.width) == 3, lit)
        end

        @testset "selecting the document marks the picture" begin
            # The path the editor actually takes: nothing writes to the plot.
            # The *document's* selection changes, the plot's is computed from it
            # through the stage-one forward map, and the overlay follows —
            # setting the plot's selection by hand, as the test above does,
            # would pass even if that chain were broken.
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            _ring_count(canvas) = count(e -> e isa GraphicsCircle && Int(e.border_width) > 0,
                                        _sc_flatten(canvas))
            @test _ring_count(iomap.output) == 0

            chart.selection = get_event_reference(chart, 2)
            @test _plot_of(iomap).selection !== nothing
            @test _ring_count(iomap.output) == 1
        end

        @testset "the gutter reads out the pointer and the window" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)

            # The window's extent is always shown.
            texts = _sc_texts(_sc_flatten(iomap.output))
            @test any(t -> occursin("Δ", t), texts)

            # The pointer's time appears once it has one, with a line carrying
            # that moment across every lane.
            plot.cursor = 3.0
            with_cursor = _sc_flatten(iomap.output)
            @test any(e -> e isa GraphicsLine && e.dash == (3, 3), with_cursor)
        end

        @testset "an empty chart still draws" begin
            canvas = _sequencechart_canvas(SequenceChart("empty", Any[]))
            @test canvas isa GraphicsCanvas
            @test !isempty(_sc_flatten(canvas))
        end
    end
end

"""
    test_sequencechart_scale()

The claim that makes the domain usable on a real trace: the amount of output is
bounded by the size of the chart, not by the length of what it shows.

If these stop holding, a chart of a long trace is no longer a drawing of it — it
is an attempt to put one graphics element on screen per event, which no backend
survives. The bounds are asserted against **spread** data as well as clustered,
because a bundle of arrows all landing on one pixel is the easy case; arrows
spread evenly across the window are the one that can defeat a dedup keyed on
position.
"""
function test_sequencechart_scale()
    @testset "sequencechart scale" begin
        # Twenty thousand events over eight lanes, with bursts and quiet gaps.
        big = make_sequencechart_large_document_example()

        @testset "a long trace draws in bounded output" begin
            iomap = _sequencechart_iomap(big; width=900, height=520)
            g = _geometry_of(iomap)
            @test get_event_count(big.events) == 20_000

            # At most one mark per lane, per kind, per mark-radius of the
            # flow axis — the bound the decimation promises.
            @test length(g.visible_events) <=
                  8 * (g.body_w ÷ big.style.event_radius + 2)
            @test length(g.visible_events) < get_event_count(big.events) ÷ 4

            elements = _sc_flatten(iomap.output)
            @test length(elements) < 6_000

            # And it is not empty: bounding the output must not mean dropping it.
            @test !isempty(g.visible_events)
            @test !isempty(g.shapes)
        end

        @testset "spread arrows stay bounded" begin
            # The hard case for a position-keyed dedup: every arrow on its own
            # pixel column, between alternating lanes.
            n = 20_000
            times = collect(range(0.0, 1000.0; length=n))
            lanes = [1 + (i % 4) for i in 1:n]
            chart = SequenceChart("spread",
                Any[SequenceChartAxis("l$i") for i in 1:4];
                events=SequenceChartEvents(times, lanes),
                arrows=SequenceChartArrows(collect(1:(n-1)), collect(2:n)),
                timeline=SequenceChartTimeline(; mode=:time))
            iomap = _sequencechart_iomap(chart; width=900, height=520)
            g = _geometry_of(iomap)
            # Every arrow is a candidate — they all touch the window — but only
            # the ones that add pixels are drawn.
            @test length(g.shapes) < 4_000
            @test length(_sc_flatten(iomap.output)) < 8_000
        end

        @testset "zooming in is exact" begin
            # Bounding the output is a claim about crowding, not about accuracy:
            # once no two events share a pixel, every one of them is drawn.
            iomap = _sequencechart_iomap(big; width=900, height=520)
            plot = _plot_of(iomap)
            g = _geometry_of(iomap)
            # A window over ten consecutive events.
            span = g.coordinates[11] - g.coordinates[1]
            plot.view = SequenceChartView(1, 0.0, span)
            zoomed = _geometry_of(iomap)
            i0, i1 = get_visible_event_range(zoomed.coordinates, zoomed.lo, zoomed.hi)
            @test length(zoomed.visible_events) == i1 - i0 + 1
        end

        @testset "the timeline pass is not redone for a repaint" begin
            # The O(n) pass over twenty thousand events must survive panning,
            # hovering and resizing — that is why it has a cell of its own.
            iomap = _sequencechart_iomap(big)
            stage2 = _stage2_iomap(iomap)
            before = stage2.timeline
            plot = _plot_of(iomap)
            plot.view = SequenceChartView(1, 0.0, 5.0)
            getfield(plot, :mouse_target)[] = get_event_reference(big, 5)
            @test stage2.timeline === before

            # Changing the data does redo it, since that is what it derives.
            big.events.times = collect(range(0.0, 1.0; length=20_000))
            @test stage2.timeline !== before
        end

        @testset "hit testing a long trace is quick" begin
            iomap = _sequencechart_iomap(big)
            g = _geometry_of(iomap)
            plot = _plot_of(iomap)
            x = round(Int, g.body_x + g.body_w / 2)
            y = round(Int, g.body_y + g.body_h / 2)
            SCT.find_event_hit(g, plot, x, y)          # warm up
            elapsed = @elapsed for _ in 1:200
                SCT.find_event_hit(g, plot, x, y)
                SCT.find_arrow_hit(g, plot, x, y)
            end
            # Hit testing walks what is drawn, not what exists, so pointer
            # tracking stays interactive however long the trace is.
            @test elapsed < 2.0
        end
    end
end

"""
    test_sequencechart_selection()

Part navigation, causality navigation and lane reordering — the gestures that
treat the chart as a graph rather than a picture.
"""
function test_sequencechart_selection()
    @testset "sequencechart selection" begin
        @testset "parts" begin
            chart = _sc_chart()
            parts = get_sequence_chart_parts(chart)
            # Title, three lanes, the two tables.
            @test length(parts) == 6
            for (index, part) in enumerate(parts)
                @test get_sequence_chart_part_index(chart, part) == index
            end
            @test get_sequence_chart_part_index(chart, nothing) == 0

            # Parts follow the display order, not the listed one.
            chart.axis_order = [3, 1, 2]
            reordered = get_sequence_chart_parts(chart)
            @test reordered[2] == get_axis_reference(chart, 3)
        end

        @testset "row references evaluate to the row" begin
            chart = _sc_chart()
            @test evaluate_reference(chart, get_event_reference(chart, 2)) ==
                  (1.0, 2, 0, "recv")
            @test evaluate_reference(chart, get_arrow_reference(chart, 1)) ==
                  (1, 2, 0, "req")
            # Out of range is nothing, not an error: a reference can outlive the
            # rows it named.
            @test evaluate_reference(chart, get_event_reference(chart, 99)) === nothing
        end

        @testset "a row step hashes as it compares" begin
            chart = _sc_chart()
            first_path = get_event_reference(chart, 2)
            second_path = get_event_reference(chart, 2)
            @test first_path == second_path
            @test hash(first_path) == hash(second_path)
            @test length(Set([first_path, second_path])) == 1
        end

        @testset "arrow keys walk the parts" begin
            chart = _sc_chart()
            chart.selection = nothing
            op = read_gesture(chart, KeyDown(:right, _sc_no_modifier; time = 0.0))
            @test op isa ReplaceSelectionOperation
            _sc_apply(chart, op)
            @test get_sequence_chart_part_index(chart, chart.selection) == 1

            for expected in 2:6
                _sc_apply(chart, read_gesture(chart, KeyDown(:down, _sc_no_modifier; time = 0.0)))
                @test get_sequence_chart_part_index(chart, chart.selection) == expected
            end
            # At the end there is nowhere to go, so the gesture is declined
            # rather than consumed.
            @test read_gesture(chart, KeyDown(:down, _sc_no_modifier; time = 0.0)) === nothing
        end

        @testset "Alt and an arrow walk the chart as they walk any document" begin
            alt = ModifierKeys(alt = true)
            chart = _sc_chart()
            chart.selection = EmptyReference()
            # The whole chart: nothing above it, no sibling, and down is the
            # first part.
            @test read_gesture(chart, KeyDown(:up, alt; time = 0.0)) === nothing
            @test read_gesture(chart, KeyDown(:left, alt; time = 0.0)) === nothing
            @test read_gesture(chart, KeyDown(:right, alt; time = 0.0)) === nothing
            _sc_apply(chart, read_gesture(chart, KeyDown(:down, alt; time = 0.0)))
            @test get_sequence_chart_part_index(chart, chart.selection) == 1
            # Sideways between the parts; the first part keeps the selection.
            _sc_apply(chart, read_gesture(chart, KeyDown(:right, alt; time = 0.0)))
            @test get_sequence_chart_part_index(chart, chart.selection) == 2
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, alt; time = 0.0)))
            @test get_sequence_chart_part_index(chart, chart.selection) == 1
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, alt; time = 0.0)))
            @test get_sequence_chart_part_index(chart, chart.selection) == 1
            # A part has nothing below it here, and up is the whole chart.
            @test read_gesture(chart, KeyDown(:down, alt; time = 0.0)) === nothing
            _sc_apply(chart, read_gesture(chart, KeyDown(:up, alt; time = 0.0)))
            @test get_sequence_chart_part_index(chart, chart.selection) == 0
        end

        @testset "arrow keys walk the trace once an event is selected" begin
            chart = _sc_chart()
            chart.selection = get_event_reference(chart, 3)
            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_no_modifier; time = 0.0)))
            @test get_selected_event(chart) == 4
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, _sc_no_modifier; time = 0.0)))
            @test get_selected_event(chart) == 3
        end

        @testset "shift walks one lane" begin
            # Events 1 and 6 are the client's; everything between is not.
            chart = _sc_chart()
            chart.selection = get_event_reference(chart, 1)
            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_shift; time = 0.0)))
            @test get_selected_event(chart) == 6
            @test read_gesture(chart, KeyDown(:right, _sc_shift; time = 0.0)) === nothing
        end

        @testset "ctrl follows causality" begin
            # This is the move that makes a sequence chart a graph: not "what is
            # next to this" but "what caused it".
            chart = _sc_chart()
            chart.selection = get_event_reference(chart, 4)
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, _sc_ctrl; time = 0.0)))
            @test get_selected_event(chart) == 3       # arrow 3 runs 3 → 4

            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_ctrl; time = 0.0)))
            @test get_selected_event(chart) == 4

            # An occurrence nothing caused declines rather than jumping.
            chart.selection = get_event_reference(chart, 1)
            @test read_gesture(chart, KeyDown(:left, _sc_ctrl; time = 0.0)) === nothing
        end

        @testset "lanes reorder" begin
            chart = _sc_chart()
            chart.selection = get_axis_reference(chart, 1)
            op = read_gesture(chart, KeyDown(:down, ModifierKeys(; ctrl=true, shift=true); time = 0.0))
            @test op !== nothing
            _sc_apply(chart, op)
            @test get_axis_display_order(chart) == [2, 1, 3]
            # Only the permutation moved; the event table still names lanes by
            # identity.
            @test collect(chart.events.axes) == [1, 2, 3, 3, 2, 1]
        end

        @testset "editing keeps the indices consistent" begin
            chart = _sc_chart()
            # Deleting the cache lane takes its events, and the arrows that
            # reached them, and renumbers what is left.
            _sc_apply(chart, delete_axis(chart, 3))
            @test length(chart.axes) == 2
            @test all(1 <= Int(a) <= 2 for a in chart.events.axes)
            @test get_event_count(chart.events) == 4
            n = get_event_count(chart.events)
            @test all(1 <= Int(s) <= n && 1 <= Int(t) <= n
                      for (s, t) in zip(chart.arrows.sources, chart.arrows.targets))
        end

        @testset "inserting events remaps arrow endpoints" begin
            chart = _sc_chart()
            before = collect(chart.arrows.targets)
            _sc_apply(chart, insert_events(chart, 1; times = [-1.0], axes = [1]))
            @test get_event_count(chart.events) == 7
            # Every arrow still points at the occurrence it always did, one row
            # further along.
            @test collect(chart.arrows.targets) == before .+ 1
            @test collect(chart.arrows.sources) == [2, 3, 4, 6]
        end
    end
end
