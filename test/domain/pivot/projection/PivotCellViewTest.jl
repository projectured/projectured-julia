"""
The views of a cell: the automatic choice, the rows of a part as a table, the
menus that choose a view and an aggregate, and the version of the source that an
edit in a cell moves.
"""

function test_pivot_cell_views()
@testset "the views of a cell" begin

sales = make_pivot_sales_rows()
pivot = make_pivot_table(sales; rows = ["region"], columns = ["year"], cells = ["country", "quarter", "amount"])

# ── The automatic choice ────────────────────────────────────────────────────

# Three cell dimensions are rows; no cell dimension is numbers.
@test get_pivot_cell_view(pivot) isa PivotRowsView
@test get_pivot_cell_view(make_pivot_document_example()) isa PivotNumberView
part = pivot.cells[1][1]
@test part isa PivotPartTable
@test part.columns == ["country", "quarter", "amount"]
@test get_table_row_count(part.part) == 8
@test get_table_value(part.part, 1, "country") == "DE"
# The document of a cell is kept while its rows and its columns stay.
@test pivot.cells[1][1] === part
getfield(pivot, :cell_view)[] = PivotRowsView()
getfield(pivot, :cell_dimensions)[] = CellVector(Any[PivotDimension("amount")])
@test pivot.cells[1][1] !== part
@test pivot.cells[1][1].columns == ["amount"]
getfield(pivot, :cell_view)[] = PivotNumberView()
@test pivot.cells[1][1] isa WidgetLabel

# ── The menus ───────────────────────────────────────────────────────────────

views = collect_pivot_cell_views()
@test PivotNumberView in views && PivotRowsView in views
menu = compute_context_menu(pivot)
items = [item for item in menu.elements if item isa WidgetMenuItem]
labels = [item.action.label for item in items]
@test labels[1] == "Show the totals"
@test "Show the cells automatically" in labels
@test "Show the cells as rows" in labels && "Show the cells as numbers" in labels
automatic = items[findfirst(==("Show the cells automatically"), labels)]
@test automatic.enabled
evaluate_operation(nothing, automatic.operation)
@test pivot.cell_view === nothing
measure = PivotMeasure("amount", :sum)
measure_menu = compute_context_menu(measure)
@test [item.action.label for item in measure_menu.elements] ==
      ["count", "sum(amount)", "mean(amount)", "minimum(amount)", "maximum(amount)", "distinct_count(amount)"]
@test !measure_menu.elements[2].enabled
evaluate_operation(nothing, measure_menu.elements[3].operation)
@test measure.aggregate === :mean
@test length(compute_context_menu(PivotMeasure("", :count)).elements) == 1

# ── A table of the rows of each part ────────────────────────────────────────

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context = with_exact_size(PrinterContext(); width = Cell(Int32(1000)), height = Cell(Int32(600)))
rows_pivot = make_pivot_table(sales; rows = ["region"], columns = ["year"], cells = ["country", "quarter", "amount"])
io = print_document(projection, nothing, rows_pivot, context)
drawn = [t[3] for t in _pivot_texts(io.output)]
@test "as rows (automatic)" in drawn
@test "quarter" in drawn && "Q1" in drawn && "8" in drawn     # a header, a value, the count of rows
@test !("\"quarter\"" in drawn)                               # a header is a label, not a string literal
@test count(==("2024"), drawn) == 1
table = _pivot_view_iomap(io).table
@test table.row_policy.preferred == _pivot_view_iomap(io).projection.row_height *
                                     get_pivot_cell_view_lines(PivotRowsView())

# ── An edit in a cell moves the version of the source ──────────────────────

@test !PivotModule._is_pivot_source_edit(ReplaceSelectionOperation(EmptyReference()))
@test !PivotModule._is_pivot_source_edit(CompoundOperation(Any[ReplaceSelectionOperation(EmptyReference())]))
@test PivotModule._is_pivot_source_edit(ReplaceReferencedValueOperation(nothing, EmptyReference(), 1))
view_iomap = _pivot_view_iomap(io)
edit = ReplaceReferencedValueOperation(sales[1], EmptyReference(), 1)
answer = read_intent(view_iomap.projection, nothing, Intent(KeyDown(:a, ModifierKeys(); time = 0.0), edit),
                     view_iomap)
@test answer isa Intent && answer.operation isa CompoundOperation
version = answer.operation.operations[end]
@test version isa ReplaceReferencedValueOperation && version.value == rows_pivot.source_version + 1

end
end
