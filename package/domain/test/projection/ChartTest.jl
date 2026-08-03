# The chart pipeline: Chart → ChartPlot → GraphicsCanvas.
#
# These drive the real projections and assert on the canvas that comes out —
# what kinds of primitive appear, where the plot rectangle lands, that a data
# change repaints, and that a selection round-trips through both stages.
#
# The scale checks are the ones with teeth: element count has to stay bounded by
# the plot rectangle no matter how long the columns are, or the "scalable" claim
# is not true.

using Test

# A chart pipeline measuring text without a backend, so these run headless.
function _chart_projection(; width::Integer=760, height::Integer=460)
    ChainingProjection(
        ChartToChartPlot(),
        ChartPlotToGraphicsCanvas(measure=truetype_measure_text,
                                  width=width, height=height))
end

_chart_canvas(chart; kw...) = print_document(_chart_projection(; kw...),
                                             _chart_projection(; kw...),
                                             chart, PrinterContext()).output

# Every element of a canvas, descending into viewports and nested canvases —
# what actually reaches a backend.
function _flatten_elements(doc)
    out = Any[]
    _flatten_elements!(out, doc)
    out
end
function _flatten_elements!(out, doc)
    if doc isa GraphicsCanvas
        for e in doc.elements
            push!(out, e)
            _flatten_elements!(out, e)
        end
    elseif doc isa GraphicsViewport
        _flatten_elements!(out, doc.content)
    end
    out
end

_count_kind(els, T) = count(e -> e isa T, els)
_viewport_of(canvas) = first(e for e in canvas.elements if e isa GraphicsViewport)
_series_elements(canvas) = collect(_viewport_of(canvas).content.elements)

_line_chart() = Chart("Signal",
    [ChartLineSeries("sin", collect(0.0:0.05:10.0), sin.(0.0:0.05:10.0)),
     ChartLineSeries("cos", collect(0.0:0.05:10.0), cos.(0.0:0.05:10.0); line_width=2)];
    x_axis=ChartAxis(; title="time (s)"), y_axis=ChartAxis(; title="value"))

