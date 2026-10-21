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
@test "Show the cells as pie charts" in [item.action.label for item in compute_context_menu(pivot).elements
                                         if item isa WidgetMenuItem]
# Many values of one dimension of text: the rows.
many = make_pivot_table((k = string.(1:20), v = collect(1.0:20.0)); cells = ["k"])
@test get_pivot_cell_view(many) isa PivotRowsView

# ── The charts draw in their cells ──────────────────────────────────────────

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(500)))
io = print_document(projection, nothing, pivot, context)
slices = Ref(0)
function count_slices(node)
    node isa GraphicsArc && (slices[] += 1)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements
            while n !== nothing
                count_slices(n.value); n = n.next
            end
        else
            foreach(count_slices, elements)
        end
    elseif node isa GraphicsViewport
        count_slices(node.content)
    end
end
count_slices(io.output)
@test slices[] == 3 * 3 * 4 - 1

# ── A drag in a chart zooms it ──────────────────────────────────────────────

# The parts of the drag come back to the chart in its cell by the path of the
# chart. So the band grows from the point of the press to the pointer, and the
# release zooms the chart to the band.
charted = make_pivot_table(make_pivot_sales_rows(); rows = ["region", "country"], columns = ["year"],
                           cells = ["quarter"], measures = [PivotMeasure("amount", :sum)])
getfield(charted, :cell_view)[] = PivotLineChartView()
editor, backend = _pz_editor(charted)
window_root() = _pz_force(_pz_force(_pz_force(get_iomap_output(editor.iomap)).windows)[1].content)
top, bottom = _pz_place(editor, "DE")[2], _pz_place(editor, "FR")[2]
lines_of_row() = [points for points in _pivot_lines(window_root()) if all(p -> top <= p[2] < bottom, points)]
before = argmin(points -> points[1][1], lines_of_row())
x, y = before[1][1] + 10, before[1][2] - 20
_pz_send!(editor, backend, MouseMove(x, y, MouseButtons(), _PZ_NONE; time = 6.0))
_pz_send!(editor, backend, MouseDown(:left, x, y, _PZ_NONE; time = 6.01))
_pz_send!(editor, backend, MouseMove(x + 20, y + 15, MouseButtons(:left), _PZ_NONE; time = 6.1))
@test (x, y, 20, 15) in _pivot_boxes(window_root())
_pz_send!(editor, backend, MouseUp(:left, x + 20, y + 15, _PZ_NONE; time = 6.2))
@test !((x, y, 20, 15) in _pivot_boxes(window_root()))
@test !(before in lines_of_row())

end
end

# The points of each line under `node`, and the box of each rectangle, in the
# coordinates of the window.
_pivot_lines(node) = [[(x + Int(p[1]), y + Int(p[2])) for p in line.points]
                      for (x, y, line) in _pivot_nodes(node, GraphicsPolyline) if !isempty(line.points)]
_pivot_boxes(node) = [(x + Int(box.x), y + Int(box.y), Int(box.w), Int(box.h))
                      for (x, y, box) in _pivot_nodes(node, GraphicsRect)]

# Each node of type `T` under `node`, with the place in the window of the canvas
# that holds it.
function _pivot_nodes(node, T, ox = 0, oy = 0, found = Any[])
    node isa T && push!(found, (ox, oy, node))
    if node isa GraphicsCanvas
        x, y = ox + Int(node.x), oy + Int(node.y)
        elements = node.elements
        if elements isa ListNode
            n = elements
            while n !== nothing
                _pivot_nodes(n.value, T, x, y, found); n = n.next
            end
        else
            foreach(element -> _pivot_nodes(element, T, x, y, found), elements)
        end
    elseif node isa GraphicsViewport
        _pivot_nodes(node.content, T, ox + Int(node.x), oy + Int(node.y), found)
    end
    found
end
