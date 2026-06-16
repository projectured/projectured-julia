using Test
using Projectured

# SqlToSyntax projection tests. Pure projection — no live DB needed.

function test_sql_to_syntax()
    @testset "SqlToSyntax" begin
        stmt = SqlSelectStatement("persons")

        # SqlToSyntax + SyntaxToText renders the display form
        pipe = SequentialProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()))
        out = projection_print(pipe, stmt).output
        @test join(s.content for s in out) == "SELECT \n  *\nFROM \n  persons\n"

        # Top-level dispatch produces a SyntaxNode
        node = projection_print(RecursiveProjection(SqlToSyntax()), stmt).output
        @test node isa SyntaxNode

        # Leaf projections produce SyntaxLeaf nodes
        @test projection_print(SqlAllColumnsToSyntaxLeaf(), SqlAllColumns()).output isa SyntaxLeaf
        @test projection_print(SqlTableExpressionToSyntaxLeaf(), SqlTableExpression("t")).output isa SyntaxLeaf
        @test projection_print(SqlColumnReferenceToSyntaxLeaf(), SqlColumnReference("id")).output isa SyntaxLeaf

        # Full pipeline (Sql→Syntax→Text→String) covers all types
        sql_pipe = SequentialProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql_text(doc) = projection_print(sql_pipe, doc).output[]

        @test sql_text(SqlAllColumns()) == "*"
        @test sql_text(SqlAllColumns(SqlTableAlias("t"))) == "t.*"
        @test sql_text(SqlColumnReference("id")) == "id"
        @test occursin("public", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("users", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("AS u", sql_text(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))))
        @test occursin("SELECT", sql_text(SqlSelectStatement("persons")))
        @test occursin("persons", sql_text(SqlSelectStatement("persons")))

        # Stubs compile
        @test SqlInsertStatement() isa SqlInsertStatement
        @test SqlUpdateStatement() isa SqlUpdateStatement
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
    proj = SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure))

    test_selection("SqlToSyntax nested", doc, proj)
end

export test_sql_to_syntax, test_sql_to_syntax_selection
