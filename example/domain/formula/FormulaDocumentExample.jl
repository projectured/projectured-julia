function make_formula_document_example()
    # A small sheet:
    #   A1 = 10
    #   B1 = 5
    #   A2 = A1 + B1   (cross-references A1 and B1; shown as :both)
    #   tax = A2 * 2   (a free-standing named formula referencing A2)
    a1 = FormulaFormula("A1", parse_julia("10"); display_mode=:both)
    b1 = FormulaFormula("B1", parse_julia("5"); display_mode=:both)

    # A2's body is `A1 + B1`, but the two operands are FormulaReferences (by
    # identity) rather than plain identifiers, so renaming A1/B1 updates the
    # rendered body and so evaluation binds the live values.
    a2 = FormulaFormula("A2",
        JuliaBinaryOperation(:+, FormulaReference(a1), FormulaReference(b1));
        display_mode=:both)

    tax = FormulaFormula("tax",
        JuliaBinaryOperation(:*, FormulaReference(a2), JuliaInteger(2));
        display_mode=:both)

    env = FormulaEnvironment([a1, b1, a2, tax])
    set_selection!(env, @reference(env, formulas[1]))
end

# Atomic documents for the catalog.
make_formula_formula_document_example()     = FormulaFormula("A1", parse_julia("10"))
make_formula_environment_document_example() = FormulaEnvironment([make_formula_formula_document_example()])
make_formula_insertion_document_example()   = FormulaInsertion(value = "42")
make_formula_reference_document_example()   = FormulaReference(make_formula_formula_document_example())
