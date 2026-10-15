"""
    test_formula_grid()

The sheet as the grid of a spreadsheet (`FormulaEnvironmentToTable`): a formula
whose name is a cell name shows its stored value in that cell, a text without its
quotes, and a new value or a computation that runs shows in the cell.
"""
function test_formula_grid()
    @testset "FormulaEnvironmentToTable" begin
        env = make_formula_invoice_document_example()
        table = print_document(FormulaEnvironmentToTable(), nothing, env, PrinterContext()).output
        get_text(row, column) = table.cells[row][column].content
        @testset "a cell name places its formula" begin
            @test [header.content for header in table.column_headers] == ["A", "B", "C", "D"]
            @test [header.content for header in table.row_headers] == string.(1:7)
            @test get_text(1, 1) == "Item"                  # a text, without its quotes
            @test get_text(2, 4) == "22.0"                  # D2 = B2 * C2
            @test get_text(7, 4) == "55.8"                  # D7, the total
            @test get_text(5, 1) == ""                      # A5 names no formula
        end
        @testset "a new value shows in its cell" begin
            env.formulas[6].code = parse_julia("5")         # B2
            evaluate_operation(nothing, ComputeFormulasOperation(env))
            @test get_text(2, 4) == "27.5"
            @test get_text(7, 4) == "62.4"
            env.formulas[8].is_computing = true             # D2
            @test get_text(2, 4) == "27.5 ⋯"
        end
        @testset "a formula with another name is not in the grid" begin
            sheet = FormulaEnvironment([FormulaFormula("rate", parse_julia("0.04")),
                                        FormulaFormula("B2", parse_julia("rate * 100"))])
            evaluate_operation(nothing, ComputeFormulasOperation(sheet))
            grid = print_document(FormulaEnvironmentToTable(), nothing, sheet, PrinterContext()).output
            @test length(grid.column_headers) == 2 && length(grid.cells) == 2
            @test grid.cells[2][2].content == "4.0"
            @test grid.cells[1][1].content == ""
        end
        @testset "the grid draws" begin
            projection = make_formula_grid_projection_example()
            context = with_exact_size(PrinterContext(); width = Cell(Int32(800)), height = Cell(Int32(600)))
            texts = _formula_texts(print_document(projection, nothing, make_formula_invoice_document_example(),
                                                  context).output)
            @test "Pencils" in texts
            @test "55.8" in texts
        end
    end
end
