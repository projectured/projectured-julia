function make_formula_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(FormulaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The sheet as the grid of a spreadsheet: each cell shows the value of the formula
# that its name names, such as `B3`. The grid only shows the sheet; the view of
# `make_formula_projection_example` edits it.
make_formula_grid_projection_example(; measure=FontFileMeasure()) =
    ChainingProjection(FormulaEnvironmentToTable(),
                       NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20)))
