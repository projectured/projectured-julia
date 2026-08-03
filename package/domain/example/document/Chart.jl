# Four charts, one of each kind, plus a composite that shows them together.
#
# The data is generated rather than canned so the shapes stay recognisable — a
# decaying oscillation, a few named configurations, two overlapping delay
# distributions, a load/latency cloud — which is what makes it obvious at a
# glance whether the projection is drawing them correctly.
#
# Everything here is a plain Julia vector, which is the whole point of the
# domain's data model: any AbstractVector works, so a data-frame column would
# drop straight in without the chart package knowing about data frames.

_chart_ramp(n, lo, hi) = collect(range(lo, hi; length=n))

# A deterministic wobble, so the examples render identically every run without
# reaching for a random seed.
_chart_wobble(x, k) = sin.(x .* k) .* cos.(x .* (k / 3 + 0.7))

"""
    make_chart_line_document_example() -> Chart

Two line series over a shared time base, one plain and one dashed and thicker,
with markers on neither (there are too many samples for markers to read).
"""
function make_chart_line_document_example()
    t = _chart_ramp(240, 0.0, 30.0)
    Chart("Queue delay",
        [ChartLineSeries("q1", t, _chart_wobble(t, 1.0) .* 4 .+ 10),
         ChartLineSeries("q2", t, _chart_wobble(t, 0.4) .* 3 .+ 12;
                         line_style=:dashed, line_width=2)];
        x_axis=ChartAxis(; title="time (s)"),
        y_axis=ChartAxis(; title="delay (ms)"),
        legend=ChartLegend(; position=:inside, anchor=:northeast, border=true))
end

"""
    make_chart_bar_document_example() -> Chart

Three runs measured over four configurations, on a categorical axis. The
placement is `:aligned`; setting `bar_placement` to `:overlap`, `:infront` or
`:stacked` is what the other three modes look like.
"""
function make_chart_bar_document_example()
    Chart("Throughput by configuration",
        [ChartBarSeries("run A", [12.0, 19.0, 7.0, 15.0]),
         ChartBarSeries("run B", [9.0, 14.0, 11.0, 6.0]),
         ChartBarSeries("run C", [5.0, 8.0, 4.0, 12.0])];
        x_axis=ChartCategoryAxis(; title="configuration",
                                 categories=["baseline", "tuned", "burst", "mixed"]),
        y_axis=ChartAxis(; title="Mbit/s"),
        legend=ChartLegend(; position=:above, anchor=:northeast))
end

"""
    make_chart_histogram_document_example() -> Chart

Two delay distributions over the same bins, one filled and one drawn as an
outline so the overlap stays readable.
"""
function make_chart_histogram_document_example()
    edges = _chart_ramp(31, 0.0, 30.0)
    centres = [(edges[i] + edges[i+1]) / 2 for i in 1:30]
    bell(mu, sigma, scale) = [scale * exp(-((c - mu) / sigma)^2) for c in centres]
    Chart("Delay distribution",
        [ChartHistogramSeries("queueing", edges, bell(11.0, 3.5, 900.0)),
         ChartHistogramSeries("service", edges, bell(17.0, 2.2, 700.0); draw=:outline)];
        x_axis=ChartAxis(; title="delay (ms)"),
        y_axis=ChartAxis(; title="observations"),
        legend=ChartLegend(; position=:inside, anchor=:northeast, border=true))
end

"""
    make_chart_scatter_document_example() -> Chart

Two clouds of measurements against offered load, drawn with different markers.
"""
function make_chart_scatter_document_example()
    load = _chart_ramp(400, 0.0, 100.0)
    Chart("Latency against load",
        [ChartScatterSeries("node 1", load, 18 .+ _chart_wobble(load, 3.1) .* 6),
         ChartScatterSeries("node 2", load, 34 .+ _chart_wobble(load, 1.7) .* 9;
                            symbol=:plus)];
        x_axis=ChartAxis(; title="offered load (%)"),
        y_axis=ChartAxis(; title="latency (ms)"),
        legend=ChartLegend(; position=:inside, anchor=:northwest, border=true))
end

"""
    make_chart_document_example() -> WidgetTable

All four chart kinds in one two-by-two grid — the registered `chart` example,
and what the domain's guide screenshot shows.
"""
function make_chart_document_example()
    WidgetTable(Point2D(0, 0),
        Any[], Any[],
        Any[
            Any[make_chart_line_document_example(), make_chart_bar_document_example()],
            Any[make_chart_histogram_document_example(), make_chart_scatter_document_example()],
        ],
        2;
        padding=6)
end

"""
    make_chart_inspector_document_example() -> WidgetSplitPane

A chart beside a property form over one of its own series — the same document
shown two ways. Editing a field in the form writes the series' cell, which is
the cell the chart draws from, so the chart repaints.
"""
function make_chart_inspector_document_example()
    chart = make_chart_line_document_example()
    WidgetSplitPane(:horizontal, Any[chart, chart.series[1]]; sizes=[540, 320])
end
