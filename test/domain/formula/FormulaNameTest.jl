# The free names of a formula: a name that the code binds itself is local and
# refers to no formula, and a callee is a name like any other.

_formula_names(text) = get_formula_names(parse_julia(text))

function test_formula_names()
@testset "the free names of a formula" begin

    @testset "a local name is not free" begin
        @test _formula_names("x -> x * A") == ["A"]
        @test _formula_names("(x, y = x + B) -> x + y") == ["B"]
        @test _formula_names("let t = A + 1, u = t; u * B end") == ["A", "B"]
        @test _formula_names("[x * A for x in V if x > B]") == ["V", "A", "B"]
        @test _formula_names("begin s = 0; for i in 1:N; s += i * A; end; s end") == ["N", "A"]
        @test _formula_names("map(V) do v; v + A end") == ["map", "V", "A"]
        @test _formula_names("begin f(x) = x + A; f(B) end") == ["A", "B"]
        @test _formula_names("begin function g(x) x * A end; g(B) end") == ["A", "B"]
        @test _formula_names("begin h(x::T) where {T <: Real} = x; h(A) end") == ["Real", "A"]
        @test _formula_names("try A catch e; e end") == ["A"]
        @test _formula_names("begin t = A; t + B end") == ["A", "B"]
    end

    @testset "a name that is no read is not free" begin
        # A field names a slot, and a keyword names a parameter of the callee.
        @test _formula_names("p.x + A") == ["p", "A"]
        @test _formula_names("f(A; k = B)") == ["f", "A", "B"]
        @test _formula_names("(a = A, b = 2)") == ["A"]
    end

    @testset "a callee is a name, and binds when the scope holds it" begin
        @test _formula_names("sqrt(rho) + exp(n)") == ["sqrt", "rho", "exp", "n"]
        sheet = FormulaEnvironment([
            FormulaFormula("F", parse_julia("x -> x^2")),
            FormulaFormula("G", parse_julia("F(3)")),
            FormulaFormula("rho", parse_julia("0.5")),
            FormulaFormula("H", parse_julia("sqrt(rho)")),
        ])
        F, G, rho, H = sheet.formulas
        @test get_formula_dependencies(G, sheet) == [F]
        @test get_formula_dependencies(H, sheet) == [rho]
        @test would_create_cycle(sheet, F, G)
    end

    @testset "a local name does not refer to the formula of that name" begin
        sheet = FormulaEnvironment([
            FormulaFormula("A", parse_julia("42")),
            FormulaFormula("x", parse_julia("1")),
            FormulaFormula("S", parse_julia("sum(x -> x * A, 1:3)")),
        ])
        A, x, S = sheet.formulas
        @test get_formula_names(S.code) == ["sum", "A"]
        @test get_formula_dependencies(S, sheet) == [A]
    end

    @testset "the name of a function formula holds its key and its parameter" begin
        parameter(name) = ProjecturedFormula.FormulaModule._find_formula_parameter(name)
        for (name, key, argument) in (("S_{pure}(G)", "S_pure", "G"), ("f(x)", "f", "x"),
                                      ("P_{block}(ρ)", "P_block", "rho"), ("S_{pure}", "S_pure", nothing),
                                      ("f(x, y)", "f(x, y)", nothing))
            @test get_formula_key(name) == key
            @test parameter(name) == argument
        end
    end

    @testset "the parameter of a function formula is no name of the sheet" begin
        sheet = FormulaEnvironment([
            FormulaFormula("G", parse_julia("3")),
            FormulaFormula("T", parse_julia("2")),
            FormulaFormula("S_{pure}(G)", parse_math("G exp(-2G) T")),
        ])
        G, T, S = sheet.formulas
        @test get_formula_names(S) == ["exp", "T"]
        @test get_formula_names(S.code) == ["G", "exp", "T"]
        @test get_formula_dependencies(S, sheet) == [T]
        @test resolve(sheet, "S_pure") === S && resolve(sheet, "S_{pure}(G)") === S
    end
end
end
