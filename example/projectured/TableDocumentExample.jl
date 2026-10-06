# Table examples build a `WidgetTable` (the single table abstraction) whose cells
# are domain documents recursed by the projection. The first variant uses JSON
# cells; the second uses Primitive / Math cells.

function make_table_document_example()
    WidgetTable(;
        position = Point2D(40, 40), column_headers = Any[JsonString("Name"), JsonString("Age"), JsonString("City")],
        row_headers = Any[],
        # each body row is a vector of document cells
        cells = Any[
            Any[JsonString("Jennifer"), JsonNumber(30), JsonString("New York")],
            Any[JsonString("Bob"),      JsonNumber(25), JsonString("Springfield")],
            Any[JsonString("Carol"),    JsonNumber(42), JsonString("Metropolis")],
        ],
        column_count = 3)
end

function make_math_table_document_example()
    WidgetTable(;
        position = Point2D(40, 40), column_headers = Any[PrimitiveString("A"), PrimitiveString("B"), PrimitiveString("C")],
        row_headers = Any[PrimitiveString("1"), PrimitiveString("2"), PrimitiveString("3")],
        cells = Any[
            # row 1: plain numbers
            Any[PrimitiveNumber(10), PrimitiveNumber(20), PrimitiveNumber(30)],
            # row 2: math formulas
            Any[MathBinaryOperation(:+, MathVariable("A"), MathVariable("B")),
                MathBinaryOperation(:*, PrimitiveNumber(2), MathVariable("B")),
                MathBinaryOperation(:-, MathVariable("C"), PrimitiveNumber(5))],
            # row 3: more formulas
            Any[MathBinaryOperation(:/, MathVariable("A"), PrimitiveNumber(2)),
                MathBinaryOperation(:/, MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("C"))), PrimitiveNumber(2)),
                MathBinaryOperation(:*, PrimitiveNumber(3), MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("B"))))],
        ],
        column_count = 3)
end
