"""
The chart views of a cell: the automatic choice of a chart, a bar chart in each
of 3 × 4 cells with the same categories and the same range of values, a line
chart over a dimension of numbers, and a pie chart that a person chooses.
"""

function test_pivot_chart_views()
@testset "the chart views of a cell" begin

# Three rows, four columns, three categories in each cell; the cell of row 3 and
# column 4 has no row of the category z.
table = (r = String[], c = Int[], k = String[], n = Int[], v = Float64[])
for r in ("a", "b", "c"), c in 1:4, (j, k) in enumerate(("x", "y", "z"))
    (r == "c" && c == 4 && k == "z") && continue
    push!(table.r, r); push!(table.c, c); push!(table.k, k); push!(table.n, j * 10)
    push!(table.v, 10.0 * findfirst(==(r), ("a", "b", "c")) + c + j)
end
pivot = make_pivot_table(table; rows = ["r"], columns = ["c"], cells = ["k"], measures = [PivotMeasure("v", :sum)])
@test get_pivot_cell_view(pivot) isa PivotBarChartView
@test get_pivot_cell_view_lines(PivotBarChartView()) == 5

# ── A bar chart in each cell, on one range ──────────────────────────────────

charts = [pivot.cells[r][c] for r in 1:3, c in 1:4]
@test all(chart -> chart isa PivotChartCell, charts)
@test all(chart -> chart.chart.y_axis.min == 0.0 && chart.chart.y_axis.max == 36.0, charts)
@test all(chart -> chart.chart.x_axis.categories == ["x", "y", "z"], charts)
first_bars = charts[1, 1].chart.series[1]
@test first_bars isa ChartBarSeries && collect(first_bars.values) == [12.0, 13.0, 14.0]
@test collect(charts[3, 4].chart.series[1].values) == [35.0, 36.0, 0.0]
@test !charts[1, 1].chart.legend.visible
@test !charts[1, 1].chart.x_axis.show_labels && !charts[1, 1].chart.y_axis.show_labels
# The data is computed once for all the cells, and again for a new measure.
@test pivot.cells[1][1] === charts[1, 1]
getfield(pivot, :measures)[] = CellVector(Any[PivotMeasure("v", :maximum)])
@test pivot.cells[1][1] !== charts[1, 1]
@test pivot.cells[1][1].chart.y_axis.max == 36.0

# Two cell dimensions: a series for each value of the second.
two = make_pivot_table(table; rows = ["r"], cells = ["k", "c"], measures = [PivotMeasure("v", :sum)])
@test get_pivot_cell_view(two) isa PivotBarChartView
@test length(two.cells[1][1].chart.series) == 4

# ── A line chart over numbers, and a pie chart on request ───────────────────

lines = make_pivot_table(table; rows = ["r"], columns = ["c"], cells = ["n"], measures = [PivotMeasure("v", :sum)])
@test get_pivot_cell_view(lines) isa PivotLineChartView
line = lines.cells[1][1].chart.series[1]
@test line isa ChartLineSeries && collect(line.x) == [10.0, 20.0, 30.0] && collect(line.y) == [12.0, 13.0, 14.0]
@test collect(lines.cells[3][4].chart.series[1].x) == [10.0, 20.0]
getfield(pivot, :cell_view)[] = PivotPieChartView()
pie = pivot.cells[1][1].chart.series[1]
@test pie isa ChartPieSeries && pie.categories == ["x", "y", "z"]
@test "Show the cells as pie charts" in [item.action.label for item in compute_context_menu(pivot).elements]
# Many values of one dimension of text: the rows.
many = make_pivot_table((k = string.(1:20), v = collect(1.0:20.0)); cells = ["k"])
@test get_pivot_cell_view(many) isa PivotRowsView

# ── The charts draw in their cells ──────────────────────────────────────────

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(500)))
io = print_document(projection, nothing, pivot, context)
polygons = Ref(0)
function count_polygons(node)
    node isa GraphicsPolygon && (polygons[] += 1)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements
            while n !== nothing
                count_polygons(n.value); n = n.next
            end
        else
            foreach(count_polygons, elements)
        end
    elseif node isa GraphicsViewport
        count_polygons(node.content)
    end
end
count_polygons(io.output)
@test polygons[] == 3 * 3 * 4 - 1

end
end
