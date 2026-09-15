# A math tree read as a Julia expression, and a formula whose code is one.

_math_reading(tree) = strip(print_natural_text(convert_math_to_julia(tree)))

function test_formula_math()
@testset "a formula whose code is an equation" begin
    @testset "every builder of the math corpus converts or is refused by name" begin
        builders = [name for name in names(ProjecturedMathExample)
                    if startswith(String(name), "make_math_") && endswith(String(name), "_document_example")]
        @test length(builders) >= 20
        converted = 0
        refused = String[]
        for name in builders
            tree = getproperty(ProjecturedMathExample, name)()
            tree isa MathDocument || continue
            try
                convert_math_to_julia(tree)
                converted += 1
            catch e
                e isa MathReadingException || rethrow()
                push!(refused, sprint(showerror, e))
            end
        end
        @test converted >= 10
        @test all(message -> endswith(message, "has no value here"), refused)
        @test any(message -> occursin("derivative", message), refused)
    end

    @testset "the readings, one per rule" begin
        rho = MathSymbol(:rho); n = MathVariable("n"); one = PrimitiveNumber(1)
        blocking = MathFraction(
            MathRow([MathParenthesized(MathBinaryOperation(:-, one, rho)),
                     MathScript(rho; superscript = n)]),
            MathBinaryOperation(:-, PrimitiveNumber(1),
                MathScript(rho; superscript = MathBinaryOperation(:+, n, PrimitiveNumber(1)))))
        @test _math_reading(blocking) == "(1 - rho) * rho ^ n / (1 - rho ^ (n + 1))"
        @test _math_reading(MathScript(MathVariable("p"); subscript = MathText("block"))) == "p_block"
        @test _math_reading(MathScript(MathVariable("x"); subscript = MathVariable("i"), superscript = PrimitiveNumber(2))) == "x_i ^ 2"
        @test _math_reading(MathRow([MathVariable("k"), MathVariable("T"), MathVariable("B")])) == "k * T * B"
        @test _math_reading(MathRadical(MathVariable("x"))) == "sqrt(x)"
        @test _math_reading(MathRadical(; radicand = MathVariable("x"), index = PrimitiveNumber(3))) == "x ^ (1 / 3)"
        @test _math_reading(MathFunction("sin", MathVariable("x"))) == "sin(x)"
        @test _math_reading(MathFunction("log", MathVariable("x"); base = PrimitiveNumber(2))) == "log(2, x)"
        @test _math_reading(MathUnaryOperation(:factorial, MathVariable("n"), true)) == "factorial(n)"
        @test _math_reading(MathUnaryOperation(:-, MathVariable("x"), false)) == "-x"
        @test _math_reading(MathBinaryOperation(:cdot, MathVariable("a"), MathVariable("b"))) == "a * b"
        @test _math_reading(MathBinaryOperation(:le, MathVariable("a"), MathVariable("b"))) == "a <= b"
        @test _math_reading(MathAssignment(MathVariable("p"), MathVariable("q"))) == "q"
        summed = MathBigOperator(:sum, MathScript(MathVariable("k"); superscript = PrimitiveNumber(2));
                                 lower = MathAssignment(MathVariable("k"), PrimitiveNumber(0)),
                                 upper = MathVariable("n"))
        @test _math_reading(summed) == "sum((k) -> k ^ 2, 0:n)"
        cases = MathCases([MathCase(PrimitiveNumber(1), MathBinaryOperation(:lt, MathVariable("x"), MathVariable("n"))),
                           MathCase(PrimitiveNumber(0))])
        @test _math_reading(cases) == "ifelse(x < n, 1, 0)"
        @test _math_reading(MathSymbol(:infty)) == "Inf"
    end

    @testset "what is refused says why" begin
        @test_throws MathReadingException convert_math_to_julia(MathDerivative(MathVariable("P"), MathVariable("t"), 1, :partial))
        @test_throws MathReadingException convert_math_to_julia(MathBigOperator(:int, MathVariable("x")))
        @test_throws MathReadingException convert_math_to_julia(MathBigOperator(:sum, MathVariable("k"); lower = MathVariable("k"), upper = MathVariable("n")))
        @test_throws MathReadingException convert_math_to_julia(MathBinaryOperation(:cup, MathVariable("A"), MathVariable("B")))
        @test_throws MathReadingException convert_math_to_julia(MathText("bit/s"))
        message = try convert_math_to_julia(MathAccent(MathVariable("L"), :bar)); "" catch e; sprint(showerror, e) end
        @test message == "an accent has no value here"
    end

    @testset "a formula evaluates math code, and its names bind" begin
        rho = MathSymbol(:rho); n = MathVariable("n")
        blocking = MathFraction(
            MathRow([MathParenthesized(MathBinaryOperation(:-, PrimitiveNumber(1), rho)),
                     MathScript(rho; superscript = n)]),
            MathBinaryOperation(:-, PrimitiveNumber(1),
                MathScript(rho; superscript = MathBinaryOperation(:+, n, PrimitiveNumber(1)))))
        sheet = FormulaEnvironment([
            FormulaFormula("rho", parse_julia("0.8")),
            FormulaFormula("n", parse_julia("6")),
            FormulaFormula("p_block", blocking),
        ])
        p_block = sheet.formulas[3]
        @test get_formula_names(p_block.code) == ["rho", "n"]
        @test isapprox(get_formula_value(p_block), 0.066341; atol = 1e-5)
        sheet.formulas[2].code = parse_julia("4")
        @test isapprox(get_formula_value(p_block), 0.2 * 0.8^4 / (1 - 0.8^5); atol = 1e-9)
        # A tree with no reading is a result that says so.
        stray = FormulaFormula("stray", MathAccent(MathVariable("L"), :bar))
        push!(getfield(sheet, :formulas)[], Cell(stray))
        wire_result!(stray, sheet)
        @test occursin("has no value here", string(get_formula_value(stray)))
    end
end
end
