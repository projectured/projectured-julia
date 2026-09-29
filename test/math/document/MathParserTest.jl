# The reader of the linear form. The printer is the grammar: a line the
# printer writes reads back to a tree that prints the same line, and the
# tree it reads back equals the tree it came from wherever the printer added
# no parentheses of its own.

using ProjecturedMath.MathModule: parse_math, MathToSyntax, MathFile
using ProjecturedMath.MathModule: MathDocument, MathVariable, MathSymbol, MathText, MathSpace, MathRow,
                                  MathBinaryOperation, MathUnaryOperation, MathAssignment,
                                  MathParenthesized, MathFraction, MathScript, MathRadical,
                                  MathBigOperator, MathDifferential, MathDerivative, MathFunction,
                                  MathAccent, MathMatrix, MathCase, MathCases, MathInsertion
using ProjecturedNatural.NaturalModule: print_natural_text
using ProjecturedSerialization.SerializationModule: save_file!, load_file, get_file_content, emit_text
using ProjecturedPrimitive.PrimitiveModule: PrimitiveNumber
import ProjecturedMathExample

_linear(tree) = print_natural_text(tree)

# Two trees, field by field, with every cell read through.
function _math_equal(a, b)
    typeof(a).name === typeof(b).name || return false
    a isa Document || return a == b
    for name in fieldnames(typeof(a))
        is_view_state_field(name) && continue
        x = getfield(a, name); y = getfield(b, name)
        x = x isa AbstractCell ? x[] : x; y = y isa AbstractCell ? y[] : y
        if x isa CellVector || y isa CellVector
            xs = collect(x); ys = collect(y)
            length(xs) == length(ys) || return false
            all(_math_equal(u, v) for (u, v) in zip(xs, ys)) || return false
        elseif x isa Document || y isa Document
            (x isa Document && y isa Document) || return false
            _math_equal(x, y) || return false
        else
            x == y || return false
        end
    end
    true
end

# The builders of the corpus whose print holds no parentheses of the printer's
# own: their trees read back equal. The others read back to a tree with a
# `MathParenthesized` where the printer wrapped a numerator, a base or a body.
const _TREE_STABLE = Set([:accent, :assignment, :big_operator, :binary_operation, :cases, :derivative,
                          :differential, :fraction, :function, :insertion, :matrix, :parenthesized,
                          :radical, :row, :script, :shannon, :symbol, :unary_operation, :variable,
                          :reliability])

