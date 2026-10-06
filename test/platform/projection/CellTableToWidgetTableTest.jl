# CellTableToWidgetTable: base CellTable → visual WidgetTable, cells wrapped as
# base Primitive documents (no domain Json dependency). Row 1 of the CellTable
# becomes the column headers; rows 2..n become the table body.

function test_cell_table_to_widget_table()
@testset "CellTableToWidgetTable" begin

    # row 1 = headers, rows 2..n = data (mixed String / number cells)
    ct = CellTable(["name" "age"; "Alice" 30; "Bob" 25])
    iomap = print_document(CellTableToWidgetTable(), nothing, ct, PrinterContext())
    wt = iomap.output

    @test wt isa WidgetTable
    @test get_widget_table_column_count(wt) == 2

    # column headers from row 1, Primitive-wrapped
    @test length(wt.column_headers) == 2
    @test wt.column_headers[1] isa PrimitiveString && wt.column_headers[1].value == "name"
    @test wt.column_headers[2] isa PrimitiveString && wt.column_headers[2].value == "age"

    # two data rows, each a CellVector of Primitive cells with the right types
    @test length(wt.cells) == 2
    row1 = wt.cells[1]
    @test length(row1) == 2
    @test row1[1] isa PrimitiveString && row1[1].value == "Alice"
    @test row1[2] isa PrimitiveNumber && row1[2].value == 30
    row2 = wt.cells[2]
    @test row2[1] isa PrimitiveString && row2[1].value == "Bob"
    @test row2[2] isa PrimitiveNumber && row2[2].value == 25

end

@testset "a point on a cell names the cell of the widget table, and no caret goes in" begin
    ct = CellTable(["name" "age"; "Alice" 30; "Bob" 25])
    view = CellTableToWidgetTable()
    # The renderer of the table view: the cells are primitive documents, printed
    # through the primitive, syntax, text and graphics chain.
    measure = FixedMeasure(10, 18, 6, 0)
    primitive = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            PrimitiveString => PrimitiveStringToSyntaxLeaf(),
            PrimitiveNumber => PrimitiveNumberToSyntaxLeaf())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure))
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = measure).dispatch,
        Pair{Type,Any}[PrimitiveDocument => primitive])))
    chain = ChainingProjection(view, renderer)
    iomap = print_document(chain, ct)
    view_iomap = iomap.step_iomaps[1][]
    cell = [FieldReferenceStep("cells"), RangeReferenceStep(0, 1), RangeReferenceStep(0, 1)]
    _goes_through_cell(path) =
        (steps = collect(get_reference_steps(strip_reference_types(path)));
         length(steps) >= 3 && steps[1:3] == cell)

    # The table has no part of the input under the point, so the default mapping
    # names the part of the widget table by an introduced reference, here in the
    # first cell of the first row.
    back = map_reference_backward(chain, iomap, PointReferenceStep(5, 55))
    @test is_introduced_reference(back, view)
    @test _goes_through_cell(find_introduced_path(view, back))
    # Only such a reference maps forward, so the part can be named again.
    @test _goes_through_cell(map_reference_forward(view, view_iomap, back))
    @test map_reference_forward(view, view_iomap, EmptyReference()) === nothing
end
end # test_cell_table_to_widget_table

export test_cell_table_to_widget_table
