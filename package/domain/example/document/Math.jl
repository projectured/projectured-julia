# A bare math variable — the atomic math leaf, for the catalog.
function make_math_variable_document_example()
    MathVariable("x")
end

function make_math_document_example()
    # X = (3 * A + B) / 2
    MathAssignment(
        MathVariable("X"),
        MathBinaryOperation(:/,
            MathParenthesized(
                MathBinaryOperation(:+,
                    MathBinaryOperation(:*, PrimitiveNumber(3), MathVariable("A")),
                    MathVariable("B"))),
            PrimitiveNumber(2)))
end
