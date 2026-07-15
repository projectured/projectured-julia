# Atomic math leaves — one meaningful instance each, for the catalog.
make_math_variable_document_example()  = MathVariable("x")
make_math_insertion_document_example() = MathInsertion()

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
