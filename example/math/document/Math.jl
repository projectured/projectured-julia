# Atomic math leaves — one meaningful instance each, for the catalog.
make_math_variable_document_example()  = MathVariable("x")
make_math_insertion_document_example() = MathInsertion()
make_math_symbol_document_example()    = MathSymbol(:lambda)
make_math_text_document_example()      = MathText("bit/s")
make_math_space_document_example()     = MathSpace(:thin)

# Minimal non-empty compound (node) documents — one leaf child each, for the catalog.
make_math_binary_operation_document_example() = MathBinaryOperation(:+, MathVariable("a"), MathVariable("b"))
make_math_assignment_document_example()       = MathAssignment(MathVariable("x"), MathVariable("y"))
make_math_parenthesized_document_example()    = MathParenthesized(MathVariable("x"))
make_math_row_document_example()              = MathRow([MathVariable("k"), MathVariable("T"), MathVariable("B")])
make_math_unary_operation_document_example()  = MathUnaryOperation(:factorial, MathVariable("n"), true)
make_math_fraction_document_example()         = MathFraction(PrimitiveNumber(1), MathVariable("x"))
make_math_script_document_example()           = MathScript(MathVariable("x"); subscript=MathVariable("i"), superscript=PrimitiveNumber(2))
make_math_radical_document_example()          = MathRadical(MathVariable("x"))
make_math_big_operator_document_example()     = MathBigOperator(:sum, MathVariable("x"); lower=MathVariable("k"), upper=MathVariable("n"))
make_math_differential_document_example()     = MathDifferential(MathVariable("t"))
make_math_derivative_document_example()       = MathDerivative(MathVariable("P"), MathVariable("t"), 1, :partial)
make_math_function_document_example()         = MathFunction("sin", MathVariable("x"))
make_math_accent_document_example()           = MathAccent(MathVariable("L"), :bar)
make_math_matrix_document_example()           = MathMatrix([PrimitiveNumber(1), PrimitiveNumber(2), PrimitiveNumber(3), PrimitiveNumber(4)], 2)
make_math_case_document_example()             = MathCase(PrimitiveNumber(1), MathBinaryOperation(:lt, MathVariable("x"), MathVariable("n")))
make_math_cases_document_example()            = MathCases([make_math_case_document_example(), MathCase(PrimitiveNumber(0))])

function make_math_document_example()
    # X = (3 * A + B) / 2
    MathAssignment(
        MathVariable("X"),
        MathBinaryOperation(:/,
            MathParenthesized(
                MathBinaryOperation(:+,
                    MathBinaryOperation(:*, PrimitiveNumber(3), MathVariable("A")),
                    MathVariable("B"))),
            PrimitiveNumber(2)))
end

# ── The formulas of communication network simulation ─────────────────────────
#
# One per construct the two-dimensional renderer has to get right. Together they
# are what "enough of mathematics" means for this domain.

"Shannon capacity: `C = B log₂(1 + S/N)`. A function with a base, over a fraction."
make_math_shannon_document_example() =
    MathAssignment(MathVariable("C"),
        MathRow([MathVariable("B"),
                 MathFunction("log",
                     MathBinaryOperation(:+, PrimitiveNumber(1),
                         MathFraction(MathVariable("S"), MathVariable("N")));
                     base = PrimitiveNumber(2))]))

"Friis transmission: `P_r = P_t G_t G_r (λ/(4πd))²`. Subscripts, juxtaposition, a stretchy parenthesis."
make_math_friis_document_example() =
    MathAssignment(
        MathSubscript(MathVariable("P"), MathVariable("r")),
        MathRow([MathSubscript(MathVariable("P"), MathVariable("t")),
                 MathSubscript(MathVariable("G"), MathVariable("t")),
                 MathSubscript(MathVariable("G"), MathVariable("r")),
                 MathSuperscript(
                     MathParenthesized(
                         MathFraction(MathSymbol(:lambda),
                             MathRow([PrimitiveNumber(4), MathSymbol(:pi), MathVariable("d")]))),
                     PrimitiveNumber(2))]))

