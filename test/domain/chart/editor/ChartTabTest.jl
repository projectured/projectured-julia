# A chart on a tab: the tab has the title of the chart, and the duplicate of a
# chart is a chart of its own, a copy of its axes and its series.

using Test

"""
    test_chart_tab()

The title of a chart names the tab that shows it, and a chart with no title names
none. A chart says how many series it holds. The duplicate of a chart is a copy: a
change of the copy leaves the chart as it was.
"""
function test_chart_tab()
@testset "a chart on a tab has its title and a duplicate" begin
    chart = Chart("Sales", Any[ChartLineSeries("a", 1:3, [1.0, 2.0, 3.0])];
                  x_axis = ChartAxis(title = "month"))
    @test get_document_title(chart) == "Sales"
    @test get_document_title(Chart("", Any[])) === nothing
    @test describe_document(chart) == "a chart of 1 series, Sales"
    @test describe_document(Chart("", Any[])) == "a chart of 0 series"

    # A tab opened with no title of its own takes the title of the chart.
    editor = _make_chart_verbs_application(chart, nothing)
    @test get_document(get_edited_document(find_pane("Sales"; editor))) === chart

    copy = make_document_duplicate(chart)
    @test copy isa Chart && copy !== chart
    @test copy.title == "Sales" && copy.x_axis.title == "month"
    @test copy.series[1] !== chart.series[1] && copy.series[1].y == [1.0, 2.0, 3.0]
    copy.title = "Costs"
    copy.series[1].label = "b"
    @test chart.title == "Sales" && chart.series[1].label == "a"
end
end
