function make_formula_document_example()
    # A small sheet:
    #   A1 = 10
    #   B1 = 5
    #   A2 = A1 + B1   (cross-references A1 and B1; shown as :both)
    #   tax = A2 * 2   (a free-standing named formula referencing A2)
    a1 = FormulaFormula("A1", juliaparse("10"); display_mode=:both)
    b1 = FormulaFormula("B1", juliaparse("5"); display_mode=:both)

    # A2's body is `A1 + B1`, but the two operands are FormulaReferences (by
    # identity) rather than plain identifiers, so renaming A1/B1 updates the
    # rendered body and so evaluation binds the live values.
    a2 = FormulaFormula("A2",
        JuliaBinaryOp(:+, FormulaReference(a1), FormulaReference(b1));
        display_mode=:both)

    tax = FormulaFormula("tax",
        JuliaBinaryOp(:*, FormulaReference(a2), JuliaInteger(2));
        display_mode=:both)

    with_selection(FormulaEnvironment([a1, b1, a2, tax]), @reference formulas[1])
end
