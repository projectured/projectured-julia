"""
The derived dimensions of a pivot: the bins of a number, the year, the month and
the day of a date, the limit of a column dimension of many values, the badge
that says how many values it has, and the menu that offers its bins.
"""

function test_pivot_derived_dimensions()
@testset "the derived dimensions of a pivot" begin

sales = make_pivot_sales_rows()
none = PivotDimension[]

# ── The bins of a number ───────────────────────────────────────────────────

binned = compute_pivot_cross_table(sales, [PivotDimension("amount"; bin = 10)], none)
@test binned.row_keys == [(PivotBin(10, 20),), (PivotBin(20, 30),), (PivotBin(30, 40),), (PivotBin(40, 50),),
                          (PivotBin(50, 60),)]
@test format_pivot_value(PivotBin(10, 20)) == "10–20"
@test all(10 <= sales[r].amount < 20 for r in find_pivot_part_rows(binned, 1, 1))

# ── The parts of a date ────────────────────────────────────────────────────

Date = PivotModule.Dates.Date
days = (day = [Date(2024, 1, 5), Date(2024, 1, 20), Date(2024, 3, 1), Date(2025, 3, 2)], v = [1, 2, 3, 4])
by_month = compute_pivot_cross_table(days, [PivotDimension("day"; bin = :month)], none)
@test by_month.row_keys == [(PivotMonth(2024, 1),), (PivotMonth(2024, 3),), (PivotMonth(2025, 3),)]
@test find_pivot_part_rows(by_month, 1, 1) == [1, 2]
@test format_pivot_value(PivotMonth(2024, 1)) == "2024-01"
@test compute_pivot_cross_table(days, [PivotDimension("day"; bin = :year)], none).row_keys == [(2024,), (2025,)]
@test length(compute_pivot_cross_table(days, [PivotDimension("day"; bin = :day)], none).row_keys) == 4

# ── A column dimension of many values ──────────────────────────────────────

wide = (k = collect(1:500), v = ones(500))
pivot = make_pivot_table(wide; columns = ["k"])
@test get_pivot_column_count(pivot.cross_table) == 200
@test PivotModule._count_pivot_categories(pivot, pivot.column_dimensions[1]) == 500
projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(400)))
drawn = [t[3] for t in _pivot_texts(print_document(projection, nothing, pivot, context).output)]
@test "k (500 values)" in drawn

# The menu of the dimension offers its bins, and a bin makes few columns.
getfield(pivot, :mouse_target)[] = PivotModule._make_pivot_zone_item_path("column_dimensions", 1)
items = [item for item in compute_context_menu(pivot).elements if item isa WidgetMenuItem]
labels = [item.action.label for item in items]
@test "Bins of 50" in labels && "Bins of 500" in labels && !("No bins" in labels)
evaluate_operation(nothing, items[findfirst(==("Bins of 50"), labels)].operation)
@test pivot.column_dimensions[1].bin == 50
@test get_pivot_column_count(pivot.cross_table) == 11
items = [item for item in compute_context_menu(pivot).elements if item isa WidgetMenuItem]
@test "No bins" in [item.action.label for item in items]

end
end
