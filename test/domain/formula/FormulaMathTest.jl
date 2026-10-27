# A math tree read as a Julia expression, and a formula whose code is one.

_math_reading(tree) = strip(print_natural_text(convert_math_to_julia(tree)))

using ProjecturedMath.MathModule: parse_math

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

    @testset "a name before parentheses is a call or a product by what the name is" begin
        reading(line; functions = ()) = strip(print_natural_text(convert_math_to_julia(parse_math(line); functions)))
        @test reading("ρ(1 - ρ)") == "rho * (1 - rho)"
        @test reading("f(2)") == "f * 2"
        @test reading("f(2)"; functions = ["f", "S_pure"]) == "f(2)"
        @test reading("S_{pure}(0.5)"; functions = ["f", "S_pure"]) == "S_pure(0.5)"
        @test reading("S_{pure}(0.5)") == "S_pure * 0.5"
        @test reading("ρ(2)"; functions = ["rho"]) == "rho(2)"
        @test reading("exp(1)") == "exp(1)"
        @test reading("exp(1)"; functions = ["f"]) == "exp(1)"
        @test reading("exp(1)"; functions = ["exp"]) == "exp(1)"
        @test reading("erf(x)") == "erf * x"
        @test reading("log_{2}(8)") == "log(2, 8)"
        @test get_formula_names(convert_math_to_julia(parse_math("f(2)"))) == ["f"]
        @test get_formula_names(convert_math_to_julia(parse_math("f(2)"); functions = ["f"])) == ["f"]
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

    @testset "a sheet with math code round-trips as its linear form" begin
        sheet = FormulaEnvironment([
            FormulaFormula("ρ", parse_math("0.8")),
            FormulaFormula("n", parse_math("6")),
            FormulaFormula("p_{block}", parse_math("((1 - ρ) ρ^n)/(1 - ρ^(n + 1))")),
        ])
        @test isapprox(get_formula_value(sheet.formulas[3]), 0.066341; atol = 1e-5)
        text = print_pred_text(sheet)
        @test occursin("code = \"((1 - ρ) ρ^{n})/(1 - ρ^{(n + 1)})\"", text)
        @test occursin("notation = :math", text)
        @test !occursin("notation = :julia", text)
        loaded = parse_pred_text(text)
        @test loaded.formulas[3].code isa MathDocument
        @test loaded.formulas[1].code isa PrimitiveNumber && is_math_code(loaded.formulas[1].code)
        @test isapprox(get_formula_value(loaded.formulas[3]), 0.066341; atol = 1e-5)
        @test print_pred_text(loaded) == text
        # A Julia formula says so, and a mixed sheet reads both.
        mixed = parse_pred_text("FormulaEnvironment(formulas = [FormulaFormula(name = \"a\", code = \"2 * 3\", notation = :julia), FormulaFormula(name = \"b\", code = \"a^{2}\", notation = :math)])")
        @test get_formula_value(mixed.formulas[2]) == 36
        @test_throws Exception parse_pred_text("FormulaFormula(name = \"a\", code = \"1\", notation = :latex)")
    end

    @testset "a formula draws as its equation with its value" begin
        sheet = FormulaEnvironment([
            FormulaFormula("ρ", parse_math("0.8")),
            FormulaFormula("n", parse_math("6")),
            FormulaFormula("p_{block}", parse_math("((1 - ρ) ρ^n)/(1 - ρ^(n + 1))")),
            FormulaFormula("twice", parse_julia("2 * rho")),
        ])
        _compute_formula_sheet!(sheet)
        renderer = NaturalToGraphics(measure = FontFileMeasure())
        context = with_exact_size(PrinterContext();
                                  width = Cell(Int32(800)), height = Cell(Int32(600)))
        canvas = print_document(renderer, nothing, sheet, context).output
        texts = _formula_texts(canvas)
        @test any(t -> occursin("ρ", t), texts)               # the equation's symbol
        @test any(t -> occursin("block", t), texts)           # the subscript of the name
        @test any(t -> occursin("0.0663", t), texts)          # the value beside it
        @test any(t -> occursin("twice = 2 * rho = 1.6", t), texts)   # a Julia formula, one line
        # A changed input, computed again, redraws the value.
        sheet.formulas[1].code = parse_math("0.5")
        _compute_formula_sheet!(sheet)
        canvas = print_document(renderer, nothing, sheet, context).output
        @test any(t -> occursin("0.007874", t), _formula_texts(canvas))
    end

    @testset "the value stands on the baseline of the equation" begin
        sheet = _compute_formula_sheet!(FormulaEnvironment([FormulaFormula("T", parse_math("952/9600"))]))
        iomap = print_document(NaturalToGraphics(measure = FontFileMeasure()), nothing, only(sheet.formulas),
                               PrinterContext())
        # The row of the formula is the last stage of its chain: the equation and
        # the label of its value, each at its place.
        row = unwrap_cell(last(get_content_iomap(iomap).step_iomaps))
        (_, equation_y, equation), (_, label_y, label) = unwrap_cell(row.child_iomaps)
        baseline(y, child) = Int(unwrap_cell(y)) + find_first_baseline(child)
        @test baseline(equation_y, equation) == baseline(label_y, label)
        # The baseline is the axis of the fraction, below its numerator.
        @test Int(unwrap_cell(label_y)) > Int(unwrap_cell(equation_y))
    end
end
end

# Every text a printed canvas drew.
function _formula_texts(node, found = String[])
    if node isa GraphicsCanvas
        for element in node.elements
            _formula_texts(element, found)
        end
    elseif node isa GraphicsViewport
        _formula_texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, node.text)
    end
    found
end