"""
    test_chart()

The chart projection: frame composition, series geometry, reactivity and
selection round-trips.
"""
function test_chart()
    @testset "chart" begin
        @testset "line chart frame" begin
            canvas = _chart_canvas(_line_chart())
            @test canvas isa GraphicsCanvas
            @test Int(canvas.w) == 760 && Int(canvas.h) == 460

            els = collect(canvas.elements)
            # Chart background and plot background.
            @test _count_kind(els, GraphicsRect) >= 2
            # Two axis lines, plus gridlines and tick marks.
            @test _count_kind(els, GraphicsLine) > 4
            # Tick labels plus the title and the two axis titles.
            texts = [e for e in els if e isa GraphicsText]
            labels = [String(t.text) for t in texts]
            @test "Signal" in labels
            @test "time (s)" in labels
            @test "value" in labels
            @test any(l -> l == "0", labels)

            vp = _viewport_of(canvas)
            # The plot rectangle sits inside the canvas with room for the labels.
            @test Int(vp.x) > 0 && Int(vp.y) > 0
            @test Int(vp.x) + Int(vp.w) <= Int(canvas.w)
            @test Int(vp.y) + Int(vp.h) <= Int(canvas.h)
            @test Int(vp.w) > 100 && Int(vp.h) > 100
        end

        @testset "series geometry" begin
            canvas = _chart_canvas(_line_chart())
            series = _series_elements(canvas)
            polylines = [e for e in series if e isa GraphicsPolyline]
            @test length(polylines) == 2
            # The cycle hands out distinct colors to series that set none.
            @test polylines[1].color != polylines[2].color
            @test Int(polylines[2].width) == 2
            # Series geometry is in the viewport's local frame, so it starts at 0.
            vp = _viewport_of(canvas)
            for pl in polylines
                xs = [p[1] for p in pl.points]
                @test minimum(xs) >= -1
                @test maximum(xs) <= Int(vp.w) + 1
            end
        end

        @testset "draw styles" begin
            x = collect(0.0:1.0:10.0)
            y = collect(0.0:1.0:10.0)
            for style in (:linear, :steps_post, :steps_pre, :steps_mid)
                c = Chart("s", [ChartLineSeries("a", x, y; draw_style=style)])
                pls = [e for e in _series_elements(_chart_canvas(c)) if e isa GraphicsPolyline]
                @test length(pls) == 1
                # A staircase needs more vertices than the samples it came from.
                style === :linear ? (@test length(pls[1].points) == 11) :
                                    (@test length(pls[1].points) > 11)
            end
            # Pins draw one stem per point instead of a connected line.
            c = Chart("s", [ChartLineSeries("a", x, y; draw_style=:pins)])
            els = _series_elements(_chart_canvas(c))
            @test isempty([e for e in els if e isa GraphicsPolyline])
            @test _count_kind(els, GraphicsLine) == 11
            # :none suppresses the line, leaving only whatever markers are asked for.
            c = Chart("s", [ChartLineSeries("a", x, y; draw_style=:none, symbol=:circle)])
            els = _series_elements(_chart_canvas(c))
            @test isempty([e for e in els if e isa GraphicsPolyline])
            @test _count_kind(els, GraphicsCircle) == 11
        end

        @testset "markers" begin
            x = collect(0.0:1.0:9.0)
            for (shape, T, n) in ((:circle, GraphicsCircle, 10), (:dot, GraphicsCircle, 10),
                                  (:square, GraphicsRect, 10), (:plus, GraphicsLine, 20),
                                  (:cross, GraphicsLine, 20), (:hline, GraphicsLine, 10),
                                  (:vline, GraphicsLine, 10))
                c = Chart("s", [ChartLineSeries("a", x, x; draw_style=:none, symbol=shape)])
                @test _count_kind(_series_elements(_chart_canvas(c)), T) == n
            end
            # Past the marker limit the individual points stop being distinct, so
            # they are dropped rather than smeared into a solid band.
            big = collect(1.0:1.0:500.0)
            c = Chart("s", [ChartLineSeries("a", big, big; symbol=:circle)])
            @test _count_kind(_series_elements(_chart_canvas(c)), GraphicsCircle) == 0
        end

        @testset "axis configuration" begin
            x = collect(1.0:1.0:100.0)
            # A pinned axis end overrides the fit; the other end still fits. The
            # y ticks stop at the pin even though the data runs to 100.
            c = Chart("s", [ChartLineSeries("a", x, x)]; y_axis=ChartAxis(; min=0.0, max=50.0))
            canvas = _chart_canvas(c)
            vp = _viewport_of(canvas)
            ylabels = [String(e.text) for e in collect(canvas.elements)
                       if e isa GraphicsText && Int(e.x) < Int(vp.x)]
            @test "50" in ylabels
            @test !("100" in ylabels)

            # Hidden labels remove the tick text but keep the frame. (The chart
            # title is not a tick label, so this chart is deliberately untitled.)
            c = Chart("", [ChartLineSeries("a", x, x)];
                      x_axis=ChartAxis(; show_labels=false),
                      y_axis=ChartAxis(; show_labels=false))
            els = collect(_chart_canvas(c).elements)
            @test isempty([e for e in els if e isa GraphicsText])
            @test _count_kind(els, GraphicsLine) >= 2

            # Grid modes.
            base = length([e for e in collect(_chart_canvas(
                Chart("s", [ChartLineSeries("a", x, x)];
                      x_axis=ChartAxis(; grid=:none), y_axis=ChartAxis(; grid=:none))
                ).elements) if e isa GraphicsLine])
            gridded = length([e for e in collect(_chart_canvas(
                Chart("s", [ChartLineSeries("a", x, x)])).elements) if e isa GraphicsLine])
            @test gridded > base

            # A log axis puts the ticks on decades.
            c = Chart("s", [ChartLineSeries("a", x, x)]; y_axis=ChartAxis(; log=true))
            labels = [String(e.text) for e in collect(_chart_canvas(c).elements) if e isa GraphicsText]
            @test any(l -> l in ("10", "100"), labels)
        end

        @testset "visibility" begin
            c = _line_chart()
            @test length([e for e in _series_elements(_chart_canvas(c)) if e isa GraphicsPolyline]) == 2
            c.series[1].visible = false
            @test length([e for e in _series_elements(_chart_canvas(c)) if e isa GraphicsPolyline]) == 1
            # Hiding a series must not recolor the ones after it: the cycle is
            # keyed on position in the list, not on how many are showing.
            full = _line_chart()
            second_color = [e for e in _series_elements(_chart_canvas(full)) if e isa GraphicsPolyline][2].color
            @test [e for e in _series_elements(_chart_canvas(c)) if e isa GraphicsPolyline][1].color == second_color
        end

        @testset "reactivity" begin
            x = collect(0.0:0.5:10.0)
            s = ChartLineSeries("a", x, sin.(x))
            chart = Chart("live", [s])
            canvas = _chart_canvas(chart)
            pl = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline)
            before = copy(pl.points)

            # Replacing a whole column is the granularity: one cell write, and
            # the geometry re-derives without the projection being re-run.
            s.y = cos.(x)
            after = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline).points
            @test after != before

            # A style change repaints too.
            s.line_width = 5
            @test Int(first(e for e in _series_elements(canvas) if e isa GraphicsPolyline).width) == 5

            # And so does a title edit, without disturbing the canvas identity.
            chart.title = "renamed"
            labels = [String(e.text) for e in collect(canvas.elements) if e isa GraphicsText]
            @test "renamed" in labels
        end

        @testset "view window" begin
            x = collect(0.0:0.01:100.0)
            chart = Chart("z", [ChartLineSeries("a", x, sin.(x))])
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            canvas = iomap.output

            wide = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline)
            wide_n = length(wide.points)

            # Zooming in re-derives the geometry from the narrower window: the
            # same pixels now show a hundredth of the data, so the decimated
            # polyline covers a fraction of the samples.
            plot.view = ChartView(0.0, 1.0, -1.0, 1.0)
            zoomed = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline)
            @test length(zoomed.points) != wide_n
            # Zoomed that far in, every sample in the window survives untouched.
            @test length(zoomed.points) <= 110

            # And the ticks follow the window rather than the data.
            labels = [String(e.text) for e in collect(canvas.elements) if e isa GraphicsText]
            @test !("100" in labels)
        end

        @testset "selection round-trip" begin
            chart = _line_chart()
            proj = ChartToChartPlot()
            iomap = print_document(proj, proj, chart, PrinterContext())

            # Every node of a reference names the type it reaches, terminal
            # included — that is the invariant @reference enforces.
            for reference in (EmptyReference(),
                              (@reference ::Chart.title::String),
                              (@reference ::Chart.series::CellVector[1]::ChartLineSeries.label::String),
                              (@reference ::Chart.x_axis::ChartAxis.title::String),
                              (@reference ::Chart.style::ChartStyle.marker_limit::Int),
                              (@reference ::Chart.legend::ChartLegend.position::Symbol))
                forward = map_reference_forward(proj, iomap, reference)
                @test forward !== nothing
                back = map_reference_backward(proj, iomap, forward)
                @test back !== nothing
                @test is_reference_equal(strip_reference_types(back),
                                         strip_reference_types(reference))
            end
        end

        @testset "empty chart" begin
            # A placeholder root still draws as a chart-shaped surface rather
            # than collapsing to nothing.
            canvas = _chart_canvas(ChartNothing())
            @test canvas isa GraphicsCanvas
            els = collect(canvas.elements)
            @test _count_kind(els, GraphicsRect) >= 2
            # A chart with no series at all is legal and still draws its frame.
            canvas = _chart_canvas(Chart("nothing yet"))
            @test "nothing yet" in [String(e.text) for e in collect(canvas.elements) if e isa GraphicsText]
        end

        @testset "family mismatch" begin
            # A bar series on a numeric axis is a configuration error, not a
            # crash: the chart draws its frame and leaves the series out.
            c = Chart("mixed", [ChartBarSeries("bars", [1.0, 2.0, 3.0])])
            canvas = _chart_canvas(c)
            @test canvas isa GraphicsCanvas
            @test isempty(_series_elements(canvas))
        end
    end
