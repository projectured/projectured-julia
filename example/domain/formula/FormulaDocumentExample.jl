function make_formula_document_example()
    # A sheet in which a formula refers to another by its name. Each row shows one
    # feature to try: change `A`, and every formula that reads it computes again.
    env = FormulaEnvironment([
        FormulaFormula("A", parse_julia("42")),
        FormulaFormula("B", parse_julia("13")),
        FormulaFormula("C", parse_julia("A + B")),
        # A value can be any value, here a vector.
        FormulaFormula("V", parse_julia("[1, 2, 3]")),
        FormulaFormula("W", parse_julia("V .* A")),
        # A function value, and a callee that is a formula of the sheet.
        FormulaFormula("F", parse_julia("x -> x^2")),
        FormulaFormula("G", parse_julia("F(3)")),
        # The `x` of the lambda is local, and only `A` is a dependency.
        FormulaFormula("S", parse_julia("sum(x -> x * A, 1:3)")),
        # A name that resolves to nothing is an error.
        FormulaFormula("E", parse_julia("A + Z")),
        # Two formulas that read each other are a cycle.
        FormulaFormula("H", parse_julia("2 * K")),
        FormulaFormula("K", parse_julia("H + 1")),
    ])
    set_selection!(env, @reference(env, formulas[1]))
end

# Atomic documents for the catalog.
make_formula_formula_document_example()     = FormulaFormula("A1", parse_julia("10"))
make_formula_environment_document_example() = FormulaEnvironment([make_formula_formula_document_example()])
make_formula_insertion_document_example()   = FormulaInsertion(value = "42")
