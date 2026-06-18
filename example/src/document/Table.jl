function make_table_document_example()
    TableTable(
        CellVector(TableRow(), TableRow(), TableRow(), TableRow()),
        CellVector(TableColumn(), TableColumn(), TableColumn()),
        CellVector(
            TableCell(JsonString("Name")),
            TableCell(JsonString("Age")),
            TableCell(JsonString("City")),
            TableCell(JsonString("Jennifer")),
            TableCell(JsonNumber(30)),
            TableCell(JsonString("New York")),
            TableCell(JsonString("Bob")),
            TableCell(JsonNumber(25)),
            TableCell(JsonString("Springfield")),
            TableCell(JsonString("Carol")),
            TableCell(JsonNumber(42)),
            TableCell(JsonString("Metropolis")),
        );
        padding=16,
    )
end

function make_math_table_document_example()
    TableTable(
        CellVector(
            TableRow(PrimitiveString("1")),
            TableRow(PrimitiveString("2")),
            TableRow(PrimitiveString("3")),
        ),
        CellVector(
            TableColumn(PrimitiveString("A")),
            TableColumn(PrimitiveString("B")),
            TableColumn(PrimitiveString("C")),
        ),
        CellVector(
            # row 1: plain numbers
            TableCell(PrimitiveNumber(10)),
            TableCell(PrimitiveNumber(20)),
            TableCell(PrimitiveNumber(30)),
            # row 2: math formulas
            TableCell(MathBinaryOperation(:+, MathVariable("A"), MathVariable("B"))),
            TableCell(MathBinaryOperation(:*, PrimitiveNumber(2), MathVariable("B"))),
            TableCell(MathBinaryOperation(:-, MathVariable("C"), PrimitiveNumber(5))),
            # row 3: more formulas
            TableCell(MathBinaryOperation(:/, MathVariable("A"), PrimitiveNumber(2))),
            TableCell(MathBinaryOperation(:/, MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("C"))), PrimitiveNumber(2))),
            TableCell(MathBinaryOperation(:*, PrimitiveNumber(3), MathParenthesized(MathBinaryOperation(:+, MathVariable("A"), MathVariable("B"))))),
        );
        padding=16,
    )
end
