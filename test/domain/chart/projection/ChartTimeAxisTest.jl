# A chart with dates on its x axis.
#
# A line or scatter series takes a column of `Date` or `DateTime` values, and the
# axis becomes a time axis: ticks on whole calendar units, labels in the form of the
# unit, and a readout in the form of the labels. A chart that mixes dates and numbers
# draws the series of the first kind and says why in the legend for the others.

function test_chart_time_axis()
@testset "a chart with dates on its x axis" begin

Dates = ChartModule.Dates
coordinate = ChartModule.get_plot_coordinate

# A line of `count` samples spread evenly from `first` to `last`.
function dated_line(first, last, count; label = "s")
    span = Dates.value(Dates.DateTime(last) - Dates.DateTime(first))
    x = [Dates.DateTime(first) + Dates.Millisecond(round(Int, span * (k - 1) / (count - 1))) for k in 1:count]
    ChartLineSeries(label, x, collect(1.0:count))
end
time_of(tick) = ChartModule.get_plot_time(tick)

@testset "the plot coordinate of a date" begin
    @test coordinate(3) === 3.0
    @test coordinate(Dates.Date(2026, 3, 10)) == coordinate(Dates.DateTime(2026, 3, 10))
    @test coordinate(Dates.DateTime(2026, 3, 10, 0, 0, 1)) - coordinate(Dates.DateTime(2026, 3, 10)) == 1000.0
    # Two dates 7 days apart are 7 times as far as two dates 1 day apart.
    day = coordinate(Dates.Date(2026, 3, 11)) - coordinate(Dates.Date(2026, 3, 10))
    @test coordinate(Dates.Date(2026, 3, 17)) - coordinate(Dates.Date(2026, 3, 10)) == 7day
    @test ChartModule.get_series_x(ChartLineSeries("n", [1.0, 2.0], [1.0, 2.0])) isa Vector{Float64}
    column = ChartModule.get_series_x(dated_line(Dates.Date(2026, 3, 10), Dates.Date(2026, 3, 12), 3))
    @test column isa AbstractVector{Float64} && length(column) == 3 && column[2] - column[1] == day
end

@testset "the ticks and the labels follow the span" begin
    layout(first, last, count = 30) =
        _chart_layout(Chart("t", [dated_line(first, last, count)]; legend = ChartLegend(visible = false)))

    # 6 hours: whole hours or finer, and the date at the first tick.
    g = layout(Dates.DateTime(2026, 3, 10, 9), Dates.DateTime(2026, 3, 10, 15))
    @test length(g.xticks) >= 3 && length(g.xticks) == length(g.xlabels)
    @test all(t -> Dates.second(time_of(t)) == 0 && Dates.minute(time_of(t)) % 5 == 0, g.xticks)
    @test startswith(g.xlabels[1], "2026-03-10 ")
    @test all(label -> occursin(r"^\d\d:\d\d$", label), g.xlabels[2:end])
    @test g.x_time_form === :minute

    # 2 days: the date shows at the first tick of each day.
    g = layout(Dates.DateTime(2026, 3, 10), Dates.DateTime(2026, 3, 12))
    days = [Dates.Date(time_of(t)) for t in g.xticks]
    @test length(unique(days)) >= 2
    for k in eachindex(g.xticks)
        first_of_day = k == 1 || days[k] != days[k - 1]
        @test occursin(r"^\d{4}-\d\d-\d\d", g.xlabels[k]) == first_of_day || startswith(g.xlabels[k], "2026-03-")
    end
    @test all(t -> Dates.minute(time_of(t)) == 0, g.xticks)

    # 3 weeks: whole days, labelled with the date.
    g = layout(Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 23))
    @test all(t -> time_of(t) == Dates.DateTime(Dates.Date(time_of(t))), g.xticks)
    @test all(label -> occursin(r"^2026-0[23]-\d\d$", label), g.xlabels)
    @test g.x_time_form === :day

    # 5 months: one tick at the start of each month.
    g = layout(Dates.Date(2026, 1, 15), Dates.Date(2026, 6, 15))
    @test g.xlabels == ["2026-02", "2026-03", "2026-04", "2026-05", "2026-06"]
    @test all(t -> Dates.day(time_of(t)) == 1, g.xticks)
    @test g.x_time_form === :month

    # 3 years: the finest step whose labels fit is a quarter, on the first day of
    # its first month.
    g = layout(Dates.Date(2023, 6, 1), Dates.Date(2026, 6, 1))
    @test g.xlabels[1:3] == ["2023-07", "2023-10", "2024-01"]
    @test all(t -> Dates.day(time_of(t)) == 1 && Dates.month(time_of(t)) % 3 == 1, g.xticks)
    @test g.x_time_form === :month

    # 30 years: one tick at the start of a year, every 1, 2, 5 or 10 years.
    g = layout(Dates.Date(1996, 6, 1), Dates.Date(2026, 6, 1))
    @test all(label -> occursin(r"^\d{4}$", label), g.xlabels)
    @test all(t -> Dates.month(time_of(t)) == 1 && Dates.day(time_of(t)) == 1, g.xticks)
    years = [Dates.year(time_of(t)) for t in g.xticks]
    @test length(unique(diff(years))) == 1 && only(unique(diff(years))) in (1, 2, 5, 10)
    @test all(year -> year % only(unique(diff(years))) == 0, years)
    @test g.x_time_form === :year
