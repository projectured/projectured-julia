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

# How high a chart's y axis has to reach to show what it draws — the cheapest
# way to see which histogram value transform is in effect.
_chart_y_max(chart) = resolve_view(ChartPlot(chart)).y_max

_chart_iomap(chart; kw...) = (p = _chart_projection(; kw...);
                              print_document(p, p, chart, PrinterContext()))

# The decimated pixel points of one series, as the renderer computes them.
_line_points_of(g, index) = ChartPlotToGraphicsModule._series_points(g, index, g.chart.series[index])

# A canvas point on the first series' geometry but more than a marker's reach
# from any of its samples, so a click there means "the series", not "a point".
function _series_hit_away_from_samples(g, pts)
    for k in 2:length(pts)
        x0, y0 = pts[k-1]; x1, y1 = pts[k]
        mx, my = (x0 + x1) ÷ 2, (y0 + y1) ÷ 2
        ChartPlotToGraphicsModule._sample_hit(g, mx + g.plot_x, my + g.plot_y) === nothing &&
            ChartPlotToGraphicsModule._series_hit(g, mx + g.plot_x, my + g.plot_y) !== nothing &&
            return (mx + g.plot_x, my + g.plot_y)
    end
    nothing
end

# Apply an operation against a chart that is not inside an editor: the chart is
# the root, so a document-rooted reference resolves against it directly.
function _apply_to(chart, op)
    editor = (; document = chart)
    evaluate_operation(editor, op)
end

