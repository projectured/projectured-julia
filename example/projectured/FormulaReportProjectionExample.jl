# The page of `make_formula_report_document_example`: the natural renderer stacks
# the blocks of the page, and draws each one through its own chain, the prose as
# rendered Markdown and the sheet as the text of its formulas. The sheet is the
# root of its own chain, so its reader reads every key in it: a key starts the
# edit mode of a formula, and Enter commits it and computes the sheet again.
make_formula_report_projection_example(; measure=FontFileMeasure()) =
    NaturalToGraphics(measure=measure, extra=Pair{Type,Any}[
        FormulaEnvironment => make_formula_projection_example(measure=measure),
    ])