end

@testset "the readout gives the time in the form of the labels" begin
    month = Chart("t", [dated_line(Dates.Date(2026, 1, 15), Dates.Date(2026, 6, 15), 30)])
    g = _chart_layout(month)
    @test ChartModule._format_axis_value(month.x_axis, coordinate(Dates.Date(2026, 3, 15)); time_form = g.x_time_form) == "2026-03"
    @test ChartModule.format_time_value(coordinate(Dates.DateTime(2026, 3, 10, 9, 5)), :minute) == "2026-03-10 09:05"
    @test ChartModule.format_time_value(coordinate(Dates.DateTime(2026, 3, 10, 9, 5, 7)), :second) == "2026-03-10 09:05:07"
    @test ChartModule.format_time_value(coordinate(Dates.Date(2026, 3, 10)), :day) == "2026-03-10"
    @test ChartModule._format_axis_value(month.x_axis, 12.5) == "12.5"
end

@testset "a zoom and a click on a sample work on a time axis" begin
    chart = Chart("t", [dated_line(Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 23), 22)])
    # A zoom halves the window in milliseconds, in the linear space of the axis.
    plot = ChartPlot(chart)
    view = resolve_view(plot)
    zoomed = ChartModule.compute_zoomed_window((view.x_min, view.x_max), 0.5;
                                               extent = (view.x_min, view.x_max), focus = nothing,
                                               log = ChartModule._is_log_x_axis(chart))
    @test zoomed[2] - zoomed[1] ≈ (view.x_max - view.x_min) / 2
    # An axis that gives its ends as dates pins the window.
    pinned = Chart("t", [dated_line(Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 23), 22)];
                   x_axis = ChartAxis(min = Dates.Date(2026, 3, 5), max = Dates.Date(2026, 3, 10)))
    g = _chart_layout(pinned)
    @test g.view.x_min == coordinate(Dates.Date(2026, 3, 5)) && g.view.x_max == coordinate(Dates.Date(2026, 3, 10))
    # A click on the 6th sample, 2026-03-07, finds it.
    px = round(Int, ChartModule.to_pixel(g.xs, coordinate(Dates.Date(2026, 3, 7))))
    py = round(Int, ChartModule.to_pixel(g.ys, 6.0))
    @test ChartModule._sample_hit(g, px, py) == (1, 6)
    @test ChartModule.get_chart_sample(pinned.series[1], 6) == (coordinate(Dates.Date(2026, 3, 7)), 6.0)
    # A time axis draws linear.
    logged = Chart("t", [dated_line(Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 23), 22)];
                   x_axis = ChartAxis(log = true))
    @test !_chart_layout(logged).xs.log
    # A scatter series takes dates too.
    scatter = Chart("t", [ChartScatterSeries("p", [Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 9)], [1.0, 2.0])])
    @test _chart_layout(scatter).x_time_form !== :none
    @test ChartModule._sample_hit(_chart_layout(scatter), 0, 0) === nothing
end

@testset "a chart keeps its dates in a .pred file" begin
    chart = Chart("t", [ChartLineSeries("s", [Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 9)], [1.0, 2.0])])
    text = print_pred_text(chart)
    @test occursin("Dates.Date(\"2026-03-09\")", text)
    loaded = parse_pred_text(text)
    @test collect(loaded.series[1].x) == [Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 9)]
    # The column that the file reads holds dates of no declared type, and the axis
    # is a time axis still.
    @test ChartModule.is_date_column(loaded.series[1].x)
    @test _chart_layout(loaded).x_time_form !== :none
    @test print_pred_text(loaded) == text
end

@testset "a chart that mixes dates and numbers says why in the legend" begin
    dated = dated_line(Dates.Date(2026, 3, 2), Dates.Date(2026, 3, 23), 22; label = "dated")
    numbers = ChartLineSeries("numbers", collect(1.0:5.0), collect(1.0:5.0))
    g = _chart_layout(Chart("t", [dated, numbers]))
    @test [item[2] for item in g.legend.items] == ["dated", "numbers: x holds numbers, the axis shows dates"]
    @test length(g.series) == 1 && g.x_time_form === :day
    g = _chart_layout(Chart("t", [numbers, dated]))
    @test [item[2] for item in g.legend.items] == ["numbers", "dated: x holds dates, the axis shows numbers"]
    @test length(g.series) == 1 && g.x_time_form === :none
end

end
end
