function make_formula_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(FormulaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
