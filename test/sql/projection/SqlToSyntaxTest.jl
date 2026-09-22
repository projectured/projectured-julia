using Test

# SqlToSyntax projection tests. Pure projection — no live DB needed.

function test_sql_to_syntax()
    @testset "SqlToSyntax" begin
        stmt = SqlSelectStatement("persons")

        # SqlToSyntax + SyntaxToText + TextToString renders the display form
        pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        @test print_document(pipe, stmt).output == "SELECT \n  *\nFROM \n  persons\n"

        # Top-level dispatch produces a SyntaxNode
        node = print_document(RecursiveProjection(SqlToSyntax()), stmt).output
        @test node isa SyntaxNode

        # Leaf projections produce SyntaxLeaf nodes
        @test print_document(SqlAllColumnsToSyntaxLeaf(), SqlAllColumns()).output isa SyntaxLeaf
        @test print_document(SqlTableExpressionToSyntaxLeaf(), SqlTableExpression("t")).output isa SyntaxLeaf
        @test print_document(SqlColumnReferenceToSyntaxLeaf(), SqlColumnReference("id")).output isa SyntaxLeaf

        # Full pipeline (Sql→Syntax→Text→String) covers all types
        sql_pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql_text(doc) = print_document(sql_pipe, doc).output

        @test sql_text(SqlAllColumns()) == "*"
        @test sql_text(SqlAllColumns(SqlTableAlias("t"))) == "t.*"
        @test sql_text(SqlColumnReference("id")) == "id"
        @test occursin("public", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("users", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("AS u", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("SELECT", sql_text(SqlSelectStatement("persons")))
        @test occursin("persons", sql_text(SqlSelectStatement("persons")))

        # Empty constructors still compile
        @test SqlInsertStatement() isa SqlInsertStatement
        @test SqlUpdateStatement() isa SqlUpdateStatement

        # INSERT renders single-line, with and without an explicit column list
        insert_doc = SqlInsertStatement(
            SqlTableName("persons"),
            [SqlColumnName("name"), SqlColumnName("age")],
            [SqlScalarValue("Ada"), SqlScalarValue(36)])
        @test sql_text(insert_doc) == "INSERT INTO persons (name, age) VALUES ('Ada', 36)"

        insert_no_cols = SqlInsertStatement(
            SqlTableName("persons"),
            SqlColumnName[],
            [SqlScalarValue("Ada"), SqlScalarValue(36)])
        @test sql_text(insert_no_cols) == "INSERT INTO persons VALUES ('Ada', 36)"

        # UPDATE renders single-line, with and without WHERE
        update_doc = SqlUpdateStatement(
            SqlTableName("persons"),
            [SqlUpdateAssignment(SqlColumnName("age"), SqlScalarValue(37))],
            SqlWhereClause(SqlWhereFilterCondition(SqlComparison(
                SqlColumnReference(SqlColumnName("name")), "=", SqlScalarValue("Ada")))))
        @test sql_text(update_doc) == "UPDATE persons SET age = 37 WHERE name = 'Ada'"

        update_no_where = SqlUpdateStatement(
            SqlTableName("persons"),
            [SqlUpdateAssignment(SqlColumnName("name"), SqlScalarValue("Ada")),
             SqlUpdateAssignment(SqlColumnName("age"), SqlScalarValue(37))])
        @test sql_text(update_no_where) == "UPDATE persons SET name = 'Ada', age = 37"

        # USING prints its column list in parentheses; a raw expression and a raw
        # condition print their text without quotes.
        @test sql_text(SqlJoinUsingCondition(SqlColumnName("id"), SqlColumnName("name"))) ==
              "USING (id, name)"
        @test sql_text(SqlRawExpression("COUNT(*)")) == "COUNT(*)"
        @test sql_text(SqlRawCondition("name LIKE 'A%'")) == "name LIKE 'A%'"
        @test sql_text(SqlWhereClause(SqlWhereFilterCondition(SqlRawCondition("a IN (1, 2)")))) ==
              "WHERE \n  a IN (1, 2)\n"

        # A statement list ends each statement with `;`. A DDL statement prints
        # its own, and the list adds one after any other statement.
        list = SqlStatementList([SqlSelectStatement("a"), SqlCreateSchemaStatement("s")])
        @test sql_text(list) == "SELECT \n  *\nFROM \n  a\n;\n\nCREATE SCHEMA s;"
    end
end

function test_sql_insert_update_selection()
    @testset "SqlToSyntax INSERT/UPDATE selection round-trip" begin
        proj = RecursiveProjection(SqlToSyntax())

        # INSERT: forward a doc reference to a syntax path, then back again.
        insert_doc = SqlInsertStatement(
            SqlTableName("persons"),
            [SqlColumnName("name"), SqlColumnName("age")],
            [SqlScalarValue("Ada"), SqlScalarValue(36)])
        iomap = print_document(proj, insert_doc)
        p = iomap.projection
        for path in (
                Reference(FieldReferenceStep("table")),
                Reference(FieldReferenceStep("columns"), ElementReferenceStep(2)),
                Reference(FieldReferenceStep("values"), ElementReferenceStep(1)))
            fwd = map_reference_forward(p, iomap, path)
            @test fwd !== nothing
            @test strip_reference_types(map_reference_backward(p, iomap, fwd)) == path
        end

        # UPDATE: assignment column, assignment value, and a WHERE sub-reference.
        update_doc = SqlUpdateStatement(
            SqlTableName("persons"),
            [SqlUpdateAssignment(SqlColumnName("age"), SqlScalarValue(37))],
            SqlWhereClause(SqlWhereFilterCondition(SqlComparison(
                SqlColumnReference(SqlColumnName("name")), "=", SqlScalarValue("Ada")))))
        uiomap = print_document(proj, update_doc)
        up = uiomap.projection
        for path in (
                Reference(FieldReferenceStep("table")),
                Reference(FieldReferenceStep("assignments"), ElementReferenceStep(1),
                              FieldReferenceStep("column_name")),
                Reference(FieldReferenceStep("assignments"), ElementReferenceStep(1),
                              FieldReferenceStep("value")),
                Reference(FieldReferenceStep("where_clause"), FieldReferenceStep("condition"),
                              FieldReferenceStep("expression"), FieldReferenceStep("left")))
            fwd = map_reference_forward(up, uiomap, path)
            @test fwd !== nothing
            @test strip_reference_types(map_reference_backward(up, uiomap, fwd)) == path
        end
    end
end

function test_sql_to_syntax_selection()
    doc = SqlSelectStatement(
        SqlSelectClause(
            SqlSelectItem(SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name"))),
            SqlSelectItem(SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_age")))),
        SqlFromClause(SqlFromItem(SqlSubqueryFromItem(
            SqlSelectStatement(
                SqlSelectClause(
                    SqlSelectItem(
                        SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name")),
                        SqlColumnAlias("person_name")),
                    SqlSelectItem(
                        SqlColumnReference(SqlTableAlias("p"), SqlColumnName("age")),
                        SqlColumnAlias("person_age"))),
                SqlFromClause(SqlFromItem(
                    SqlTableExpression(SqlTableName("persons"), SqlTableAlias("p")))),
                SqlWhereClause(
                    SqlWhereFilterCondition(SqlComparison(
                        SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name")),
                        "<>",
                        SqlScalarValue("X"))))),
            SqlTableAlias("sub")))),
        SqlWhereClause(
            SqlWhereFilterCondition(SqlComparison(
                SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")),
                "<>",
                SqlScalarValue("X")))))

    measure = (text, font) -> (length(text) * 10, 18)
    proj = ChainingProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure))

    test_position_navigation("SqlToSyntax nested", doc, proj)

    # A join with USING, an expression kept as raw text, and a list of statements.
    test_position_navigation("SqlToSyntax USING and a raw expression",
        parse_sql_text("SELECT COUNT(*) FROM a JOIN b USING (id, name)"), proj)
    test_position_navigation("SqlToSyntax statement list",
        parse_sql_text("SELECT * FROM a; CREATE SCHEMA s; SELECT * FROM b"), proj)
end

function test_sql_ddl()
    @testset "SqlToSyntax DDL (CREATE TABLE / SCHEMA)" begin
        sql_pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql_text(doc) = print_document(sql_pipe, doc).output

        # CREATE TABLE: multi-line, schema-qualified, indented column list.
        create_table = SqlCreateTableStatement(
            SqlTableName("public", "film"),
            [SqlColumnDefinition("title", "text"),
             SqlColumnDefinition("len", "integer")])
        @test sql_text(create_table) ==
            "CREATE TABLE public.film (\n  title text,\n  len integer\n);"

        # A single column definition on its own renders `<name> <type>`.
        @test sql_text(SqlColumnDefinition("id", "integer")) == "id integer"

        # CREATE SCHEMA: single line.
        @test sql_text(SqlCreateSchemaStatement("public")) == "CREATE SCHEMA public;"
    end
end

function test_sql_ddl_selection()
    @testset "SqlToSyntax DDL selection round-trip" begin
        proj = RecursiveProjection(SqlToSyntax())

        create_table = SqlCreateTableStatement(
            SqlTableName("public", "film"),
            [SqlColumnDefinition("title", "text"),
             SqlColumnDefinition("len", "integer")])
        iomap = print_document(proj, create_table)
        p = iomap.projection
        for path in (
                Reference(FieldReferenceStep("table_name")),
                Reference(FieldReferenceStep("columns"), ElementReferenceStep(1),
                              FieldReferenceStep("column_name")),
                Reference(FieldReferenceStep("columns"), ElementReferenceStep(2),
                              FieldReferenceStep("column_name")))
            fwd = map_reference_forward(p, iomap, path)
            @test fwd !== nothing
            @test strip_reference_types(map_reference_backward(p, iomap, fwd)) == path
        end

        # CREATE SCHEMA only maps the whole-statement (∅) selection.
        siomap = print_document(proj, SqlCreateSchemaStatement("public"))
        sp = siomap.projection
        @test strip_reference_types(map_reference_forward(sp, siomap, EmptyReference())) == EmptyReference()
    end
end

export test_sql_to_syntax, test_sql_to_syntax_selection, test_sql_insert_update_selection,
       test_sql_ddl, test_sql_ddl_selection
