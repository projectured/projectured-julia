# Table examples build a `WidgetTable` (the single table abstraction) whose cells
# are domain documents recursed by the projection. The first variant uses JSON
# cells; the second uses Primitive / Math cells.

function make_table_document_example()
    WidgetTable(Point2D(40, 40),
        # column headers
        Any[JsonString("Name"), JsonString("Age"), JsonString("City")],
        # row headers (none)
        Any[],
        # body rows (each a vector of document cells)
        Any[
            Any[JsonString("Jennifer"), JsonNumber(30), JsonString("New York")],
            Any[JsonString("Bob"),      JsonNumber(25), JsonString("Springfield")],
            Any[JsonString("Carol"),    JsonNumber(42), JsonString("Metropolis")],
        ],
        3)                       # column_count
end

function make_math_table_document_example()
    WidgetTable(Point2D(40, 40),
        # column headers
        Any[PrimitiveString("A"), PrimitiveString("B"), PrimitiveString("C")],
        # row headers
        Any[PrimitiveString("1"), PrimitiveString("2"), PrimitiveString("3")],
        # body rows
        Any[
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
        3)
end
