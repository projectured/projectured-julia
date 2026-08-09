function make_math_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(MathToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The two-dimensional form: the math rules, plus the collection-to-stack rewrap
# so the example's list of formulas renders one under the other. Every element
# re-enters the same recursion, so a formula inside the stack is typeset by the
# math rules and anything else by whatever rule matches it.
function make_math_display_projection_example(; measure=truetype_measure_text)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        MathToGraphics(measure=measure).dispatch,
        Pair{Type,Any}[CellVector => ChainingProjection(CellVectorToVerticalLayout(gap=16),
                                                        VerticalLayoutToGraphicsCanvas())],
        LayoutToGraphics().dispatch)))
end