const alt_modifier = ModifierKeys(; alt=true)
const move_modifier = ModifierKeys(; ctrl=true, shift=true)
const no_modifier = ModifierKeys()

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

            # Hidden labels remove the tick text but keep the frame. (The title
            # and the legend are not tick labels, so both are off here.)
            c = Chart("", [ChartLineSeries("a", x, x)];
                      x_axis=ChartAxis(; show_labels=false),
                      y_axis=ChartAxis(; show_labels=false),
                      legend=ChartLegend(; visible=false))
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

        @testset "bar placement" begin
            cats = ["a", "b", "c"]
            mk(placement) = Chart("bars",
                [ChartBarSeries("one", [3.0, 5.0, 1.0]),
                 ChartBarSeries("two", [2.0, 1.0, 4.0])];
                x_axis=ChartCategoryAxis(; categories=cats), bar_placement=placement)

            for placement in (:aligned, :overlap, :infront, :stacked)
                els = _series_elements(_chart_canvas(mk(placement)))
                rects = [e for e in els if e isa GraphicsRect]
                @test length(rects) == 6            # two series over three categories
                @test _count_kind(els, GraphicsLine) == 1   # the baseline
            end

            # Aligned bars share a slot side by side, so each is narrower than an
            # in-front bar, which takes the whole slot.
            aligned = [e for e in _series_elements(_chart_canvas(mk(:aligned))) if e isa GraphicsRect]
            infront = [e for e in _series_elements(_chart_canvas(mk(:infront))) if e isa GraphicsRect]
            @test Int(aligned[1].w) < Int(infront[1].w)

            # Stacking sums the series, so the axis has to reach the total.
            stacked_canvas = _chart_canvas(mk(:stacked))
            ylabels = [String(e.text) for e in collect(stacked_canvas.elements) if e isa GraphicsText]
            @test any(l -> tryparse(Float64, l) !== nothing && tryparse(Float64, l) >= 6.0, ylabels)

            # One label per category, and the categories are the labels.
            labels = [String(e.text) for e in collect(_chart_canvas(mk(:aligned)).elements)
                      if e isa GraphicsText]
            @test all(c -> c in labels, cats)
        end

        @testset "histogram" begin
            edges = collect(0.0:1.0:10.0)
            values = Float64[1, 3, 5, 8, 12, 10, 6, 4, 2, 1]
            solid = Chart("h", [ChartHistogramSeries("a", edges, values)])
            els = _series_elements(_chart_canvas(solid))
            @test _count_kind(els, GraphicsRect) == 10
            @test isempty([e for e in els if e isa GraphicsPolyline])

            # Outline mode draws a silhouette instead of filled cells, so several
            # overlaid histograms stay readable.
            outline = Chart("h", [ChartHistogramSeries("a", edges, values; draw=:outline)])
            els = _series_elements(_chart_canvas(outline))
            @test isempty([e for e in els if e isa GraphicsRect])
            @test length([e for e in els if e isa GraphicsPolyline]) == 1

            # The four value transforms.
            raw_top = _chart_y_max(Chart("h", [ChartHistogramSeries("a", edges, values)]))
            @test 12.0 <= raw_top <= 15.0                 # the tallest bin, plus margin
            cum = Chart("h", [ChartHistogramSeries("a", edges, values; cumulative=true)])
            @test _chart_y_max(cum) > 4 * raw_top         # a running sum reaches the total
            cdf = Chart("h", [ChartHistogramSeries("a", edges, values;
                                                   cumulative=true, density=true)])
            @test _chart_y_max(cdf) ≈ 1.0 atol=0.2        # a CDF reaches 1
            pdf = Chart("h", [ChartHistogramSeries("a", edges, values; density=true)])
            @test _chart_y_max(pdf) < 1.0                 # a density over unit-wide bins

            # Overflow cells appear only when asked for.
            without = length(_series_elements(_chart_canvas(
                Chart("h", [ChartHistogramSeries("a", edges, values; underflows=4.0, overflows=3.0)]))))
            with = length(_series_elements(_chart_canvas(
                Chart("h", [ChartHistogramSeries("a", edges, values;
                                                 underflows=4.0, overflows=3.0,
                                                 show_overflow=true)]))))
            @test with == without + 2

            # Binning a raw column.
            binned = ChartHistogramSeries("a", randn(5_000); nbins=25)
            @test length(binned.binedges) == 26 && length(binned.binvalues) == 25
            @test sum(binned.binvalues) == 5_000
        end

        @testset "scatter" begin
            n = 500
            c = Chart("s", [ChartScatterSeries("a", collect(1.0:n), collect(1.0:n))])
            els = _series_elements(_chart_canvas(c))
            @test _count_kind(els, GraphicsCircle) > 0
            # Markers are deduplicated per pixel, so overlapping samples do not
            # each cost an element.
            dup = Chart("s", [ChartScatterSeries("a", fill(1.0, n), fill(1.0, n))])
            @test _count_kind(_series_elements(_chart_canvas(dup)), GraphicsCircle) == 1

            # Marker shapes carry over from line series.
            c = Chart("s", [ChartScatterSeries("a", collect(1.0:10.0), collect(1.0:10.0);
                                               symbol=:square)])
            @test _count_kind(_series_elements(_chart_canvas(c)), GraphicsRect) == 10
        end

        @testset "line style" begin
            x = collect(0.0:1.0:10.0)
            mk(style) = Chart("s", [ChartLineSeries("a", x, x; line_style=style)])
            solid = first(e for e in _series_elements(_chart_canvas(mk(:solid)))
                          if e isa GraphicsPolyline)
            @test solid.dash === nothing
            for style in (:dotted, :dashed)
                pl = first(e for e in _series_elements(_chart_canvas(mk(style)))
                           if e isa GraphicsPolyline)
                @test pl.dash isa Tuple && pl.dash[1] > 0 && pl.dash[2] > 0
            end
            @test first(e for e in _series_elements(_chart_canvas(mk(:dotted)))
                        if e isa GraphicsPolyline).dash !=
                  first(e for e in _series_elements(_chart_canvas(mk(:dashed)))
                        if e isa GraphicsPolyline).dash
        end

        @testset "legend" begin
            c = _line_chart()
            canvas = _chart_canvas(c)
            labels = [String(e.text) for e in collect(canvas.elements) if e isa GraphicsText]
            @test "sin" in labels && "cos" in labels

            # Hiding the legend removes its items but nothing else.
            c.legend.visible = false
            labels = [String(e.text) for e in collect(_chart_canvas(c).elements) if e isa GraphicsText]
            @test !("sin" in labels)
            @test "Signal" in labels

            # An outside legend takes space from the plot; an inside one overlays.
            inside_w = Int(_viewport_of(_chart_canvas(_line_chart())).w)
            right = _line_chart(); right.legend.position = :right
            @test Int(_viewport_of(_chart_canvas(right)).w) < inside_w
            below = _line_chart(); below.legend.position = :below
            @test Int(_viewport_of(_chart_canvas(below)).h) <
                  Int(_viewport_of(_chart_canvas(_line_chart())).h)

            # Anchors move the box without resizing it.
            boxes = map((:northwest, :northeast, :southeast)) do anchor
                ch = _line_chart(); ch.legend.anchor = anchor
                plan = _chart_iomap(ch).step_iomaps[2][].geometry.legend
                (plan.x, plan.y, plan.box_w, plan.box_h)
            end
            @test allunique([(b[1], b[2]) for b in boxes])
            @test all(b -> (b[3], b[4]) == (boxes[1][3], boxes[1][4]), boxes)

            # Sorting reorders the items without touching the series list.
            sorted = _line_chart(); sorted.legend.sort = true
            plan = _chart_iomap(sorted).step_iomaps[2][].geometry.legend
            @test [it[2] for it in plan.items] == ["cos", "sin"]
            @test String(sorted.series[1].label) == "sin"

            # Everything that does not fit is accounted for rather than dropped.
            many = Chart("many",
                [ChartLineSeries("series number \$i", [0.0, 1.0], [0.0, 1.0]) for i in 1:60];
                legend=ChartLegend(; position=:right))
            labels = [String(e.text) for e in collect(_chart_canvas(many).elements)
                      if e isa GraphicsText]
            @test any(l -> occursin("more", l), labels)
        end

        @testset "legend interaction" begin
            chart = _line_chart()
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            plan = iomap.step_iomaps[2][].geometry.legend
            index, ix, iy, iw, ih = first(legend_item_rects(plan))

            # Clicking a legend item hides the series it stands for.
            op = read_intent(proj, iomap, MousePress(:left, ix + 2, iy + ih ÷ 2))
            @test op isa ReplaceReferencedValueOperation
            @test op.document === chart.series[index]
            @test op.value == false

            # Hovering one names it, so the frame can veil the others.
            op = read_intent(proj, iomap, MouseMove(ix + 2, iy + ih ÷ 2, :none, ModifierKeys()))
            @test op !== nothing
            evaluate_operation(nothing, op)
            @test plot.hovered !== nothing
            veiled = [e for e in _series_elements(iomap.output) if e isa GraphicsPolyline]
            @test veiled[1].color.alpha != veiled[2].color.alpha

            # Leaving clears both hover fields.
            op = read_intent(proj, iomap, MouseLeave(0, 0, :none, ModifierKeys()))
            @test op !== nothing
            evaluate_operation(nothing, op)
            @test plot.hovered === nothing && plot.cursor === nothing
        end

        @testset "part selection" begin
            chart = _line_chart()
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            g = iomap.step_iomaps[2][].geometry

            # A click on the title strip selects the title, on an axis strip the
            # axis — and the reference that comes back is in the chart's own
            # domain, not the plot's, because stage 1 peels its step off.
            op = read_intent(proj, iomap, MousePress(:left, g.plot_x + 10, 2))
            @test op isa ReplaceSelectionOperation
            @test is_reference_equal(strip_reference_types(op.path),
                                     strip_reference_types(@reference ::Chart.title::String))

            op = read_intent(proj, iomap,
                             MousePress(:left, 4, g.plot_y + g.plot_h ÷ 2))
            @test op isa ReplaceSelectionOperation
            @test is_reference_equal(strip_reference_types(op.path),
                                     strip_reference_types(@reference ::Chart.y_axis::ChartAxis))

            # A click right on a data point selects the point.
            pts = _line_points_of(g, 1)
            @test !isempty(pts)
            px, py = pts[length(pts) ÷ 2]
            op = read_intent(proj, iomap,
                             MousePress(:left, px + g.plot_x, py + g.plot_y))
            @test op isa ReplaceSelectionOperation
            chart.selection = op.path
            @test selected_sample(chart) !== nothing
            # A sample still counts as its series for everything coarser —
            # navigation, the hover veil, the legend highlight.
            @test selected_series_index(chart) == 1
            @test chart_part_index(chart, op.path) == 5

            # A click on the series' geometry but away from any sample selects
            # the whole series instead.
            far = _series_hit_away_from_samples(g, pts)
            if far !== nothing
                op = read_intent(proj, iomap, MousePress(:left, far[1], far[2]))
                @test op isa ReplaceSelectionOperation
                @test is_reference_equal(strip_reference_types(op.path),
                    strip_reference_types(@reference ::Chart.series::CellVector[1]::ChartLineSeries))
            end
        end

        @testset "point selection" begin
            x = collect(0.0:1.0:20.0)
            chart = Chart("p", [ChartLineSeries("a", x, x .^ 2)])

            # A sample is named by a step on the series, not by descending into
            # the column: there is no per-sample document for a path to reach.
            reference = chart_sample_reference(chart, 1, 5)
            @test is_fully_typed_reference(reference)
            @test evaluate_reference(chart, reference) == (4.0, 16.0)
            chart.selection = reference
            @test selected_sample(chart) == (1, 5)
            @test selected_series_index(chart) == 1

            # Out of range names nothing rather than throwing.
            @test chart_sample(chart.series[1], 999) === nothing
            @test chart_sample(chart.series[1], 0) === nothing

            # Each series kind says what one of its samples is.
            hist = ChartHistogramSeries("h", [0.0, 1.0, 2.0], [3.0, 4.0])
            @test chart_sample(hist, 2) == (1.0, 2.0, 4.0)
            @test chart_sample(ChartBarSeries("b", [7.0, 8.0]), 2) == 8.0

            # The selected sample is drawn.
            plain = length(_series_elements(_chart_canvas(Chart("p", [ChartLineSeries("a", x, x .^ 2)]))))
            @test length(_series_elements(_chart_canvas(chart))) > plain

            # Picking a point out of a huge sorted series is a binary search, not
            # a scan — so it stays interactive at a million samples.
            big_x = collect(range(0.0, 1000.0; length=1_000_000))
            big = Chart("big", [ChartLineSeries("a", big_x, sin.(big_x))])
            proj = _chart_projection()
            iomap = print_document(proj, proj, big, PrinterContext())
            g = iomap.step_iomaps[2][].geometry
            target = ChartGeometryModule.to_pixel(g.xs, 500.0)
            elapsed = @elapsed op = read_intent(proj, iomap,
                MousePress(:left, round(Int, target),
                           round(Int, ChartGeometryModule.to_pixel(g.ys, sin(500.0)))))
            @test op isa ReplaceSelectionOperation
            @test elapsed < 0.5
            big.selection = op.path
            picked = selected_sample(big)
            @test picked !== nothing
            @test abs(big_x[picked[2]] - 500.0) < 1.0

            # A folded scatter draws no individual points, so there is none to
            # click: the click falls through to the series.
            cloud = Chart("c", [ChartScatterSeries("a", rand(50_000), rand(50_000))];
                          style=ChartStyle(; scatter_fold_threshold=1_000))
            proj = _chart_projection()
            iomap = print_document(proj, proj, cloud, PrinterContext())
            g = iomap.step_iomaps[2][].geometry
            op = read_intent(proj, iomap,
                MousePress(:left, g.plot_x + g.plot_w ÷ 2, g.plot_y + g.plot_h ÷ 2))
            cloud.selection = op === nothing ? nothing : op.path
            @test selected_sample(cloud) === nothing
        end

        @testset "series reordering" begin
            chart = _line_chart()
            first_label = String(chart.series[1].label)
            second_label = String(chart.series[2].label)

            # Nothing selected, nothing to move.
            @test selected_series_index(chart) == 0
            @test read_gesture(chart, KeyDown(:down, move_modifier)) === nothing

            chart.selection = @reference ::Chart.series::CellVector[1]::ChartLineSeries
            @test selected_series_index(chart) == 1

            op = read_gesture(chart, KeyDown(:down, move_modifier))
            @test op !== nothing
            _apply_to(chart, op)
            @test String(chart.series[1].label) == second_label
            @test String(chart.series[2].label) == first_label
            # The selection follows the series that moved.
            @test selected_series_index(chart) == 2

            op = read_gesture(chart, KeyDown(:up, move_modifier))
            _apply_to(chart, op)
            @test String(chart.series[1].label) == first_label

            # Moving past either end is not an operation at all.
            chart.selection = @reference ::Chart.series::CellVector[1]::ChartLineSeries
            @test read_gesture(chart, KeyDown(:up, move_modifier)) === nothing

            # Deleting removes exactly the selected series.
            op = read_gesture(chart, KeyDown(:delete, alt_modifier))
            @test op !== nothing
            _apply_to(chart, op)
            @test length(chart.series) == 1
            @test String(chart.series[1].label) == second_label
        end

        @testset "zoom and pan" begin
            x = collect(0.0:0.1:100.0)
            chart = Chart("z", [ChartLineSeries("a", x, sin.(x))])
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            g = iomap.step_iomaps[2][].geometry
            mid_x = g.plot_x + g.plot_w ÷ 2
            mid_y = g.plot_y + g.plot_h ÷ 2

            before = resolve_view(plot)
            # The wheel zooms about the cursor: the window narrows, and the data
            # point that was under the pointer is still under it.
            under = ChartGeometryModule.to_data(g.xs, mid_x)
            op = read_intent(proj, iomap, MouseScroll(0, 1, mid_x, mid_y, ModifierKeys()))
            @test op !== nothing
            evaluate_operation(nothing, op)
            after = resolve_view(plot)
            @test (after.x_max - after.x_min) < (before.x_max - before.x_min)
            @test (after.y_max - after.y_min) < (before.y_max - before.y_min)
            # The point under the cursor stays under it — to within a couple of
            # pixels, since a narrower window means different tick labels and so
            # a slightly different left margin.
            g2 = iomap.step_iomaps[2][].geometry
            pixel = (after.x_max - after.x_min) / g2.plot_w
            @test ChartGeometryModule.to_data(g2.xs, mid_x) ≈ under atol=4pixel

            # Wheeling out again widens it back.
            op = read_intent(proj, iomap, MouseScroll(0, -1, mid_x, mid_y, ModifierKeys()))
            evaluate_operation(nothing, op)
            back = resolve_view(plot)
            @test (back.x_max - back.x_min) ≈ (before.x_max - before.x_min) atol=1e-6

            # Over the x-axis strip only x zooms; over the y strip only y.
            op = read_intent(proj, iomap,
                MouseScroll(0, 1, mid_x, g.plot_y + g.plot_h + 4, ModifierKeys()))
            evaluate_operation(nothing, op)
            v = resolve_view(plot)
            @test (v.x_max - v.x_min) < (before.x_max - before.x_min)
            @test (v.y_max - v.y_min) ≈ (before.y_max - before.y_min) atol=1e-6

            plot.view = nothing
            op = read_intent(proj, iomap,
                MouseScroll(0, 1, g.plot_x - 4, mid_y, ModifierKeys()))
            evaluate_operation(nothing, op)
            v = resolve_view(plot)
            @test (v.x_max - v.x_min) ≈ (before.x_max - before.x_min) atol=1e-6
            @test (v.y_max - v.y_min) < (before.y_max - before.y_min)

            # Shift+wheel pans without changing the window width.
            plot.view = nothing
            op = read_intent(proj, iomap,
                MouseScroll(0, 1, mid_x, mid_y, ModifierKeys(; shift=true)))
            evaluate_operation(nothing, op)
            v = resolve_view(plot)
            @test (v.x_max - v.x_min) ≈ (before.x_max - before.x_min) atol=1e-6
            @test v.x_min > before.x_min

            # A wheel outside the plot and its axis strips is not ours.
            @test read_intent(proj, iomap, MouseScroll(0, 1, 2, 2, ModifierKeys())) === nothing

            # Keyboard: pan, zoom, and reset to auto-fit.
            # Shift+arrow pans; the bare arrows belong to selection navigation.
            plot.view = nothing
            op = read_intent(proj, iomap, KeyDown(:right, ModifierKeys(; shift=true)))
            @test op !== nothing
            evaluate_operation(nothing, op)
            @test resolve_view(plot).x_min > before.x_min
            # A bare arrow falls past the view reader to the chart's own
            # navigation, which is what moves the selection.
            @test read_intent(proj, iomap, KeyDown(:right, ModifierKeys())) isa ReplaceSelectionOperation
            # '0' drops back to auto-fit, whatever the window had become.
            op = read_intent(proj, iomap, KeyPress('0'))
            @test op !== nothing
            evaluate_operation(nothing, op)
            @test plot.view === nothing
        end

        @testset "rubber band" begin
            x = collect(0.0:0.1:100.0)
            chart = Chart("z", [ChartLineSeries("a", x, sin.(x))])
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            g = iomap.step_iomaps[2][].geometry
            x0, y0 = g.plot_x + 30, g.plot_y + 30
            x1, y1 = g.plot_x + 160, g.plot_y + 140

            evaluate_operation(nothing, read_intent(proj, iomap, MouseDown(:left, x0, y0, ModifierKeys())))
            @test plot.drag_anchor !== nothing

            evaluate_operation(nothing, read_intent(proj, iomap, MouseMove(x1, y1, :left, ModifierKeys())))
            @test plot.drag_rect !== nothing
            # While the band is up it is drawn over the series.
            @test _count_kind(_series_elements(iomap.output), GraphicsRect) >= 1

            evaluate_operation(nothing, read_intent(proj, iomap, MouseUp(:left, x1, y1, ModifierKeys())))
            @test plot.drag_anchor === nothing && plot.drag_rect === nothing
            v = resolve_view(plot)
            # The committed window is what the band enclosed.
            @test v.x_min ≈ ChartGeometryModule.to_data(g.xs, x0) atol=0.5
            @test v.x_max ≈ ChartGeometryModule.to_data(g.xs, x1) atol=0.5

            # A band that never grew is a click, not a zoom.
            plot.view = nothing
            evaluate_operation(nothing, read_intent(proj, iomap, MouseDown(:left, x0, y0, ModifierKeys())))
            evaluate_operation(nothing, read_intent(proj, iomap, MouseUp(:left, x0 + 2, y0 + 2, ModifierKeys())))
            @test plot.view === nothing

            # Leaving mid-drag abandons it rather than committing halfway.
            evaluate_operation(nothing, read_intent(proj, iomap, MouseDown(:left, x0, y0, ModifierKeys())))
            evaluate_operation(nothing, read_intent(proj, iomap, MouseMove(x1, y1, :left, ModifierKeys())))
            evaluate_operation(nothing, read_intent(proj, iomap, MouseLeave(0, 0, :none, ModifierKeys())))
            @test plot.drag_anchor === nothing && plot.drag_rect === nothing
            @test plot.view === nothing

            # Shift-dragging pans instead of banding.
            evaluate_operation(nothing, read_intent(proj, iomap,
                MouseDown(:left, x1, y1, ModifierKeys(; shift=true))))
            evaluate_operation(nothing, read_intent(proj, iomap,
                MouseMove(x1 - 40, y1, :left, ModifierKeys(; shift=true))))
            @test plot.drag_rect === nothing
            @test plot.view !== nothing
            evaluate_operation(nothing, read_intent(proj, iomap, MouseUp(:left, x1 - 40, y1, ModifierKeys())))
        end

        @testset "crosshair" begin
            x = collect(0.0:1.0:20.0)
            chart = Chart("c", [ChartLineSeries("a", x, x)])
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            g = iomap.step_iomaps[2][].geometry

            plain = length(_series_elements(iomap.output))
            evaluate_operation(nothing, read_intent(proj, iomap,
                MouseMove(g.plot_x + g.plot_w ÷ 2, g.plot_y + g.plot_h ÷ 2, :none, ModifierKeys())))
            @test plot.cursor !== nothing
            els = _series_elements(iomap.output)
            @test length(els) > plain
            # Two dashed crosshair lines, and a readout naming the series.
            @test count(e -> e isa GraphicsLine && e.dash !== nothing, els) == 2
            @test any(e -> e isa GraphicsText && occursin("a", String(e.text)), els)
        end

        @testset "part navigation" begin
            chart = _line_chart()
            # Title, both axes, the legend, then one entry per series.
            parts = chart_parts(chart)
            @test length(parts) == 4 + length(chart.series)
            @test chart_part_index(chart, parts[1]) == 1
            @test chart_part_index(chart, parts[end]) == length(parts)

            ed = (; document = chart)
            # Ctrl+Home seeds a selection, which is what every navigation walk
            # needs before it can start.
            op = read_gesture(chart, KeyDown(:home, ModifierKeys(; ctrl=true)))
            @test op isa ReplaceSelectionOperation
            _apply_to(chart, op)
            @test chart_part_index(chart, chart.selection) == 1

            # Right walks forward through every part and stops at the end.
            seen = Int[1]
            for _ in 1:20
                op = read_gesture(chart, KeyDown(:right, no_modifier))
                op === nothing && break
                _apply_to(chart, op)
                push!(seen, chart_part_index(chart, chart.selection))
            end
            @test seen == collect(1:length(parts))
            @test read_gesture(chart, KeyDown(:right, no_modifier)) === nothing

            # And Left walks back.
            op = read_gesture(chart, KeyDown(:left, no_modifier))
            @test op !== nothing
            _apply_to(chart, op)
            @test chart_part_index(chart, chart.selection) == length(parts) - 1

            _apply_to(chart, read_gesture(chart, KeyDown(:end, ModifierKeys(; ctrl=true))))
            @test chart_part_index(chart, chart.selection) == length(parts)
            _apply_to(chart, read_gesture(chart, KeyDown(:home, no_modifier)))
            @test chart_part_index(chart, chart.selection) == 1

            # Tree navigation: out to the whole chart, and back in.
            _apply_to(chart, read_gesture(chart, KeyDown(:left, alt_modifier)))
            @test chart.selection isa EmptyReference
            @test chart_part_index(chart, chart.selection) == 0
            _apply_to(chart, read_gesture(chart, KeyDown(:right, alt_modifier)))
            @test chart_part_index(chart, chart.selection) == 1
            # Alt+Down/Up move between siblings.
            _apply_to(chart, read_gesture(chart, KeyDown(:down, alt_modifier)))
            @test chart_part_index(chart, chart.selection) == 2

            # Ctrl+Alt+Home selects the whole chart, wherever the cursor was.
            _apply_to(chart, read_gesture(chart, KeyDown(:home, ModifierKeys(; ctrl=true, alt=true))))
            @test chart.selection isa EmptyReference

            # The view gestures do not take the arrows away from navigation.
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            @test read_intent(proj.projections[2], iomap.step_iomaps[2][],
                              KeyDown(:right, no_modifier)) === nothing
            @test read_intent(proj.projections[2], iomap.step_iomaps[2][],
                              KeyDown(:right, ModifierKeys(; shift=true))) !== nothing
        end

        @testset "selection is drawn" begin
            chart = _line_chart()
            parts = chart_parts(chart)
            ed = (; document = chart)

            plain = length(_flatten_elements(_chart_canvas(chart)))
            renders = Int[]
            for reference in parts
                chart.selection = reference
                push!(renders, length(_flatten_elements(_chart_canvas(chart))))
            end
            # Every part adds something to the output when it is selected —
            # a selection nothing draws would be invisible to the user.
            @test all(n -> n > plain, renders)

            # The whole chart is called out with a frame of its own.
            chart.selection = EmptyReference(get_reference_node_type(chart))
            @test length(_flatten_elements(_chart_canvas(chart))) > plain
        end

        @testset "property inspector" begin
            # A chart beside a reflection-driven form over one of its own
            # series: the same document, two projections. This is what makes a
            # chart property editable without writing a property editor.
            chart = make_chart_line_document_example()
            series = chart.series[1]
            inspector = ObjectToWidget(fields=[:label, :line_width, :visible])
            form = print_document(inspector, series)

            names = [String(path.head.name) for (_, path) in form.controls]
            @test names == ["label", "line_width", "visible"]
            # The data columns are not properties: a form row per sample would be
            # useless, and unusable at a million of them.
            @test !("x" in names) && !("y" in names)

            # A checkbox edit in the form writes the series' own cell.
            checkbox = form.controls[3][1]
            op = read_intent(inspector, form,
                ReplaceReferencedValueOperation(checkbox,
                    ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                    false))
            @test op isa ReplaceReferencedValueOperation
            @test op.document === series
            @test String(op.reference.head.name) == "visible"

            # And that write repaints the chart, because it is the very cell the
            # chart draws from.
            before = length([e for e in _series_elements(_chart_canvas(chart))
                             if e isa GraphicsPolyline])
            evaluate_operation(nothing, op)
            after = length([e for e in _series_elements(_chart_canvas(chart))
                            if e isa GraphicsPolyline])
            @test after == before - 1

            # A text edit round-trips the same way.
            op = read_intent(inspector, form,
                ReplaceReferencedValueOperation(form.controls[2][1],
                    ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                    "4"))
            @test op isa ReplaceReferencedValueOperation
            @test String(op.reference.head.name) == "line_width"
            evaluate_operation(nothing, op)
            @test series.line_width == 4
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
        # The ceiling every case is held to: a chart may not emit more elements
        # than a few per pixel column of its plot rectangle, whatever it is
        # showing. 760x460 is the default canvas.
        ceiling = 4_000

        @testset "million-sample line" begin
            n = 1_000_000
            x = collect(range(0.0, 100.0; length=n))
            y = sin.(range(0.0, 400π; length=n))
            chart = Chart("big", [ChartLineSeries("a", x, y)])

            canvas = _chart_canvas(chart)
            @test length(_flatten_elements(canvas)) < 200
            pl = first(e for e in _series_elements(canvas) if e isa GraphicsPolyline)
            # At most four points per pixel column of the plot rectangle.
            @test length(pl.points) <= 4 * (Int(_viewport_of(canvas).w) + 2)
            @test length(pl.points) < n ÷ 100

            # A ten-times-shorter column does not make a smaller picture: the
            # cost is the plot rectangle, not the data.
            short = Chart("small", [ChartLineSeries("a", x[1:100_000], y[1:100_000])])
            short_pl = first(e for e in _series_elements(_chart_canvas(short))
                             if e isa GraphicsPolyline)
            @test abs(length(short_pl.points) - length(pl.points)) < length(pl.points)

            elapsed = @elapsed length(_series_elements(_chart_canvas(chart)))
            @test elapsed < 5.0
        end

        @testset "million-point scatter" begin
            n = 1_000_000
            chart = Chart("cloud", [ChartScatterSeries("a", randn(n), randn(n))])
            canvas = _chart_canvas(chart)
            els = _series_elements(canvas)
            # Folded into a density grid: one shaded cell per occupied bin, so
            # the count is bounded by the plot area rather than by the points.
            @test !isempty(els)
            @test length(els) < ceiling
            @test all(e -> e isa GraphicsRect, els)
            # Density is carried by alpha, so the cells cannot all be identical.
            @test length(unique(e.color.alpha for e in els)) > 1
        end

        @testset "ten-thousand-category bar" begin
            cats = ["c$i" for i in 1:10_000]
            chart = Chart("many", [ChartBarSeries("v", collect(1.0:10_000.0))];
                          x_axis=ChartCategoryAxis(; categories=cats),
                          legend=ChartLegend(; visible=false))
            canvas = _chart_canvas(chart)
            @test length(_series_elements(canvas)) < ceiling
            # And the labels are thinned to what fits rather than one per slot.
            labels = [e for e in collect(canvas.elements) if e isa GraphicsText]
            @test 0 < length(labels) < 40
        end

        @testset "ten-thousand-bin histogram" begin
            edges = collect(0.0:1.0:10_000.0)
            values = Float64.(1:10_000)
            chart = Chart("h", [ChartHistogramSeries("a", edges, values)];
                          legend=ChartLegend(; visible=false))
            els = _series_elements(_chart_canvas(chart))
            @test !isempty(els)
            @test length(els) < ceiling
        end

        @testset "zoomed in stays exact" begin
            # Once the window holds few enough samples that each has its own
            # pixel column, decimation drops nothing.
            x = collect(0.0:1.0:100_000.0)
            chart = Chart("z", [ChartLineSeries("a", x, sin.(x ./ 500))])
            proj = _chart_projection()
            iomap = print_document(proj, proj, chart, PrinterContext())
            plot = iomap.step_iomaps[1][].output
            plot.view = ChartView(0.0, 100.0, -1.0, 1.0)
            pl = first(e for e in _series_elements(iomap.output) if e isa GraphicsPolyline)
            @test 100 <= length(pl.points) <= 110
        end
    end
end