function test_math_parser()
@testset "the linear form reads back" begin
    @testset "every builder of the corpus prints, reads and prints the same line" begin
        seen = 0
        for name in names(ProjecturedMathExample)
            s = String(name)
            startswith(s, "make_math_") && endswith(s, "_document_example") || continue
            tree = getproperty(ProjecturedMathExample, name)()
            tree isa MathDocument || continue
            stem = Symbol(s[11:end - 17])
            stem in (:case, :text, :space) && continue   # stated below, one by one
            line = _linear(tree)
            back = parse_math(line)
            @test _linear(back) == line
            stem in _TREE_STABLE && @test _math_equal(back, tree)
            seen += 1
        end
        @test seen >= 25
    end

    @testset "what the reader decides where the line is ambiguous" begin
        # A word is text, a case outside a case list is not a line, a space is `\,`.
        @test parse_math("bit") isa MathText
        @test _linear(parse_math("sin x")) == "sin x"
        @test parse_math("sin x") isa MathRow
        @test parse_math("a \\, b") isa MathRow && collect(parse_math("a \\, b").elements)[2] isa MathSpace
        @test _linear(MathSpace(:thin)) == "\\,"
        @test !(parse_math("1 if x < n") isa MathCase)
        # `/` without a space is a fraction; ` / ` with spaces is a division.
        @test parse_math("1/x") isa MathFraction
        @test parse_math("a / b") isa MathBinaryOperation
        # A fraction binds tighter than juxtaposition.
        row = parse_math("1/n x")
        @test row isa MathRow && collect(row.elements)[1] isa MathFraction
        # A name directly before `(` is a call; with a space it is juxtaposition.
        @test parse_math("f(x)") isa MathFunction
        @test parse_math("f (x)") isa MathRow
        @test parse_math("log_{2}(1 + x)") isa MathFunction && parse_math("log_{2}(1 + x)").base !== nothing
        # The printer's own parentheses read back as a node.
        @test parse_math("(a + b)^{2}").base isa MathParenthesized
        # A negative number is a number.
        @test parse_math("-2") isa PrimitiveNumber && parse_math("-2").value == -2
        @test parse_math("-x") isa MathUnaryOperation
    end

    @testset "a read is wider than a print" begin
        @test _linear(parse_math("ρ^n")) == "ρ^{n}"
        @test _linear(parse_math("\\rho^{n}")) == "ρ^{n}"
        @test _linear(parse_math("x_i^2")) == "x_{i}^{2}"
        @test _linear(parse_math("p_{block} = ((1 - ρ) ρ^n)/(1 - ρ^(n + 1))")) ==
              "p_{block} = ((1 - ρ) ρ^{n})/(1 - ρ^{(n + 1)})"
        @test _linear(parse_math("\\sum_{k = 0}^{n} (x/n)")) == "\\sum_{k = 0}^{n} (x/n)"
        @test _linear(parse_math("\\int_{0}^{\\infty} (x dt)")) == "\\int_{0}^{∞} (x dt)"
        @test _linear(parse_math("\\partial^2(P)/\\partial(t)^2")) == "\\partial^2(P)/\\partial(t)^2"
        @test _linear(parse_math("d(Q)/d(t)")) == "d(Q)/d(t)"
        @test _linear(parse_math("\\sqrt[3]{x}")) == "\\sqrt[3]{x}"
        @test _linear(parse_math("\\matrix[2]{1, 2, 3, 4}")) == "\\matrix[2]{1, 2, 3, 4}"
        @test _linear(parse_math("\\cases{1 if x < n; 0 otherwise}")) == "\\cases{1 if x < n; 0 otherwise}"
        @test _linear(parse_math("|x| + [y]")) == "|x| + [y]"
        @test _linear(parse_math("a \\cdot b \\times c")) == "a \\cdot b \\times c"
        @test _linear(parse_math("a <= b != c")) == "a <= b != c"
        @test _linear(parse_math("\\lim_{n -> ∞} (1/n)")) == "\\lim_{n -> ∞} (1/n)"
        @test _linear(parse_math("n!")) == "n!"
        @test _linear(parse_math("\\neg p")) == "\\neg p"
        @test _linear(parse_math("⌷")) == "⌷"
    end

    @testset "an error names its position, and nothing runs" begin
        @test_throws Exception parse_math("")
        message(text) = try parse_math(text); "" catch e; sprint(showerror, e) end
        @test occursin("position 9", message("a + b + "))
        @test occursin("unknown command", message("\\foo{x}"))
        @test occursin("position", message("(a + b"))
        @test occursin("one assignment", message("a = b = c"))
        # A shell command is text the reader cannot read; it is refused, and nothing runs.
        @test_throws Exception parse_math("run(`touch pwned`)")
        @test !isfile("pwned")
    end

    @testset "a .math file holds the line" begin
        directory = mktempdir()
        tree = parse_math("W = 1/(μ - λ)")
        @test save_file!(MathFile("queue.math", tree), directory) === true
        @test read(joinpath(directory, "queue.math"), String) == "W = 1/(μ - λ)\n"
        loaded = load_file(directory, "queue.math")
        @test loaded isa MathFile
        @test _math_equal(get_file_content(loaded), tree)
        @test emit_text(loaded) == "W = 1/(μ - λ)\n"
        rm(directory; recursive = true, force = true)
    end
end
end
