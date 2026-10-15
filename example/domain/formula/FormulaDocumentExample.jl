function make_formula_document_example()
    # A sheet in which a formula refers to another by its name. Each row shows one
    # feature to try: change `A`, and every formula that reads it computes again;
    # type in the name `A`, and every use takes the new name; Ctrl+click a use of
    # `A`, and the name of `A` is selected.
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
        # A math formula refers to a Julia formula by the same name.
        FormulaFormula("D", parse_math("C/2")),
        # A name that resolves to nothing is an error.
        FormulaFormula("E", parse_julia("A + Z")),
        # Two formulas that read each other are a cycle.
        FormulaFormula("H", parse_julia("2 * K")),
        FormulaFormula("K", parse_julia("H + 1")),
    ])
    # The values, as a saved sheet holds them once computed; a window computes
    # them again when it opens the sheet.
    evaluate_operation(nothing, ComputeFormulasOperation(env))
    set_selection!(env, @reference(env, formulas[1]))
end

function make_formula_invoice_document_example()
    # An invoice as a spreadsheet holds it: each formula is a cell, named by its
    # column and its row. Row 1 holds the headings, rows 2 to 4 the items, column D
    # the total of each item, and rows 5 to 7 add them up. Change a quantity or a
    # price and press Enter: the total of its row, the subtotal, the tax and the
    # total compute again, each after the cells that it names. A quantity and a
    # price are math code, because a key edits math code and no literal of Julia.
    make_formula(name, code) = FormulaFormula(name, parse_julia(code))
    make_input(name, number) = FormulaFormula(name, parse_math(number))
    env = FormulaEnvironment([
        make_formula("A1", "\"Item\""),    make_formula("B1", "\"Quantity\""),
        make_formula("C1", "\"Price\""),   make_formula("D1", "\"Total\""),
        make_formula("A2", "\"Paper\""),   make_input("B2", "4"),
        make_input("C2", "5.5"),           make_formula("D2", "B2 * C2"),
        make_formula("A3", "\"Pencils\""), make_input("B3", "12"),
        make_input("C3", "0.8"),           make_formula("D3", "B3 * C3"),
        make_formula("A4", "\"Stapler\""), make_input("B4", "1"),
        make_input("C4", "14.9"),          make_formula("D4", "B4 * C4"),
        make_formula("C5", "\"Subtotal\""), make_formula("D5", "D2 + D3 + D4"),
        make_formula("C6", "\"Tax 20%\""),  make_formula("D6", "round(D5 * 0.2; digits = 2)"),
        make_formula("C7", "\"Total\""),    make_formula("D7", "D5 + D6"),
    ])
    evaluate_operation(nothing, ComputeFormulasOperation(env))
    set_selection!(env, @reference(env, formulas[6]))
end

function make_formula_queue_document_example()
    # The M/M/1 queue in the math notation: customers arrive at the rate λ, and one
    # server serves them at the rate μ. A name can be a Greek letter or carry a
    # subscript, and each formula reads the ones above it. Raise λ to 10 or more,
    # and the queue has no steady state: ρ reaches 1, and L and W are no longer
    # finite and positive.
    make_formula(name, code) = FormulaFormula(name, parse_math(code))
    env = FormulaEnvironment([
        make_formula("λ", "8"),
        make_formula("μ", "10"),
        make_formula("ρ", "λ/μ"),
        make_formula("P_{0}", "1 - ρ"),
        make_formula("L", "ρ/(1 - ρ)"),
        make_formula("L_{q}", "ρ^2/(1 - ρ)"),
        make_formula("W", "L/λ"),
        make_formula("W_{q}", "L_{q}/λ"),
    ])
    evaluate_operation(nothing, ComputeFormulasOperation(env))
    set_selection!(env, @reference(env, formulas[1]))
end

function make_formula_estimate_document_example()
    # Formulas that take a second or more: an estimate of π from random points in a
    # square, and an estimate of the Euler–Mascheroni constant from a harmonic sum.
    # The sheet holds no value when it is built, so the window computes each value
    # when it opens the sheet. While a formula computes, it shows `⋯` and the
    # editor answers every key. Change N and press Enter to compute them again; N
    # is math code, because a key edits math code and no literal of Julia.
    make_formula(name, code) = FormulaFormula(name, parse_julia(code))
    env = FormulaEnvironment([
        FormulaFormula("N", parse_math("200000000")),
        make_formula("hits", "count(i -> rand()^2 + rand()^2 < 1, 1:N)"),
        make_formula("pi_estimate", "4 * hits / N"),
        make_formula("pi_error", "abs(pi_estimate - pi)"),
        make_formula("harmonic", "sum(k -> 1 / k, 1:N)"),
        make_formula("gamma_estimate", "harmonic - log(N)"),
        make_formula("gamma_error", "abs(gamma_estimate - 0.5772156649015329)"),
    ])
    set_selection!(env, @reference(env, formulas[1]))
end

# Atomic documents for the catalog.
make_formula_formula_document_example()     = FormulaFormula("A1", parse_julia("10"))
make_formula_environment_document_example() = FormulaEnvironment([make_formula_formula_document_example()])
make_formula_insertion_document_example()   = FormulaInsertion(value = "42")
