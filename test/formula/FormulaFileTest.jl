# What a formula owes its file: a sheet written as its own constructor reads
# back with the same results, and a name in a formula's code binds to the
# formula of that name in the sheet.

function _formula_file_result(formula)
    buffer = IOBuffer()
    for span in formula.result.elements
        span isa TextString && print(buffer, span.content)
    end
    String(take!(buffer))
end

function test_formula_file()
@testset "a formula and its file" begin
    register_pred_type!(FormulaFormula)
    register_pred_type!(FormulaEnvironment)

    @testset "a name in the code binds to the formula of that name" begin
        sheet = FormulaEnvironment([
            FormulaFormula("rho", parse_julia("0.8")),
            FormulaFormula("n", parse_julia("6")),
            FormulaFormula("p_block", parse_julia("(1 - rho) * rho^n / (1 - rho^(n + 1))")),
        ])
        p_block = sheet.formulas[3]
        @test get_formula_names(p_block.code) == ["rho", "n"]
        @test length(get_formula_dependencies(p_block, sheet)) == 2
        @test isapprox(parse(Float64, _formula_file_result(p_block)), 0.066341; atol = 1e-5)
        # A changed load changes every number below it.
        sheet.formulas[1].code = parse_julia("0.5")
        @test isapprox(parse(Float64, _formula_file_result(p_block)), 0.007874; atol = 1e-5)
        # A callee is a function and not a name of the sheet.
        @test get_formula_names(parse_julia("sqrt(rho) + exp(n)")) == ["rho", "n"]
        # A name the sheet does not hold is an error the result says.
        stray = FormulaFormula("stray", parse_julia("rho + missing_name"))
        push!(getfield(sheet, :formulas)[], Cell(stray))
        wire_result!(stray, sheet)
        @test startswith(_formula_file_result(stray), "#ERROR!")
        @test !would_create_cycle(sheet, p_block, sheet.formulas[1])
        @test would_create_cycle(sheet, sheet.formulas[1], p_block)
    end

    @testset "a sheet round-trips through its constructor" begin
        sheet = FormulaEnvironment([
            FormulaFormula("rho", parse_julia("0.8")),
            FormulaFormula("n", parse_julia("6")),
            FormulaFormula("p_block", parse_julia("(1 - rho) * rho^n / (1 - rho^(n + 1))");
                           display_mode = :result),
        ])
        text = print_pred_text(sheet)
        @test startswith(text, "FormulaEnvironment(")
        @test occursin("FormulaFormula(", text)
        @test occursin("code = \"0.8\"", text)
        @test occursin("display_mode = :result", text)
        @test !occursin("result", replace(text, "display_mode = :result" => ""))
        loaded = parse_pred_text(text)
        @test loaded isa FormulaEnvironment
        @test length(loaded.formulas) == 3
        @test loaded.formulas[3].name == "p_block"
        @test loaded.formulas[3].display_mode === :result
        @test isapprox(parse(Float64, _formula_file_result(loaded.formulas[3])), 0.066341; atol = 1e-5)
        # Byte stable: a second print of the loaded sheet is the same text.
        @test print_pred_text(loaded) == text
        # The positional form reads too.
        one = parse_pred_text("FormulaFormula(\"rho\", \"0.8\")")
        @test one isa FormulaFormula && one.name == "rho"
        # Code is text and nothing else.
        @test_throws Exception parse_pred_text("FormulaFormula(name = \"rho\", code = 1)")
    end
end
end
