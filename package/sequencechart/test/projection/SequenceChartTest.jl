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

const SCT = SequenceChartPlotToGraphicsModule

_sequencechart_projection(; width::Integer=900, height::Integer=520) =
    ChainingProjection(
        SequenceChartToSequenceChartPlot(),
        SequenceChartPlotToGraphicsCanvas(measure=truetype_measure_text,
                                          width=width, height=height))

_sequencechart_iomap(chart; kw...) = (p = _sequencechart_projection(; kw...);
                                      print_document(p, p, chart, PrinterContext()))

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
function _sc_chart(; orientation::Symbol=:horizontal, mode::Symbol=:nonlinear)
    axes = Any[SequenceChartAxis("client"),
               SequenceChartAxis("server"),
               SequenceChartAxis("cache")]
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
            plot.hovered = event_reference(plot.chart, 2)
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
            cross = g.lane_of[event_axis(chart.events, row)]
            x = round(Int, flow + g.body_x)
            y = round(Int, cross + g.body_y)
            @test SCT.event_hit(g, plot, x, y) == row

            # Well away from anything, nothing is hit.
            @test SCT.event_hit(g, plot, x, round(Int, y + 40)) === nothing

            # A lane is hit along its line.
            @test SCT.lane_hit(g, plot, round(Int, g.body_x + g.body_w / 2), y) ==
                  event_axis(chart.events, row)
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
            cross = g.lane_of[event_axis(chart.events, row)]
            press = MousePress(:left, round(Int, flow + g.body_x),
                               round(Int, cross + g.body_y), _sc_no_modifier)
            op = read_intent(projection, stage2, press)
            @test op isa ReplaceSelectionOperation

            # The reader speaks the plot's vocabulary; stage one peels the one
            # step it owns, so what reaches the document is chart-rooted.
            stage1 = iomap.step_iomaps[1][]
            inner = map_reference_backward(stage1.projection, stage1, op.path)
            @test inner == event_reference(chart, row)

            # And that selection names the occurrence back.
            chart.selection = inner
            @test selected_event(chart) == row
        end

        @testset "double click clears the window" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)
            plot.view = SequenceChartView(1, 0.0, 0.5)

            press = MousePress(:left, round(Int, g.body_x + g.body_w / 2),
                               round(Int, g.body_y + g.body_h / 2), 2, _sc_no_modifier)
            op = read_intent(stage2.projection, stage2, press)
            @test op isa ReplaceReferencedValueOperation
            _sc_apply(plot, op)
            @test plot.view === nothing
        end

        @testset "wheel zooms about the pointer" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)
            span_before = g.hi - g.lo

            x = round(Int, g.body_x + g.body_w / 2)
            y = round(Int, g.body_y + g.body_h / 2)
            focus = to_data(g.scale, g.body_w / 2)
            op = read_intent(stage2.projection, stage2, MouseScroll(0, 1, x, y))
            @test op isa ReplaceReferencedValueOperation
            _sc_apply(plot, op)

            zoomed = _geometry_of(iomap)
            @test zoomed.hi - zoomed.lo < span_before
            # Whatever was under the pointer is still under it — the only zoom
            # that lets someone drive toward a detail.
            @test to_data(zoomed.scale, g.body_w / 2) ≈ focus rtol=1e-6
        end

        @testset "hover writes overlay state only" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            g = _geometry_of(iomap)
            stage2 = _stage2_iomap(iomap)
            plot = _plot_of(iomap)

            row = first(g.visible_events)
            flow = to_pixel(g.scale, g.coordinates[row])
            cross = g.lane_of[event_axis(chart.events, row)]
            move = MouseMove(round(Int, flow + g.body_x), round(Int, cross + g.body_y))
            op = read_intent(stage2.projection, stage2, move)
            @test op !== nothing
            _sc_apply(plot, op)
            @test plot.hovered !== nothing
            @test plot.cursor !== nothing

            # Repeating the same move says nothing new, so it declines rather
            # than writing a value that would invalidate cells for no reason.
            @test read_intent(stage2.projection, stage2, move) === nothing

            # Leaving clears both, so no stale readout outlives the pointer.
            leave = read_intent(stage2.projection, stage2, MouseLeave(0, 0))
            _sc_apply(plot, leave)
            @test plot.hovered === nothing
            @test plot.cursor === nothing
        end

        @testset "reader declines outside its business" begin
            iomap = _sequencechart_iomap(_sc_chart())
            stage2 = _stage2_iomap(iomap)
            # A click on the background is not a selection of anything.
            @test read_intent(stage2.projection, stage2,
                              MousePress(:left, 2, 2, _sc_no_modifier)) === nothing
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

        @testset "the overlay marks what is selected and hovered" begin
            chart = _sc_chart()
            iomap = _sequencechart_iomap(chart)
            plot = _plot_of(iomap)
            before = length(_sc_flatten(_sequencechart_canvas(_sc_chart())))

            # A selected occurrence gets a ring rather than a recolour: the
            # mark's own colour carries its kind, and overwriting it would cost
            # the reader the thing they selected it to see.
            plot.selection = sequence_chart_reference(plot, event_reference(chart, 2))
            with_selection = _sc_flatten(iomap.output)
            rings = [e for e in with_selection
                     if e isa GraphicsCircle && Int(e.border_width) > 0]
            @test length(rings) == 1
            @test Int(rings[1].radius) > chart.style.event_radius

            # Hovering an arrow re-strokes it thicker.
            plot.selection = nothing
            plot.hovered = sequence_chart_reference(plot, arrow_reference(chart, 1))
            hovered = _sc_flatten(iomap.output)
            @test any(e -> e isa GraphicsPolyline && Int(e.width) == 3, hovered)
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

            chart.selection = event_reference(chart, 2)
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
            @test event_count(big.events) == 20_000

            # At most one mark per lane, per kind, per mark-radius of the
            # flow axis — the bound the decimation promises.
            @test length(g.visible_events) <=
                  8 * (g.body_w ÷ big.style.event_radius + 2)
            @test length(g.visible_events) < event_count(big.events) ÷ 4

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
            i0, i1 = visible_event_range(zoomed.coordinates, zoomed.lo, zoomed.hi)
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
            plot.hovered = event_reference(big, 5)
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
            SCT.event_hit(g, plot, x, y)          # warm up
            elapsed = @elapsed for _ in 1:200
                SCT.event_hit(g, plot, x, y)
                SCT.arrow_hit(g, plot, x, y)
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
            parts = sequence_chart_parts(chart)
            # Title, three lanes, the two tables.
            @test length(parts) == 6
            for (index, part) in enumerate(parts)
                @test sequence_chart_part_index(chart, part) == index
            end
            @test sequence_chart_part_index(chart, nothing) == 0

            # Parts follow the display order, not the listed one.
            chart.axis_order = [3, 1, 2]
            reordered = sequence_chart_parts(chart)
            @test reordered[2] == axis_reference(chart, 3)
        end

        @testset "row references evaluate to the row" begin
            chart = _sc_chart()
            @test evaluate_reference(chart, event_reference(chart, 2)) ==
                  (1.0, 2, 0, "recv")
            @test evaluate_reference(chart, arrow_reference(chart, 1)) ==
                  (1, 2, 0, "req")
            # Out of range is nothing, not an error: a reference can outlive the
            # rows it named.
            @test evaluate_reference(chart, event_reference(chart, 99)) === nothing
        end

        @testset "arrow keys walk the parts" begin
            chart = _sc_chart()
            chart.selection = nothing
            op = read_gesture(chart, KeyDown(:right, _sc_no_modifier))
            @test op isa ReplaceSelectionOperation
            _sc_apply(chart, op)
            @test sequence_chart_part_index(chart, chart.selection) == 1

            for expected in 2:6
                _sc_apply(chart, read_gesture(chart, KeyDown(:down, _sc_no_modifier)))
                @test sequence_chart_part_index(chart, chart.selection) == expected
            end
            # At the end there is nowhere to go, so the gesture is declined
            # rather than consumed.
            @test read_gesture(chart, KeyDown(:down, _sc_no_modifier)) === nothing
        end

        @testset "arrow keys walk the trace once an event is selected" begin
            chart = _sc_chart()
            chart.selection = event_reference(chart, 3)
            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_no_modifier)))
            @test selected_event(chart) == 4
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, _sc_no_modifier)))
            @test selected_event(chart) == 3
        end

        @testset "shift walks one lane" begin
            # Events 1 and 6 are the client's; everything between is not.
            chart = _sc_chart()
            chart.selection = event_reference(chart, 1)
            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_shift)))
            @test selected_event(chart) == 6
            @test read_gesture(chart, KeyDown(:right, _sc_shift)) === nothing
        end

        @testset "ctrl follows causality" begin
            # This is the move that makes a sequence chart a graph: not "what is
            # next to this" but "what caused it".
            chart = _sc_chart()
            chart.selection = event_reference(chart, 4)
            _sc_apply(chart, read_gesture(chart, KeyDown(:left, _sc_ctrl)))
            @test selected_event(chart) == 3       # arrow 3 runs 3 → 4

            _sc_apply(chart, read_gesture(chart, KeyDown(:right, _sc_ctrl)))
            @test selected_event(chart) == 4

            # An occurrence nothing caused declines rather than jumping.
            chart.selection = event_reference(chart, 1)
            @test read_gesture(chart, KeyDown(:left, _sc_ctrl)) === nothing
        end

        @testset "lanes reorder" begin
            chart = _sc_chart()
            chart.selection = axis_reference(chart, 1)
            op = read_gesture(chart, KeyDown(:down, ModifierKeys(; ctrl=true, shift=true)))
            @test op !== nothing
            _sc_apply(chart, op)
            @test axis_display_order(chart) == [2, 1, 3]
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
            @test event_count(chart.events) == 4
            n = event_count(chart.events)
            @test all(1 <= Int(s) <= n && 1 <= Int(t) <= n
                      for (s, t) in zip(chart.arrows.sources, chart.arrows.targets))
        end

        @testset "inserting events remaps arrow endpoints" begin
            chart = _sc_chart()
            before = collect(chart.arrows.targets)
            _sc_apply(chart, insert_events(chart, 1, [-1.0], [1]))
            @test event_count(chart.events) == 7
            # Every arrow still points at the occurrence it always did, one row
            # further along.
            @test collect(chart.arrows.targets) == before .+ 1
            @test collect(chart.arrows.sources) == [2, 3, 4, 6]
        end
    end
end
