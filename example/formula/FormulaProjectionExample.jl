function make_formula_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(FormulaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
