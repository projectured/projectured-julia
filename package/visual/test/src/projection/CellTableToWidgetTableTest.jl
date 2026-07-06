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
    @test wt.column_count == 2

    # column headers from row 1, Primitive-wrapped
    @test length(wt.column_headers) == 2
    @test wt.column_headers[1] isa PrimitiveString && wt.column_headers[1].value == "name"
    @test wt.column_headers[2] isa PrimitiveString && wt.column_headers[2].value == "age"

    # two data rows, each a CellVector of Primitive cells with the right types
    @test length(wt.rows) == 2
    row1 = wt.rows[1]
    @test length(row1) == 2
    @test row1[1] isa PrimitiveString && row1[1].value == "Alice"
    @test row1[2] isa PrimitiveNumber && row1[2].value == 30
    row2 = wt.rows[2]
    @test row2[1] isa PrimitiveString && row2[1].value == "Bob"
    @test row2[2] isa PrimitiveNumber && row2[2].value == 25

end
end # test_cell_table_to_widget_table

export test_cell_table_to_widget_table
