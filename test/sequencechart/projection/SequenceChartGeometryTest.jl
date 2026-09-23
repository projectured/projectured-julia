# Unit tests for the sequence chart slice's arithmetic. Everything here is a
# pure function over numbers and vectors, so these run headless and fast — no
# documents, no projection, no backend.
#
# The load-bearing properties are about the timeline mapping, because everything
# downstream is measured in the coordinate it produces:
#
# - every mode is monotone, so an event that happened later never draws earlier;
# - a zero-length gap still gets room under :nonlinear, which is what makes a
#   burst of same-time events readable at all;
# - rows sharing an ordinal share a coordinate, which is what lets one
#   occurrence appear on several lanes without occupying several slots;
# - a window survives a mode switch, including the degenerate case where the
#   whole window sits inside one zero-time region — the case a time-denominated
#   window could not express, and the reason the view is anchored to an event.

using Test

const SCG = SequenceChartModule

# A trace with the two shapes that make sequence charts hard: a burst of events
# sharing one instant, and a long quiet gap afterwards.
_seq_times() = [0.0, 1.0, 1.0, 1.0, 1.0e6]
_seq_axes() = [1, 2, 2, 3, 1]

"""
    test_sequencechart_geometry()

The timeline mapping, coordinate conversions, tick selection, lane placement,
arrow routing and decimation.
"""
function test_sequencechart_geometry()
    @testset "sequencechart geometry" begin
        @testset "flow frame" begin
            h = SCG.FlowFrame(:horizontal, 10, 20, 300, 100)
            @test SCG.flow_point(h, 50, 60) == (50.0, 60.0)
            @test SCG.frame_flow_span(h) == (10.0, 310.0)
            @test SCG.frame_cross_span(h) == (20.0, 120.0)
            @test SCG.flow_rect(h, 50, 60, 30, 8) == (50.0, 60.0, 30.0, 8.0)

            # Vertical is the same geometry with flow and cross swapped — which
            # is the whole of the orientation feature.
            v = SCG.FlowFrame(:vertical, 10, 20, 300, 100)
            @test SCG.flow_point(v, 50, 60) == (60.0, 50.0)
            @test SCG.frame_flow_span(v) == (20.0, 120.0)
            @test SCG.frame_cross_span(v) == (10.0, 310.0)
            @test SCG.flow_rect(v, 50, 60, 30, 8) == (60.0, 50.0, 8.0, 30.0)
        end

        @testset "timeline modes" begin
            times = _seq_times()

            # :time is the elapsed time itself, origin at the first event.
            @test SCG.get_timeline_coordinates(times, nothing, :time) == [0.0, 1.0, 1.0, 1.0, 1.0e6]

            # :step gives every event equal room; :ordinal agrees when the
            # ordinals are just the row numbers.
            @test SCG.get_timeline_coordinates(times, nothing, :step) == [0.0, 1.0, 2.0, 3.0, 4.0]
            @test SCG.get_timeline_coordinates(times, nothing, :ordinal) == [0.0, 1.0, 2.0, 3.0, 4.0]

            # An upstream filter keeps the original numbers, so :ordinal shows a
            # hole where events were hidden and :step closes it up. This is the
            # documented difference between the two modes.
            ordinals = [1, 2, 3, 4, 100]
            @test SCG.get_timeline_coordinates(times, ordinals, :ordinal) == [0.0, 1.0, 2.0, 3.0, 99.0]
            @test SCG.get_timeline_coordinates(times, ordinals, :step) == [0.0, 1.0, 2.0, 3.0, 4.0]

            # :nonlinear — a zero-length gap still gets the minimum share, and a
            # huge one saturates just under a full unit. Both stay visible,
            # which is the entire point of the mode.
            c = SCG.get_timeline_coordinates(times, nothing, :nonlinear; minimum=0.1)
            @test c[3] - c[2] ≈ 0.1
            @test c[4] - c[3] ≈ 0.1
            @test 0.9 < c[5] - c[4] <= 1.0
            @test c[2] - c[1] > 0.1

            # Monotone in every mode: later never draws earlier.
            for mode in (:time, :ordinal, :step, :nonlinear)
                coordinates = SCG.get_timeline_coordinates(times, nothing, mode)
                @test issorted(coordinates)
            end

            # Longer gap, more room — the ordering of gap lengths survives the
            # compression even though their ratio does not.
            spread = SCG.get_timeline_coordinates([0.0, 1.0, 3.0, 100.0], nothing, :nonlinear)
            @test (spread[3] - spread[2]) > (spread[2] - spread[1])
            @test (spread[4] - spread[3]) > (spread[3] - spread[2])

            @test isempty(SCG.get_timeline_coordinates(Float64[], nothing, :nonlinear))
            @test SCG.get_timeline_coordinates([5.0], nothing, :nonlinear) == [0.0]
        end

        @testset "shared ordinals share a coordinate" begin
            # One occurrence on three lanes: three rows, one ordinal, one slot.
            times = [0.0, 0.0, 0.0, 1.0]
            ordinals = [1, 1, 1, 2]
            for mode in (:ordinal, :step, :nonlinear)
                c = SCG.get_timeline_coordinates(times, ordinals, mode)
                @test c[1] == c[2] == c[3]
                @test c[4] > c[3]
            end
        end

        @testset "time and coordinate conversion" begin
            times = _seq_times()
            coordinates = SCG.get_timeline_coordinates(times, nothing, :nonlinear)

            @test SCG.time_to_coordinate(times, coordinates, 0.0) ≈ coordinates[1]
            @test SCG.time_to_coordinate(times, coordinates, 1.0e6) ≈ coordinates[5]

            # A time several events share names a *range*, and `upper` picks
            # which edge of it is meant.
            @test SCG.time_to_coordinate(times, coordinates, 1.0; upper=false) ≈ coordinates[2]
            @test SCG.time_to_coordinate(times, coordinates, 1.0; upper=true) ≈ coordinates[4]

            # Outside the trace clamps rather than extrapolating.
            @test SCG.time_to_coordinate(times, coordinates, -100.0) ≈ coordinates[1]
            @test SCG.time_to_coordinate(times, coordinates, 1.0e9) ≈ coordinates[5]

            # Round trip through the inverse, away from the ambiguous region.
            mid = (coordinates[4] + coordinates[5]) / 2
            t = SCG.convert_coordinate_to_time(times, coordinates, mid)
            @test SCG.time_to_coordinate(times, coordinates, t) ≈ mid rtol=1e-9

            # Every coordinate inside a zero-time region reports that one time —
            # the honest answer, and why a window is not stored as a time pair.
            inside = (coordinates[2] + coordinates[4]) / 2
            @test SCG.convert_coordinate_to_time(times, coordinates, inside) ≈ 1.0
        end

        @testset "window survives a mode switch" begin
            times = _seq_times()
            from = SCG.get_timeline_coordinates(times, nothing, :nonlinear)
            to = SCG.get_timeline_coordinates(times, nothing, :step)

            # A window over the quiet gap carries across by its endpoints' times.
            lo, hi = from[4], from[5]
            t_lo = SCG.convert_coordinate_to_time(times, from, lo)
            t_hi = SCG.convert_coordinate_to_time(times, from, hi)
            @test SCG.time_to_coordinate(times, to, t_lo; upper=true) ≈ to[4]
            @test SCG.time_to_coordinate(times, to, t_hi) ≈ to[5]

            # The degenerate case: a window strictly inside a zero-time region.
            # Both ends are the same instant, so a time pair cannot tell them
            # apart — carrying the window means falling back to the region's own
            # coordinate span, which is what the anchored view does.
            inner_lo, inner_hi = from[2], from[4]
            @test SCG.convert_coordinate_to_time(times, from, inner_lo) ==
                  SCG.convert_coordinate_to_time(times, from, inner_hi)
            @test to[4] > to[2]      # the region still has width in the new mode
        end

        @testset "visible ranges" begin
            coordinates = [0.0, 1.0, 2.0, 3.0, 4.0]
            @test SCG.get_visible_event_range(coordinates, 1.5, 2.5) == (2, 4)
            @test SCG.get_visible_event_range(coordinates, -10.0, 10.0) == (1, 5)
            @test SCG.get_visible_event_range(Float64[], 0.0, 1.0) == (1, 0)

            # An arrow crossing the window with *both* ends outside it is still
            # visible — it is the connection the reader is looking at. Selecting
            # by endpoint membership would erase exactly those.
            sources = [1, 1, 5]
            targets = [2, 5, 5]
            visible = SCG.get_visible_arrows(coordinates, sources, targets; lo=1.8, hi=2.2)
            @test 2 in visible          # spans the window, neither end inside
            @test !(1 in visible)       # entirely left of it
            @test !(3 in visible)       # entirely right of it

            # The horizon widens candidacy: an arrow just outside still counts,
            # because a split arrow's stub has to be drawn from somewhere.
            @test 1 in SCG.get_visible_arrows(coordinates, sources, targets; lo=1.8, hi=2.2, horizon=1.0)

            # Out-of-range endpoints are dropped rather than throwing: a
            # half-written table renders what it can.
            @test isempty(SCG.get_visible_arrows(coordinates, [99], [1]; lo=0.0, hi=4.0))
        end

        @testset "ticks" begin
            times = _seq_times()
            coordinates = SCG.get_timeline_coordinates(times, nothing, :nonlinear)
            scale = SCG.AxisScale(coordinates[1], coordinates[end], 0.0, 600.0)

            ticks = SCG.flow_ticks(times, coordinates; scale, mode = :nonlinear, target_px=100)
            @test length(ticks) >= 2
            @test issorted([c for (c, _) in ticks])
            @test all(scale.lo - 1e-9 <= c <= scale.hi + 1e-9 for (c, _) in ticks)

            # In :time mode the ticks are round numbers instead of round pixels.
            linear = SCG.get_timeline_coordinates(times, nothing, :time)
            lscale = SCG.AxisScale(linear[1], linear[end], 0.0, 600.0)
            time_ticks = SCG.flow_ticks(times, linear; scale = lscale, mode = :time,
                                        target_px=100)
            @test length(time_ticks) >= 2

            @test isempty(SCG.flow_ticks(Float64[], Float64[]; scale, mode = :time))
        end

        @testset "honest tick labels" begin
            # A pixel stands for a span of time; printing more digits than that
            # span justifies is noise dressed as precision.
            @test SCG.get_honest_tick_label(1.23456, 0.5) == "1"
            @test SCG.get_honest_tick_label(1.23456, 0.005) == "1.23"

            # Zooming in earns digits, and only as many as it earns.
            coarse = SCG.get_honest_tick_label(1.2345678, 0.1)
            fine = SCG.get_honest_tick_label(1.2345678, 0.00001)
            @test length(fine) > length(coarse)

            # Whatever it prints must be inside the neighbourhood it was given.
            for neighbourhood in (1.0, 0.1, 0.001, 1e-6)
                label = SCG.get_honest_tick_label(1.2345678, neighbourhood)
                value = parse(Float64, label)
                @test abs(value - 1.2345678) <= neighbourhood * 1.0000001
            end
        end

        @testset "tick prefix" begin
            prefix, suffixes = SCG.tick_common_prefix(["1.024001", "1.024002", "1.024003"])
            @test prefix == "1.02400"
            @test suffixes == ["1", "2", "3"]
            # Reassembling has to give the labels back unchanged.
            @test prefix .* suffixes == ["1.024001", "1.024002", "1.024003"]

            # Nothing worth factoring out: leave the labels alone rather than
            # splitting off a character.
            @test SCG.tick_common_prefix(["1", "2", "3"]) == ("", ["1", "2", "3"])
            @test SCG.tick_common_prefix(["7.5"]) == ("", ["7.5"])
        end

        @testset "zero time spans" begin
            times = _seq_times()
            coordinates = SCG.get_timeline_coordinates(times, nothing, :nonlinear)
            spans = SCG.get_zero_time_spans(times, coordinates, -1.0, 100.0)
            @test length(spans) == 1
            c0, c1 = spans[1]
            @test c0 ≈ coordinates[2] && c1 ≈ coordinates[4]

            # Under :time the same events have no width, so there is nothing to
            # shade — the shading exists to explain the other mappings.
            linear = SCG.get_timeline_coordinates(times, nothing, :time)
            @test isempty(SCG.get_zero_time_spans(times, linear, -1.0, 1e9))

            # Clipped to the window it was asked about.
            clipped = SCG.get_zero_time_spans(times, coordinates, coordinates[3], 100.0)
            @test clipped[1][1] ≈ coordinates[3]
        end

        @testset "lane placement" begin
            positions = SCG.get_axis_cross_positions(4, nothing, 0.0, 400.0)
            @test length(positions) == 4
            @test issorted(positions)
            @test all(0.0 <= p <= 400.0 for p in positions)

            # Lanes divide the room between them, so a chart of any lane count
            # fills its pane.
            wide = SCG.get_axis_cross_positions(4, nothing, 0.0, 800.0)
            @test (wide[2] - wide[1]) > (positions[2] - positions[1])

            # A pinned spacing overrides that.
            pinned = SCG.get_axis_cross_positions(4, nothing, 0.0, 800.0; spacing=30.0)
            @test pinned[2] - pinned[1] ≈ 30.0

            # A band widens its own lane's slot.
            banded = SCG.get_axis_cross_positions(3, [0.0, 20.0, 0.0], 0.0, 400.0)
            @test banded[2] - banded[1] > banded[3] - banded[2]

            @test isempty(SCG.get_axis_cross_positions(0, nothing, 0.0, 100.0))
        end

        @testset "arrow routing" begin
            @test SCG.get_arrow_route(:auto, true) === :arc
            @test SCG.get_arrow_route(:auto, false) === :direct
            @test SCG.get_arrow_route(:direct, true) === :direct
            @test SCG.get_arrow_route(:arc, false) === :arc

            # An arc starts and ends on the lane and bulges to one side, where
            # there is room — the lane itself is full of events.
            points = SCG.get_arc_geometry(100.0, 200.0, 50.0, 15.0)
            @test length(points) == 4
            @test points[1] == (100.0, 50.0)
            @test points[4] == (200.0, 50.0)
            @test all(p[2] < 50.0 for p in points[2:3])

            # Neighbouring arcs get different heights so they separate instead
            # of tracing one smear — deterministic, so repaints are stable.
            heights = [SCG.arc_height(d, 40.0) for d in 1:8]
            @test length(unique(heights)) > 1
            @test SCG.arc_height(1, 40.0) == SCG.arc_height(5, 40.0)
            @test all(h >= 15.0 for h in heights)
        end

        @testset "split arrows" begin
            # Short enough to draw whole.
            @test SCG.split_arrow(0.0, 50.0, 100.0, 20.0) === nothing

            # Too long: each end keeps a stub pointing the way it went.
            split = SCG.split_arrow(0.0, 500.0, 100.0, 20.0)
            @test split !== nothing
            near, far = split
            @test near == (0.0, 20.0)
            @test far == (500.0, 480.0)

            # Backwards arrows split the same way, mirrored.
            back = SCG.split_arrow(500.0, 0.0, 100.0, 20.0)
            @test back == ((500.0, 480.0), (0.0, 20.0))
        end

        @testset "event decimation" begin
            # A thousand events on two lanes, drawn across 200 pixels: what
            # survives is bounded by the pixels, not by the events.
            n = 1000
            coordinates = collect(range(0.0, 100.0; length=n))
            axes = [1 + (i % 2) for i in 1:n]
            scale = SCG.AxisScale(0.0, 100.0, 0.0, 200.0)
            kept = SCG.decimate_events(coordinates, axes; scale, i0=1, i1=n)
            @test length(kept) <= 2 * 201
            @test length(kept) < n
            @test issorted(kept)

            # A mark is a disc, so where events are packed closer than it is
            # wide, drawing every one of them paints the same ground twice.
            # Separating by the mark's radius keeps the run unbroken and cuts
            # the count by the width of a mark.
            sparse = SCG.decimate_events(coordinates, axes; scale, i0=1, i1=n, separation=3)
            @test length(sparse) < length(kept)
            @test length(sparse) <= 2 * (201 ÷ 3 + 2)

            # But a different kind is never collapsed away: a crowded stretch
            # must still show that something unusual happened in it.
            kinds = [i == 500 ? 2 : 1 for i in 1:n]
            with_kinds = SCG.decimate_events(coordinates, axes; scale, i0=1, i1=n,
                                             kinds=kinds, separation=3)
            @test 500 in with_kinds

            # Zoomed in far enough that no two events share a pixel, everything
            # survives — decimation is exact, not sampling.
            fine = SCG.AxisScale(0.0, 1.0, 0.0, 4000.0)
            all_kept = SCG.decimate_events(coordinates, axes; scale=fine, i0=1, i1=10)
            @test length(all_kept) == 10

            @test isempty(SCG.decimate_events(coordinates, axes; scale, i0=5, i1=4))
        end

        @testset "arrow coverage dedup" begin
            # A bundle of arrows collapsing onto one pixel column between the
            # same two lanes: one of them paints everything the rest would.
            candidates = collect(1:100)
            flows = [(50.0, 50.0) for _ in 1:100]
            crosses = [(20.0, 80.0) for _ in 1:100]
            @test length(SCG.deduplicate_arrow_coverage(candidates, flows, crosses)) == 1

            # Different cross intervals are different marks, so they all stay.
            spread_crosses = [(20.0 + 5k, 80.0 + 5k) for k in 1:20]
            @test length(SCG.deduplicate_arrow_coverage(collect(1:20),
                [(50.0, 50.0) for _ in 1:20], spread_crosses)) == 20

            # An arrow with real width is a shape in its own right and is never
            # dropped into a bundle.
            wide = SCG.deduplicate_arrow_coverage([1, 2], [(0.0, 300.0), (0.0, 300.0)],
                                            [(20.0, 80.0), (20.0, 80.0)])
            @test length(wide) == 2
        end

        @testset "band intervals" begin
            coordinates = [0.0, 1.0, 2.0, 3.0, 4.0]
            times = [0.0, 1.0, 2.0, 3.0, 4.0]

            # Sample-and-hold: a value paints from its own moment to the next.
            intervals = SCG.get_band_intervals([0.0, 2.0], [1.0, 2.0]; events=nothing,
                                           event_times=times, coordinates, lo=-10.0, hi=10.0)
            @test length(intervals) == 2
            @test intervals[1][1] ≈ 0.0 && intervals[1][2] ≈ 2.0
            @test intervals[1][3] == 1.0
            @test intervals[2][2] ≈ 4.0      # the last value holds to the end

            # A band time becomes a coordinate through the *event* timeline: the
            # band's own samples say nothing about where the axis is stretched.
            stretched = SCG.get_timeline_coordinates(times, nothing, :step)
            through = SCG.get_band_intervals([2.0], [1.0]; events=nothing, event_times=times,
                                         coordinates=stretched, lo=-10.0, hi=10.0)
            @test through[1][1] ≈ stretched[3]

            # Anchoring to an event row places an edge exactly, which a bare
            # time cannot do when several events share one instant.
            burst_times = [0.0, 5.0, 5.0, 5.0, 9.0]
            burst = SCG.get_timeline_coordinates(burst_times, nothing, :nonlinear)
            anchored = SCG.get_band_intervals([5.0], [1.0]; events=[4], event_times=burst_times,
                                          coordinates=burst, lo=-10.0, hi=10.0)
            @test anchored[1][1] ≈ burst[4]
            loose = SCG.get_band_intervals([5.0], [1.0]; events=nothing, event_times=burst_times,
                                        coordinates=burst, lo=-10.0, hi=10.0)
            @test loose[1][1] ≈ burst[2]     # the region's near edge, not row 4

            # Clipped to the window it was asked about.
            @test isempty(SCG.get_band_intervals([0.0], [1.0]; events=nothing, event_times=times,
                                             coordinates, lo=90.0, hi=100.0))
        end
    end
end
