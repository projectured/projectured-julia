# A pie chart and the size of a chart.
#
# A chart of pie series draws an arc as wide as its radius for each slice of
# positive value, and no axis; a chart in a small slot draws at the least size that
# its renderer names; and the extent of a chart on each axis reads only the limits
# of that axis.

function test_chart_pie()
@testset "a pie chart, and the size of a chart" begin

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

# Each axis of a chart reads only its own limits. A grid finds the widths of its
# columns before the heights of its rows, so a width that read a height limit
# would close a cycle through the rows above it. A limit of the other axis that
# throws when it is read leaves each extent as it is.
other_axis = Cell(@computation error("a limit of the other axis was read"))
wide = with_size_range(PrinterContext(); width = (nothing, Cell(Int32(300))), height = (nothing, other_axis))
@test Int(print_document(default, nothing, bar, wide).output.w) == 300
high = with_size_range(PrinterContext(); width = (nothing, other_axis), height = (nothing, Cell(Int32(200))))
@test Int(print_document(default, nothing, bar, high).output.h) == 200
# The example of the domain, four charts in a table of two rows and two columns,
# draws each chart at its size in the slot of a window.
slot = with_bounded_size(PrinterContext(); width = Cell(Int32(1600)), height = Cell(Int32(1000)))
table = print_document(make_chart_projection_example(), nothing, make_chart_document_example(), slot).output
@test count(e -> e isa GraphicsCanvas && (Int(e.w), Int(e.h)) == (430, 300), _flatten_elements(table)) == 4

end
end
