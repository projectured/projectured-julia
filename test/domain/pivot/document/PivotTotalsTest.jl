"""
The totals and the order of a pivot: the subtotal rows, the total row and the
total column and their parts, a closed run, the order by a measure, the first N
values, the key that opens and closes a run, and the menu of a dimension.
"""

function test_pivot_totals()
@testset "the totals and the order of a pivot" begin

sales = make_pivot_sales_rows()
total = PivotTotal()
sum_of(rows) = sum(sales[r].amount for r in rows)

# ── Totals ─────────────────────────────────────────────────────────────────

pivot = make_pivot_table(sales; rows = ["region", "country"], columns = ["year"],
                         measures = [PivotMeasure("amount", :sum)], totals = true)
cross = pivot.cross_table
@test cross.row_keys == [("EU", "DE"), ("EU", "FR"), ("EU", total), ("US", "CA"), ("US", "NY"), ("US", total),
                         (total, total)]
@test cross.column_keys == [(2024,), (2025,), (total,)]
@test sum_of(find_pivot_part_rows(cross, ("EU", total), (2024,))) == 60 + 100
@test length(find_pivot_part_rows(cross, ("EU", total), (total,))) == 16
@test find_pivot_part_rows(cross, (total, total), (total,)) == 1:32
@test sum_of(find_pivot_part_rows(cross, ("EU", "DE"), (total,))) == 60 + 80
@test format_pivot_value(total) == "total"

# A closed run shows only its subtotal row, with or without the totals.
getfield(pivot, :collapsed)[] = Any[("EU",)]
@test pivot.cross_table.row_keys == [("EU", total), ("US", "CA"), ("US", "NY"), ("US", total), (total, total)]
getfield(pivot, :totals)[] = false
@test pivot.cross_table.row_keys == [("EU", total), ("US", "CA"), ("US", "NY")]
@test pivot.cross_table.column_keys == [(2024,), (2025,)]
@test [label.content for label in PivotModule._make_pivot_row_labels(pivot, ("EU", total))] == ["▸ EU", "total"]
@test [label.content for label in PivotModule._make_pivot_row_labels(pivot, ("US", "CA"))] == ["US", "CA"]

# ── The order by a measure, and the first N values ─────────────────────────

by_measure = make_pivot_table(sales; rows = ["country"], measures = [PivotMeasure("amount", :sum)])
by_measure.row_dimensions[1].order = :measure
by_measure.row_dimensions[1].descending = true
@test by_measure.cross_table.row_keys == [("NY",), ("CA",), ("FR",), ("DE",)]
by_measure.row_dimensions[1].limit = 2
@test by_measure.cross_table.row_keys == [("NY",), ("CA",)]
@test all(sales[r].country in ("NY", "CA") for r in find_pivot_part_rows(by_measure.cross_table, 1, 1))
by_measure.row_dimensions[1].order = :natural
by_measure.row_dimensions[1].descending = false
@test by_measure.cross_table.row_keys == [("CA",), ("DE",)]

# ── Enter opens and closes a run ────────────────────────────────────────────

pivot = make_pivot_document_example()
projection = PivotTableToWidget()
run_path(row, level) = ConcreteReference(ProjectionReferenceStep(projection, PivotModule._make_pivot_grid_reference(2,
    ConcreteReference(FieldReferenceStep("row_headers"), ConcreteReference(RangeReferenceStep(row - 1, row),
        ConcreteReference(RangeReferenceStep(level - 1, level), EmptyReference()))))), EmptyReference())
replace_selection!(pivot, run_path(3, 1))     # the run of US
toggle = PivotModule._make_pivot_run_toggle(pivot)
evaluate_operation(nothing, toggle.operations[1])
@test pivot.collapsed == Any[("US",)]
@test pivot.cross_table.row_keys == [("EU", "DE"), ("EU", "FR"), ("US", total)]
@test toggle.operations[2].path == run_path(3, 1)
replace_selection!(pivot, run_path(3, 1))
evaluate_operation(nothing, PivotModule._make_pivot_run_toggle(pivot).operations[1])
@test isempty(pivot.collapsed)
# The last level has no run to close.
replace_selection!(pivot, run_path(1, 2))
@test PivotModule._make_pivot_run_toggle(pivot) === nothing

# ── The menu of a dimension ─────────────────────────────────────────────────

menu = compute_context_menu(pivot)
labels = [item isa WidgetMenuItem ? item.action.label : "—" for item in menu.elements]
@test "Show the totals" in labels && !("Order by value" in labels)
getfield(pivot, :mouse_target)[] = PivotModule._make_pivot_zone_item_path("row_dimensions", 1)
menu = compute_context_menu(pivot)
labels = [item isa WidgetMenuItem ? item.action.label : "—" for item in menu.elements]
@test labels[1:7] == ["Order by value", "Order by first occurrence", "Order by the measure", "Descending",
                      "Show the first 5", "Show the first 10", "Show every value"]
@test "✓ EU" in labels && "✓ US" in labels
hide = menu.elements[findfirst(==("✓ EU"), labels)]
evaluate_operation(nothing, hide.operation)
@test pivot.row_dimensions[1].hidden_values == Any["EU"]
@test pivot.cross_table.row_keys == [("US", "CA"), ("US", "NY")]
evaluate_operation(nothing, menu.elements[findfirst(==("Show the totals"), labels)].operation)
@test pivot.totals

# ── The view shows the totals ───────────────────────────────────────────────

natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(500)))
shown = make_pivot_table(sales; rows = ["region", "country"], columns = ["year"],
                         measures = [PivotMeasure("amount", :sum)], totals = true)
drawn = [t[3] for t in _pivot_texts(print_document(natural, nothing, shown, context).output)]
@test count(==("total"), drawn) >= 4
@test format_pivot_value(sum(row.amount for row in sales)) in drawn

end
end
