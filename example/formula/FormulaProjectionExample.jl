function make_formula_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(FormulaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
