# The evaluation of a formula by name: the value is any value, the scope binds
# its names last, and an error or a cycle is a value that a dependent gives on.

_formula_sheet(pairs...) =
    FormulaEnvironment([FormulaFormula(name, parse_julia(code)) for (name, code) in pairs])

function test_formula_evaluation()
@testset "the evaluation of a formula by name" begin

    @testset "a value can be any value" begin
        sheet = _formula_sheet("A" => "42", "V" => "[1, 2, 3]", "W" => "V .* A")
        A, V, W = sheet.formulas
        @test get_formula_value(V) == [1, 2, 3]
        @test get_formula_value(W) == [42, 84, 126]
        A.code = parse_julia("2")
        @test get_formula_value(W) == [2, 4, 6]
    end

    @testset "a formula can hold a function, and a call of it is a dependency" begin
        sheet = _formula_sheet("F" => "x -> x^2", "G" => "F(3)")
        F, G = sheet.formulas
        @test get_formula_value(F) isa Function
        @test get_formula_value(G) == 9
        F.code = parse_julia("x -> x + 1")
        @test get_formula_value(G) == 4
    end

    @testset "a local name does not refer to the formula of that name" begin
        sheet = _formula_sheet("A" => "42", "x" => "1000", "S" => "sum(x -> x * A, 1:3)")
        @test get_formula_value(sheet.formulas[3]) == 252
    end

    @testset "the scope wins over a Julia global" begin
        sheet = _formula_sheet("pi" => "3", "C" => "pi * 2", "T" => "sqrt(16)")
        @test get_formula_value(sheet.formulas[2]) == 6
        @test get_formula_value(sheet.formulas[3]) == 4.0
    end

    @testset "a math formula refers to a Julia formula by the same name" begin
        sheet = FormulaEnvironment([FormulaFormula("C", parse_julia("55")),
                                    FormulaFormula("D", parse_math("C/2"))])
        @test get_formula_value(sheet.formulas[2]) == 27.5
    end

    @testset "an error is a value that a dependent gives on" begin
        sheet = _formula_sheet("A" => "42", "E" => "A + Z", "E2" => "E + 1")
        _, E, E2 = sheet.formulas
        @test get_formula_value(E) isa FormulaError
        @test startswith(get_formula_value(E).text, "#ERROR! UndefVarError")
        @test get_formula_value(E2) === get_formula_value(E)
        push!(getfield(sheet, :formulas)[], Cell(FormulaFormula("Z", parse_julia("1"))))
        wire_result!(sheet.formulas[4], sheet)
        @test get_formula_value(E) == 43
        @test get_formula_value(E2) == 44
    end

    @testset "a cycle shows in each formula of it, and ends when it is broken" begin
        sheet = _formula_sheet("H" => "2 * K", "K" => "H + 1", "A" => "A + 1")
        H, K, A = sheet.formulas
        @test get_formula_value(H) == FormulaError("#CYCLE!")
        @test get_formula_value(K) == FormulaError("#CYCLE!")
        @test get_formula_value(A) == FormulaError("#CYCLE!")
        K.code = parse_julia("5")
        @test get_formula_value(H) == 10
        @test get_formula_value(K) == 5
    end

    @testset "the view shows a value on one line" begin
        f2s = RecursiveProjection(FormulaToSyntax())
        sheet = _formula_sheet("V" => "[1, 2, 3]", "E" => "Z")
        V, E = sheet.formulas
        V.display_mode = :result
        @test render(print_document(f2s, V).output) == "[1, 2, 3]"
        E.display_mode = :result
        @test !occursin('\n', render(print_document(f2s, E).output))
    end
end
end
