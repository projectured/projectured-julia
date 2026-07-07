function make_formula_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(FormulaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
