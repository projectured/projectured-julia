function make_math_document_example()
    # X = (3 * A + B) / 2
    document = MathAssignment(
        MathVariable("X"),
        MathBinaryOperation(:/,
            MathParenthesized(
                MathBinaryOperation(:+,
                    MathBinaryOperation(:*, PrimitiveNumber(3), MathVariable("A")),
                    MathVariable("B"))),
            PrimitiveNumber(2)))
    set_selection!(document, @reference target.name{1})
    document
end
