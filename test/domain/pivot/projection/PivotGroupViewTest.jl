"""
The group layout of a pivot: the rows of the source in the order of their
groups under the columns of the source, the headers that name each group once,
a closed group as one row, and the key that closes a group.
"""

function test_pivot_group_view()
@testset "the group layout of a pivot" begin

sales = make_pivot_sales_rows()
pivot = make_pivot_table(sales; rows = ["region", "country"], cell_view = PivotGroupView())
@test PivotModule._get_pivot_group_columns(pivot) == ["year", "quarter", "product", "amount"]
groups = PivotModule._get_pivot_group_rows(pivot)
@test last(groups.ends) == 32
@test PivotModule._find_pivot_group_row(groups, 1) == (1, 1)
@test PivotModule._find_pivot_group_row(groups, 9) == (2, 9)
@test PivotModule._get_pivot_table_row_key(pivot, 17) == ("US", "CA")
headers = PivotModule._make_pivot_group_header_list(pivot)
@test collect(headers.value) == ["EU", "DE", "1"]
@test collect(headers.next.value) == ["EU", "DE", "2"]
@test collect(PivotModule._make_pivot_group_corner(pivot)) == ["region", "country", "#"]

# ── The headers name each group once ────────────────────────────────────────

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(900)), height = Cell(Int32(700)))
drawn = [t[3] for t in _pivot_texts(print_document(projection, nothing, pivot, context).output)]
@test "as rows under their groups" in drawn
@test count(==("EU"), drawn) == 1 && count(==("DE"), drawn) == 1
@test "Q3" in drawn && "bike" in drawn && "#" in drawn

# ── A closed group is one row ───────────────────────────────────────────────

getfield(pivot, :collapsed)[] = Any[("EU", "DE")]
groups = PivotModule._get_pivot_group_rows(pivot)
@test last(groups.ends) == 25
@test PivotModule._find_pivot_group_row(groups, 1) == (1, nothing)
@test groups.held[1] == 8
@test collect(PivotModule._make_pivot_group_header_list(pivot).value) == ["EU", "▸ DE", ""]
rows = PivotModule._make_pivot_group_row_list(pivot)
@test rows.value[1].content == "8 rows"

# Enter on a selected group closes it, and the selection goes to its first row.
getfield(pivot, :collapsed)[] = Any[]
table_projection = PivotTableToWidget()
run_path(row, level) = ConcreteReference(ProjectionReferenceStep(table_projection,
    PivotModule._make_pivot_grid_reference(2, ConcreteReference(FieldReferenceStep("row_headers"),
        ConcreteReference(RangeReferenceStep(row - 1, row), ConcreteReference(RangeReferenceStep(level - 1, level),
            EmptyReference()))))), EmptyReference())
replace_selection!(pivot, run_path(11, 2))    # a row of FR
toggle = PivotModule._make_pivot_run_toggle(pivot)
evaluate_operation(nothing, toggle.operations[1])
@test pivot.collapsed == Any[("EU", "FR")]
@test toggle.operations[2].path == run_path(9, 2)
@test last(PivotModule._get_pivot_group_rows(pivot).ends) == 25

# With totals, a total is one row that counts its rows.
getfield(pivot, :collapsed)[] = Any[]
getfield(pivot, :totals)[] = true
groups = PivotModule._get_pivot_group_rows(pivot)
@test last(groups.ends) == 32 + 3
@test groups.held[end] == 32

end
end
