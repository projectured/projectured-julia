# The documents of the pivot examples: a small table of sales, as a vector of
# named tuples, and a pivot of it.

"""
    make_pivot_sales_rows() -> Vector{NamedTuple}

Thirty-two sales: four countries in two regions, two years, four quarters, and
two products. The amounts follow a fixed rule, so every run gives the same table.
"""
function make_pivot_sales_rows()
    places = [("EU", "DE"), ("EU", "FR"), ("US", "CA"), ("US", "NY")]
    rows = NamedTuple{(:region, :country, :year, :quarter, :product, :amount),
                      Tuple{String,String,Int,String,String,Float64}}[]
    for (p, (region, country)) in enumerate(places), year in 2024:2025, quarter in 1:4
        product = isodd(p + quarter) ? "bike" : "car"
        amount = 10.0 * p + 2.0 * quarter + (year - 2024) * 5.0
        push!(rows, (region = region, country = country, year = year, quarter = "Q$quarter",
                     product = product, amount = amount))
    end
    rows
end

"""
    make_pivot_document_example() -> PivotTable

The sales of [`make_pivot_sales_rows`](@ref) by region and country down, by year
across, with the sum of the amounts in each cell.
"""
make_pivot_document_example() =
    make_pivot_table(make_pivot_sales_rows(); rows = ["region", "country"], columns = ["year"],
                     measures = [PivotMeasure("amount", :sum)])

"""
    make_pivot_pane_document_example() -> WidgetScrollPane

The pivot of [`make_pivot_document_example`](@ref) in a scroll pane of a fixed
size. The table of a pivot scrolls its own rows, so it needs an offered height,
and the pane gives it one wherever the pivot is drawn.
"""
make_pivot_pane_document_example() = WidgetScrollPane(make_pivot_document_example(); size = Point2D(820, 420))

"""
    make_pivot_part_table_document_example() -> PivotPartTable

Three rows of the sales, in three of their columns: what a cell of the rows view
of a pivot shows.
"""
make_pivot_part_table_document_example() =
    PivotPartTable(make_table_part(make_pivot_sales_rows(), [1, 9, 17]), ["country", "quarter", "amount"])

"""
    make_pivot_chart_cell_document_example() -> PivotChartCell

A bar chart of three categories, as a cell of a pivot shows it.
"""
make_pivot_chart_cell_document_example() =
    PivotChartCell(Chart("", [ChartBarSeries("sum(amount)", [3.0, 5.0, 2.0])];
                         x_axis = ChartCategoryAxis(; categories = ["Q1", "Q2", "Q3"], show_labels = false),
                         legend = ChartLegend(; visible = false)))
