using Test
using Projectured

# SQL document-model tests. Pure construction + render — no live DB needed.

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

        expected_sql =
            "SELECT sub.person_name, sub.person_age FROM " *
            "(SELECT p.name AS person_name, p.age AS person_age" *
            " FROM \"persons\" AS p WHERE p.name <> 'X') AS sub" *
            " WHERE sub.person_name <> 'X'"
        show_detail && @info "render_sql (before resolve):" render_sql(outer_stmt)
        @test render_sql(outer_stmt) == expected_sql

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

        # Bottom-up pass: inner scope resolved first, then outer
        resolve_sql_names!(outer_stmt)

        # Inner qualifiers bound to p_alias (canonical alias from persons AS p)
        @test p_name_ref.qualifier      === p_alias
        @test p_age_ref.qualifier       === p_alias
        @test inner_where_ref.qualifier === p_alias
        # Outer qualifiers bound to sub_alias (canonical alias from the subquery wrapper)
        @test outer_ref1.qualifier      === sub_alias
        @test outer_ref2.qualifier      === sub_alias
        @test outer_where_ref.qualifier === sub_alias
        @test subq_item.alias           === sub_alias

        show_detail && @info "render_sql (after resolve):" render_sql(outer_stmt)
        @test render_sql(outer_stmt) == expected_sql
    end
end

function test_sql_boolean_expression(; show_detail=false)
    @testset "SqlBooleanExpression" begin
        # scalar values
        @test render_sql(SqlScalarValue(42))      == "42"
        @test render_sql(SqlScalarValue("Alice"))  == "'Alice'"
        @test render_sql(SqlScalarValue(true))     == "TRUE"
        @test render_sql(SqlScalarValue(false))    == "FALSE"

        # comparison
        cmp_name = SqlComparison(SqlColumnReference("name"), "=",  SqlScalarValue("Alice"))
        cmp_age  = SqlComparison(SqlColumnReference("age"),  ">=", SqlScalarValue(18))
        @test render_sql(cmp_name) == "name = 'Alice'"
        @test render_sql(cmp_age)  == "age >= 18"

        # logical connectives
        @test render_sql(SqlAnd(cmp_name, cmp_age)) ==
              "(name = 'Alice' AND age >= 18)"
        @test render_sql(SqlOr(cmp_name, cmp_age)) ==
              "(name = 'Alice' OR age >= 18)"
        @test render_sql(SqlNot(cmp_age)) ==
              "(NOT age >= 18)"

        # nesting: (name = 'Alice' AND age >= 18) OR (NOT age >= 18)
        nested = SqlOr(SqlAnd(cmp_name, cmp_age), SqlNot(cmp_age))
        expected = "((name = 'Alice' AND age >= 18) OR (NOT age >= 18))"
        show_detail && @info "render_sql (nested boolean):" render_sql(nested)
        @test render_sql(nested) == expected

        # WHERE clause wrapping
        stmt = SqlSelectStatement(
            SqlSelectClause(SqlSelectItem(SqlAllColumns())),
            SqlFromClause(SqlFromItem(SqlTableExpression("persons"))),
            SqlWhereClause(SqlWhereFilterCondition(cmp_age)))
        expected_sql = "SELECT * FROM \"persons\" WHERE age >= 18"
        show_detail && @info "render_sql (with WHERE):" render_sql(stmt)
        @test render_sql(stmt) == expected_sql
    end
end

function test_sql_document(; show_detail=false)
    @testset "SqlDocument" begin
        test_sql_document_nested_select(show_detail=show_detail)
        test_sql_boolean_expression(show_detail=show_detail)
    end
end

export test_sql_document
