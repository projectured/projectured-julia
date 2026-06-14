using Test
using Projectured

# SqlToSyntax projection tests. Pure projection — no live DB needed.

function test_sql_to_syntax()
    @testset "SqlToSyntax" begin
        stmt = SqlSelectStatement("persons")

        # Canonical executable SQL text
        @test render_sql(stmt) == "SELECT * FROM \"persons\""

        # SqlToSyntax + SyntaxToText renders the display form
        pipe = SequentialProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()))
        out = projection_print(pipe, stmt).output
        @test join(s.content for s in out) == "SELECT * FROM persons"

        # Top-level dispatch produces a SyntaxNode
        node = projection_print(RecursiveProjection(SqlToSyntax()), stmt).output
        @test node isa SyntaxNode

        # Leaf projections produce SyntaxLeaf nodes
        @test projection_print(SqlAllColumnsToSyntaxLeaf(), SqlAllColumns()).output isa SyntaxLeaf
        @test projection_print(SqlTableExpressionToSyntaxLeaf(), SqlTableExpression("t")).output isa SyntaxLeaf
        @test projection_print(SqlColumnReferenceToSyntaxLeaf(), SqlColumnReference("id")).output isa SyntaxLeaf

        # render_sql covers new types
        @test render_sql(SqlAllColumns()) == "*"
        @test render_sql(SqlAllColumns(SqlTableAlias("t"))) == "t.*"
        @test render_sql(SqlColumnReference("id")) == "id"
        @test render_sql(SqlTableExpression(SqlTableName("public", "users"), SqlTableAlias("u"))) ==
              "\"public\".\"users\" AS u"
        @test render_sql(SqlSelectStatement("persons")) == "SELECT * FROM \"persons\""

        # Stubs compile
        @test SqlInsertStatement() isa SqlInsertStatement
        @test SqlUpdateStatement() isa SqlUpdateStatement
    end
end

export test_sql_to_syntax
