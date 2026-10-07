# A pie chart and the least size of a chart.
#
# A chart of pie series draws an arc as wide as its radius for each slice of
# positive value, and no axis; a chart in a small slot draws at the least size that
# its renderer names.

function test_chart_pie()
@testset "a pie chart, and the least size of a chart" begin

pie = Chart("", [ChartPieSeries("share", ["a", "b", "c", "d"], [1, 2, 1, 0])])
canvas = _chart_canvas(pie; width = 200, height = 200)
elements = _flatten_elements(canvas)
@test _count_kind(elements, GraphicsArc) == 3
@test _count_kind(elements, GraphicsPolygon) == 0
@test _count_kind(elements, GraphicsLine) == 0
@test get_chart_series_family(pie.series[1]) === :pie
# The slices share the circle by their values, from the top, clockwise: the
# second is as large as the first and the third together. Each slice is filled
# from the centre, and all share the centre and the radius.
slices = [e for e in elements if e isa GraphicsArc]
@test [(Float64(a.start_angle), Float64(a.sweep_angle)) for a in slices] == [(0.0, 90.0), (90.0, 180.0), (270.0, 90.0)]
@test all(a -> Int(a.width) == Int(a.radius) > 0, slices)
@test allequal((Int(a.cx), Int(a.cy), Int(a.radius)) for a in slices)
@test slices[1].color != slices[2].color
# A pie with nothing to share draws no slice.
@test _count_kind(_flatten_elements(_chart_canvas(Chart("", [ChartPieSeries("none", ["a"], [0])]);
                                                  width = 200, height = 200)), GraphicsArc) == 0

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
