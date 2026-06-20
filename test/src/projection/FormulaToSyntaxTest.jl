# Helper: read the flat string out of a TextText result document.
function _formula_result_string(result)
    buf = IOBuffer()
    for span in result
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
end

function test_formula_to_syntax()

@testset "column_letter / cell_name boundaries" begin
    @test column_letter(1) == "A"
    @test column_letter(2) == "B"
    @test column_letter(26) == "Z"
    @test column_letter(27) == "AA"
    @test column_letter(28) == "AB"
    @test column_letter(52) == "AZ"
    @test column_letter(53) == "BA"
    @test column_letter(702) == "ZZ"
    @test column_letter(703) == "AAA"
    @test cell_name(1, 1) == "A1"
    @test cell_name(2, 1) == "B1"
    @test cell_name(27, 3) == "AA3"
end

@testset "FormulaReference renders target name, tracks renames" begin
    target = FormulaFormula("A1", juliaparse("10"); display_mode=:code)
    ref = FormulaReference(target)
    f2s = RecursiveProjection(FormulaToSyntax())

    out = projection_print(f2s, ref).output
    rendered = Cell(() -> render(out))
    @test rendered[] == "A1"

    # Renaming the target updates every reference reactively (no rewrite).
    target.name = "B7"
    @test !isuptodate(rendered)
    @test rendered[] == "B7"
end

@testset "FormulaFormula view modes (code / result / both)" begin
    f2s = RecursiveProjection(FormulaToSyntax())
    env = FormulaEnvironment([FormulaFormula("A1", juliaparse("2 + 3"))])
    f = env.formulas[1]

    f.display_mode = :code
    @test render(projection_print(f2s, f).output) == "2 + 3"

    f.display_mode = :result
    @test render(projection_print(f2s, f).output) == "5"

    f.display_mode = :both
    both = render(projection_print(f2s, f).output)
    @test occursin("A1", both)
    @test occursin("2 + 3", both)
    @test occursin("=", both)
    @test occursin("5", both)
end

@testset "evaluation: A2 = A1 + B1, reactive recompute" begin
    a1code = juliaparse("10")  # a JuliaInteger
    b1code = juliaparse("5")
    a1 = FormulaFormula("A1", a1code)
    b1 = FormulaFormula("B1", b1code)
    a2 = FormulaFormula("A2", JuliaBinaryOp(:+, FormulaReference(a1), FormulaReference(b1)))
    env = FormulaEnvironment([a1, b1, a2])

    @test _formula_result_string(a1.result) == "10"
    @test _formula_result_string(b1.result) == "5"
    @test _formula_result_string(a2.result) == "15"

    # Editing A1 invalidates and recomputes A2 (reactive propagation through the
    # dependency's result cell).
    a1code.value = 100
    @test _formula_result_string(a1.result) == "100"
    @test _formula_result_string(a2.result) == "105"
end

@testset "cycle detection: would_create_cycle rejects A1 -> A2 -> A1" begin
    a1 = FormulaFormula("A1", JuliaInteger(1))
    a2 = FormulaFormula("A2", FormulaReference(a1))   # A2 -> A1
    env = FormulaEnvironment([a1, a2])

    @test formula_dependencies(a2) == FormulaFormula[a1]
    # Adding A1 -> A2 would close the cycle A1 -> A2 -> A1.
    @test would_create_cycle(env, a1, a2) == true
    # A self-reference is also a cycle.
    @test would_create_cycle(env, a1, a1) == true
    # An independent direction is fine.
    b1 = FormulaFormula("B1", JuliaInteger(7))
    env2 = FormulaEnvironment([a1, a2, b1])
    @test would_create_cycle(env2, a1, b1) == false
end

@testset "cycle safety net: evaluator returns an error result, no hang" begin
    # Force a genuine cycle past the static check by wiring references directly,
    # then assert the re-entry guard yields a marker rather than looping.
    a1 = FormulaFormula("A1", JuliaInteger(0))
    a2 = FormulaFormula("A2", JuliaInteger(0))
    a1.code = FormulaReference(a2)   # A1 -> A2
    a2.code = FormulaReference(a1)   # A2 -> A1  (cycle)
    env = FormulaEnvironment([a1, a2])
    s = _formula_result_string(a1.result)
    @test occursin("#CYCLE!", s) || occursin("#ERROR!", s)
end

@testset "FormulaEnvironment renders one formula per line" begin
    f2s = RecursiveProjection(FormulaToSyntax())
    env = FormulaEnvironment([
        FormulaFormula("A1", juliaparse("1"); display_mode=:result),
        FormulaFormula("B1", juliaparse("2"); display_mode=:result),
    ])
    rendered = render(projection_print(f2s, env).output)
    @test occursin("1", rendered)
    @test occursin("2", rendered)
    @test occursin("\n", rendered)
end

@testset "topological_order: dependencies before dependents" begin
    a1 = FormulaFormula("A1", JuliaInteger(1))
    a2 = FormulaFormula("A2", FormulaReference(a1))
    a3 = FormulaFormula("A3", FormulaReference(a2))
    env = FormulaEnvironment([a3, a2, a1])
    order = topological_order(env)
    @test findfirst(==(a1), order) < findfirst(==(a2), order)
    @test findfirst(==(a2), order) < findfirst(==(a3), order)
end

end # test_formula_to_syntax