"M/M/1 waiting time: `W = 1/(μ − λ)`."
make_math_queue_document_example() =
    MathAssignment(MathVariable("W"),
        MathFraction(PrimitiveNumber(1),
            MathBinaryOperation(:-, MathSymbol(:mu), MathSymbol(:lambda))))

"Erlang B: `B = (Aⁿ/n!) / Σ_{k=0}^{n} Aᵏ/k!`. A nested fraction over a sum with two limits."
make_math_erlang_document_example() =
    MathAssignment(MathVariable("B"),
        MathFraction(
            MathFraction(MathSuperscript(MathVariable("A"), MathVariable("n")),
                         MathUnaryOperation(:factorial, MathVariable("n"), true)),
            MathBigOperator(:sum,
                MathFraction(MathSuperscript(MathVariable("A"), MathVariable("k")),
                             MathUnaryOperation(:factorial, MathVariable("k"), true));
                lower = MathAssignment(MathVariable("k"), PrimitiveNumber(0)),
                upper = MathVariable("n"))))

"Mean delay: `E(T) = ∫₀^∞ t f(t) dt`. An integral with side limits and a differential."
make_math_delay_document_example() =
    MathAssignment(
        MathFunction("E", MathVariable("T")),
        MathBigOperator(:integral,
            MathRow([MathVariable("t"), MathFunction("f", MathVariable("t")),
                     MathDifferential(MathVariable("t"))]);
            lower = PrimitiveNumber(0), upper = MathSymbol(:infty)))

"BPSK bit error rate: `P_b = Q(√(2 E_b/N₀))`. A radical inside a function."
make_math_error_rate_document_example() =
    MathAssignment(
        MathSubscript(MathVariable("P"), MathVariable("b")),
        MathFunction("Q",
            MathRadical(
                MathRow([PrimitiveNumber(2),
                         MathFraction(MathSubscript(MathVariable("E"), MathVariable("b")),
                                      MathSubscript(MathVariable("N"), PrimitiveNumber(0)))]))))

"Series reliability: `R = ∏_{i=1}^{n} (1 − p_i)`."
make_math_reliability_document_example() =
    MathAssignment(MathVariable("R"),
        MathBigOperator(:prod,
            MathParenthesized(
                MathBinaryOperation(:-, PrimitiveNumber(1),
                    MathSubscript(MathVariable("p"), MathVariable("i"))));
            lower = MathAssignment(MathVariable("i"), PrimitiveNumber(1)),
            upper = MathVariable("n")))

"Thermal noise: `N = k T B`, an upright name over a juxtaposition, and its mean `L̄ = λ W`."
make_math_noise_document_example() =
    MathAssignment(
        MathText("SNR"),
        MathFraction(MathVariable("P"),
            MathRow([MathVariable("k"), MathVariable("T"), MathVariable("B")])))

"Queue length by regime — a piecewise definition beside a matrix."
make_math_regime_document_example() =
    MathAssignment(
        MathAccent(MathVariable("L"), :bar),
        MathCases([
            MathCase(MathFraction(MathSymbol(:rho),
                                  MathBinaryOperation(:-, PrimitiveNumber(1), MathSymbol(:rho))),
                     MathBinaryOperation(:lt, MathSymbol(:rho), PrimitiveNumber(1))),
            MathCase(MathSymbol(:infty))]))

"""
Every formula above, stacked. This is the document the two-dimensional renderer
is judged on: each line exercises a different construct.
"""
make_math_display_document_example() =
    CellVector(Cell[Cell(make_math_shannon_document_example()),
                    Cell(make_math_friis_document_example()),
                    Cell(make_math_queue_document_example()),
                    Cell(make_math_erlang_document_example()),
                    Cell(make_math_delay_document_example()),
                    Cell(make_math_error_rate_document_example()),
                    Cell(make_math_reliability_document_example()),
                    Cell(make_math_noise_document_example()),
                    Cell(make_math_regime_document_example()),
                    Cell(make_math_derivative_document_example())])
