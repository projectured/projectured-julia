function make_formula_document_example()
    # A sheet in which a formula refers to another by its name: `C` reads `A` and
    # `B`, and a change of `A` computes `C` again.
    env = FormulaEnvironment([
        FormulaFormula("A", parse_julia("42")),
        FormulaFormula("B", parse_julia("13")),
        FormulaFormula("C", parse_julia("A + B")),
    ])
    set_selection!(env, @reference(env, formulas[1]))
end

# Atomic documents for the catalog.
make_formula_formula_document_example()     = FormulaFormula("A1", parse_julia("10"))
make_formula_environment_document_example() = FormulaEnvironment([make_formula_formula_document_example()])
make_formula_insertion_document_example()   = FormulaInsertion(value = "42")
