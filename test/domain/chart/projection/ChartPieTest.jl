# A pie chart and the least size of a chart.
#
# A chart of pie series draws a polygon for each slice of positive value, and no
# axis; a chart in a small slot draws at the least size that its renderer names.

function test_chart_pie()
@testset "a pie chart, and the least size of a chart" begin

pie = Chart("", [ChartPieSeries("share", ["a", "b", "c", "d"], [1, 2, 1, 0])])
canvas = _chart_canvas(pie; width = 200, height = 200)
elements = _flatten_elements(canvas)
@test _count_kind(elements, GraphicsPolygon) == 3
@test _count_kind(elements, GraphicsLine) == 0
@test get_chart_series_family(pie.series[1]) === :pie
# The slices share the circle by their values: the second is as large as the
# first and the third together, so it has the most points of its arc.
slices = [e for e in elements if e isa GraphicsPolygon]
@test length(slices[2].points) > length(slices[1].points)
@test slices[1].color != slices[2].color
# A pie with nothing to share draws no slice.
@test _count_kind(_flatten_elements(_chart_canvas(Chart("", [ChartPieSeries("none", ["a"], [0])]);
                                                  width = 200, height = 200)), GraphicsPolygon) == 0

# The least size: 120 × 80 by default, and smaller when the renderer names it.
small = with_exact_size(PrinterContext(); width = Cell(Int32(40)), height = Cell(Int32(30)))
bar = Chart("", [ChartBarSeries("n", [1, 2])]; x_axis = ChartCategoryAxis(categories = ["x", "y"]))
default = ChainingProjection(ChartToChartPlot(), ChartPlotToGraphicsCanvas(measure = FontFileMeasure()))
output = print_document(default, nothing, bar, small).output
@test (Int(output.w), Int(output.h)) == (120, 80)
cell = ChainingProjection(ChartToChartPlot(),
                          ChartPlotToGraphicsCanvas(measure = FontFileMeasure(), minimum_width = 20, minimum_height = 16))
output = print_document(cell, nothing, bar, small).output
@test (Int(output.w), Int(output.h)) == (40, 30)

end
end
