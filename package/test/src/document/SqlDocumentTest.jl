using Test
using Projectured

# SQL document-model tests. Pure construction + projection pipeline — no live DB needed.

# Helper: run the Sql→Syntax→Text→String pipeline to produce a plain String.
function _sql_text(doc)
    pipe = SequentialProjection(
        RecursiveProjection(SqlToSyntax()),
        RecursiveProjection(SyntaxToText()),
        RecursiveProjection(TextToString()))
    projection_print(pipe, doc).output[]
end

function test_sql_document_nested_select(; show_detail=false)
    @testset "SqlSelectStatement nested (persons subquery)" begin
        # Named variables needed for identity assertions after resolution
        p_alias         = SqlTableAlias("p")
        p_name_ref      = SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name"))
        p_age_ref       = SqlColumnReference(SqlTableAlias("p"), SqlColumnName("age"))
        inner_where_ref = SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name"))
        person_name_ca  = SqlColumnAlias("person_name")
        person_age_ca   = SqlColumnAlias("person_age")

        sub_alias       = SqlTableAlias("sub")
        outer_ref1      = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name"))
        outer_ref2      = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_age"))
        outer_where_ref = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name"))
        subq_item       = SqlSubqueryFromItem(
            SqlSelectStatement(
                SqlSelectClause(
                    SqlSelectItem(p_name_ref, person_name_ca),
                    SqlSelectItem(p_age_ref,  person_age_ca)),
                SqlFromClause(SqlFromItem(
                    SqlTableExpression(SqlTableName("persons"), p_alias))),
                SqlWhereClause(
                    SqlWhereFilterCondition(SqlComparison(inner_where_ref, "<>", SqlScalarValue("X"))))),
            sub_alias)

        outer_stmt = SqlSelectStatement(
            SqlSelectClause(
                SqlSelectItem(outer_ref1),
                SqlSelectItem(outer_ref2)),
            SqlFromClause(SqlFromItem(subq_item)),
            SqlWhereClause(
                SqlWhereFilterCondition(SqlComparison(outer_where_ref, "<>", SqlScalarValue("X")))))

        rendered = _sql_text(outer_stmt)
        show_detail && @info "sql pipeline (before resolve):" rendered
        @test occursin("SELECT", rendered)
        @test occursin("sub.person_name", rendered)
        @test occursin("sub.person_age", rendered)
        @test occursin("persons", rendered)
        @test occursin("WHERE", rendered)

        # Pre-resolution: walk top-to-bottom — every qualifier is a distinct object
        # Inner scope: each SqlTableAlias("p") was created inline → 3 unique objects,
        # none equal to p_alias or to each other
        @test p_name_ref.qualifier      !== p_alias
        @test p_age_ref.qualifier       !== p_alias
        @test inner_where_ref.qualifier !== p_alias
        @test p_name_ref.qualifier      !== p_age_ref.qualifier
        @test p_name_ref.qualifier      !== inner_where_ref.qualifier
        @test p_age_ref.qualifier       !== inner_where_ref.qualifier
        # Outer scope: each SqlTableAlias("sub") was created inline → 3 unique objects,
        # none equal to sub_alias or to each other
        @test outer_ref1.qualifier      !== sub_alias
        @test outer_ref2.qualifier      !== sub_alias
        @test outer_where_ref.qualifier !== sub_alias
        @test outer_ref1.qualifier      !== outer_ref2.qualifier
        @test outer_ref1.qualifier      !== outer_where_ref.qualifier
        @test outer_ref2.qualifier      !== outer_where_ref.qualifier
        # subq_item.alias was passed as sub_alias directly → already the canonical object
        @test subq_item.alias           === sub_alias
    end
end

function test_sql_boolean_expression(; show_detail=false)
    @testset "SqlBooleanExpression" begin
        # scalar values
        @test _sql_text(SqlScalarValue(42))      == "42"
        @test _sql_text(SqlScalarValue("Alice"))  == "'Alice'"
        @test _sql_text(SqlScalarValue(true))     == "TRUE"
        @test _sql_text(SqlScalarValue(false))    == "FALSE"

        # comparison
        cmp_name = SqlComparison(SqlColumnReference("name"), "=",  SqlScalarValue("Alice"))
        cmp_age  = SqlComparison(SqlColumnReference("age"),  ">=", SqlScalarValue(18))
        @test _sql_text(cmp_name) == "name = 'Alice'"
        @test _sql_text(cmp_age)  == "age >= 18"

        # logical connectives
        @test _sql_text(SqlAnd(cmp_name, cmp_age)) ==
              "(name = 'Alice' AND age >= 18)"
        @test _sql_text(SqlOr(cmp_name, cmp_age)) ==
              "(name = 'Alice' OR age >= 18)"
        @test _sql_text(SqlNot(cmp_age)) ==
              "(NOT age >= 18)"

        # nesting: (name = 'Alice' AND age >= 18) OR (NOT age >= 18)
        nested = SqlOr(SqlAnd(cmp_name, cmp_age), SqlNot(cmp_age))
        expected = "((name = 'Alice' AND age >= 18) OR (NOT age >= 18))"
        show_detail && @info "sql pipeline (nested boolean):" _sql_text(nested)
        @test _sql_text(nested) == expected

        # WHERE clause wrapping — pipeline output is multi-line
        stmt = SqlSelectStatement(
            SqlSelectClause(SqlSelectItem(SqlAllColumns())),
            SqlFromClause(SqlFromItem(SqlTableExpression("persons"))),
            SqlWhereClause(SqlWhereFilterCondition(cmp_age)))
        rendered = _sql_text(stmt)
        show_detail && @info "sql pipeline (with WHERE):" rendered
        @test occursin("SELECT", rendered)
        @test occursin("*", rendered)
        @test occursin("FROM", rendered)
        @test occursin("persons", rendered)
        @test occursin("WHERE", rendered)
        @test occursin("age >= 18", rendered)
    end
end

function test_sql_document(; show_detail=false)
    @testset "SqlDocument" begin
        test_sql_document_nested_select(show_detail=show_detail)
        test_sql_boolean_expression(show_detail=show_detail)
    end
end

export test_sql_document