end

"""
    test_chart_scale()

The cost of a chart is bounded by its plot rectangle, not by its data. These
are the assertions behind the scalability claim.
"""
function test_chart_scale()
    @testset "chart scale" begin
        n = 1_000_000
        x = collect(range(0.0, 100.0; length=n))
        y = sin.(range(0.0, 400π; length=n))
        chart = Chart("big", [ChartLineSeries("a", x, y)])

        canvas = _chart_canvas(chart; width=760, height=460)
        els = _flatten_elements(canvas)
        @test length(els) < 200
        pl = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline)
        # At most four points per pixel column of the plot rectangle.
        @test length(pl.points) <= 4 * (Int(_viewport_of(canvas).w) + 2)
        @test length(pl.points) < n ÷ 100

        # A ten-times-longer column does not make a bigger picture.
        short = Chart("small", [ChartLineSeries("a", x[1:100_000], y[1:100_000])])
        short_pl = first(e for e in _series_elements(_chart_canvas(short)) if e isa GraphicsPolyline)
        @test abs(length(short_pl.points) - length(pl.points)) < length(pl.points)

        # Reprinting a million samples stays interactive.
        elapsed = @elapsed begin
            c2 = _chart_canvas(chart)
            length(_series_elements(c2))
        end
        @test elapsed < 5.0
    end
end
