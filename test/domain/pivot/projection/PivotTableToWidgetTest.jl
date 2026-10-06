"""
A pivot drawn through the natural renderer: the bar of its zones, a table whose
headers have one level for each dimension, and a cell that shows the measures
of its part. A press selects a row and a cell of the pivot, and a selection of
the pivot shows in the table.
"""

# Every text a canvas drew, as (x, y, text), through viewports and down a list.
function _pivot_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements; seen = 0
            while n !== nothing && seen < 50
                _pivot_texts(n.value, ox + Int(node.x), oy + Int(node.y), found)
                n = n.next; seen += 1
            end
        else
            for element in elements
                _pivot_texts(element, ox + Int(node.x), oy + Int(node.y), found)
            end
        end
    elseif node isa GraphicsViewport
        _pivot_texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        isempty(string(node.text)) || push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end

# The IO map of the pivot stage, and of its table.
_pivot_view_iomap(io) = io.step_iomaps[1][]
_pivot_table_of(io) = _pivot_view_iomap(io).table

function test_pivot_table_projection()
@testset "a pivot drawn as a bar and a table" begin

projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(800)), height = Cell(Int32(400)))
pivot = make_pivot_document_example()
io = print_document(projection, nothing, pivot, context())
found = _pivot_texts(io.output)
drawn = [t[3] for t in found]
place_of(label) = only(t for t in found if t[3] == label)

# ── The bar ──────────────────────────────────────────────────────────────────

for name in ("Fields", "Columns", "Rows", "Cells", "Values", "quarter", "product", "year", "sum(amount)")
    @test name in drawn
end
@test place_of("Fields")[2] < place_of("Columns")[2] < place_of("Rows")[2] < place_of("Values")[2]
@test place_of("Fields")[2] <= place_of("quarter")[2] < place_of("Columns")[2]

# ── The headers ──────────────────────────────────────────────────────────────

@test count(==("2024"), drawn) == 1 && count(==("2025"), drawn) == 1
@test count(==("EU"), drawn) == 1 && count(==("US"), drawn) == 1
@test all(country -> count(==(country), drawn) == 1, ["DE", "FR", "CA", "NY"])
@test count(==("region"), drawn) == 2     # the chip in the Rows row, and the corner
@test place_of("EU")[2] == place_of("DE")[2]

# ── The cells ────────────────────────────────────────────────────────────────

sales = make_pivot_sales_rows()
sum_of(country, year) = sum(row.amount for row in sales if row.country == country && row.year == year)
expected = format_pivot_value(sum_of("DE", 2024))
cell = only(t for t in found if t[3] == expected && t[2] == place_of("DE")[2])
@test cell[1] > place_of("DE")[1]
@test format_pivot_value(sum_of("NY", 2025)) in drawn

# The document of a cell is kept by its keys, and the path steps through it.
@test pivot.cells[1][1] === pivot.cells[1][1]
@test pivot.cells[1][1] isa WidgetLabel
@test length(pivot.cells[1]) == 2
@test_throws BoundsError pivot.cells[5]

# ── A press ──────────────────────────────────────────────────────────────────

press(x, y; alt = false) = begin
    change = read_intent(projection, nothing,
                         Intent(MouseClick(:left, x + 2, y + 2, ModifierKeys(alt = alt); time = 0.0), nothing), io)
    change isa Intent ? change.operation : change
end
cell_path(r, c) = ConcreteReference(FieldReferenceStep("cells"), ConcreteReference(RangeReferenceStep(r - 1, r),
    ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
row_path(r) = ConcreteReference(FieldReferenceStep("cells"),
    ConcreteReference(RangeReferenceStep(r - 1, r), EmptyReference()))
op = press(cell[1], cell[2])
@test op isa ReplaceSelectionOperation && strip_reference_types(op.path) == row_path(1)
op = press(cell[1], cell[2]; alt = true)
@test op isa ReplaceSelectionOperation && strip_reference_types(op.path) == cell_path(1, 1)
# A run of the row headers is a part of the table that the pivot does not name.
# An Alt+press selects it, and a plain press selects the row under the pointer.
us = place_of("US")
run_op = press(us[1], us[2]; alt = true)
@test run_op isa ReplaceSelectionOperation
@test strip_reference_types(run_op.path).head isa ProjectionReferenceStep
op = press(us[1], us[2])
@test op isa ReplaceSelectionOperation && strip_reference_types(op.path) == row_path(3)

# ── A selection of the pivot shows in the table ──────────────────────────────

table = _pivot_table_of(io)
replace_selection!(pivot, cell_path(2, 1))
@test strip_reference_types(table.selection) == cell_path(2, 1)
replace_selection!(pivot, row_path(3))
@test strip_reference_types(table.selection) ==
      ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(2, 3), EmptyReference()))
replace_selection!(pivot, run_op.path)
@test strip_reference_types(table.selection) ==
      ConcreteReference(FieldReferenceStep("row_headers"), ConcreteReference(RangeReferenceStep(2, 3),
          ConcreteReference(RangeReferenceStep(0, 1), EmptyReference())))

# ── A pivot with no dimension on an axis ────────────────────────────────────

flat = make_pivot_table(sales; rows = ["region"], measures = [PivotMeasure("amount", :sum), PivotMeasure("", :count)])
flat_found = [t[3] for t in _pivot_texts(print_document(projection, nothing, flat, context()).output)]
@test "sum(amount)  count" in flat_found
@test "EU" in flat_found
@test string(format_pivot_value(sum(row.amount for row in sales if row.region == "EU")), "  16") in flat_found
total = make_pivot_table(sales)
total_found = [t[3] for t in _pivot_texts(print_document(projection, nothing, total, context()).output)]
@test "all" in total_found
@test "count" in total_found
@test "32" in total_found

end
end
