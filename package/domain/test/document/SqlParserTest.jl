using Test

# SqlParser tests — parser-only, no DB needed.

function test_sql_parser()
    @testset "SqlParser" begin
        # ── helper: parse and return the output document ──────────────
        parse(sql) = sqlparse(sql)

        # ── helper: normalize SQL for round-trip comparison ───────────
        normalize_sql(s) = begin
            s = replace(s, r"--[^\n]*" => "")        # line comments
            s = replace(s, r"/\*.*?\*/"s => "")       # block comments
            replace(strip(s), r"\s+" => " ")           # collapse whitespace
        end

        # ── helper: parse → Sql→Syntax→Text→String → normalize ───────
        sql_pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        roundtrip(stmt) = normalize_sql(print_document(sql_pipe, stmt).output[])

        # ── simplest case ─────────────────────────────────────────────
        @testset "SELECT * FROM table" begin
            sql = "SELECT * FROM persons"
            stmt = parse(sql)
            @test stmt isa SqlSelectStatement
            @test length(stmt.select_clause.items) == 1
            @test stmt.select_clause.items[1].expression isa SqlAllColumns
            @test length(stmt.from_clause.items) == 1
            @test stmt.from_clause.items[1].base_item.table_name.name == "persons"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── multi-column ──────────────────────────────────────────────
        @testset "multi-column SELECT" begin
            sql = "SELECT name, age FROM persons"
            stmt = parse(sql)
            @test length(stmt.select_clause.items) == 2
            @test stmt.select_clause.items[1].expression isa SqlColumnReference
            @test stmt.select_clause.items[1].expression.column_name.name == "name"
            @test stmt.select_clause.items[2].expression.column_name.name == "age"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── qualifier + alias ─────────────────────────────────────────
        @testset "qualifier and alias" begin
            sql = "SELECT p.name AS n FROM persons AS p"
            stmt = parse(sql)
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlColumnReference
            @test item.expression.qualifier.name == "p"
            @test item.column_alias.name == "n"
            @test stmt.from_clause.items[1].base_item.alias.name == "p"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── DISTINCT ──────────────────────────────────────────────────
        @testset "DISTINCT" begin
            sql = "SELECT DISTINCT name FROM persons"
            stmt = parse(sql)
            @test stmt.select_clause.distinct isa SqlDistinct
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── WHERE with comparison ─────────────────────────────────────
        @testset "WHERE comparison" begin
            sql = "SELECT * FROM persons WHERE age >= 18"
            stmt = parse(sql)
            @test stmt.where_clause.condition isa SqlWhereFilterCondition
            cmp = stmt.where_clause.condition.expression
            @test cmp isa SqlComparison
            @test cmp.operator == ">="
            @test cmp.left isa SqlColumnReference
            @test cmp.right isa SqlScalarValue
            @test cmp.right.value == 18
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── JOIN ──────────────────────────────────────────────────────
        @testset "INNER JOIN" begin
            stmt = parse("SELECT * FROM a JOIN b ON a.id = b.id")
            fi = stmt.from_clause.items[1]
            @test length(fi.joins) == 1
            j = fi.joins[1]
            @test j.join_type isa SqlInnerJoin
            @test j.condition isa SqlJoinOnCondition
            @test roundtrip(stmt) == "SELECT * FROM a INNER JOIN b ON a.id = b.id"
        end

        # ── LEFT JOIN ────────────────────────────────────────────────
        @testset "LEFT JOIN" begin
            stmt = parse("SELECT * FROM a LEFT JOIN b ON a.id = b.id")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlLeftOuterJoin
            @test roundtrip(stmt) == "SELECT * FROM a LEFT OUTER JOIN b ON a.id = b.id"
        end

        # ── RIGHT JOIN ───────────────────────────────────────────────
        @testset "RIGHT JOIN" begin
            stmt = parse("SELECT * FROM a RIGHT JOIN b ON a.id = b.id")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlRightOuterJoin
            @test roundtrip(stmt) == "SELECT * FROM a RIGHT OUTER JOIN b ON a.id = b.id"
        end

        # ── FULL OUTER JOIN ──────────────────────────────────────────
        @testset "FULL OUTER JOIN" begin
            sql = "SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id"
            stmt = parse(sql)
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlFullOuterJoin
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── CROSS JOIN ───────────────────────────────────────────────
        @testset "CROSS JOIN" begin
            sql = "SELECT * FROM a CROSS JOIN b"
            stmt = parse(sql)
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlCrossJoin
            @test j.condition === nothing
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── JOIN USING ───────────────────────────────────────────────
        @testset "JOIN USING" begin
            stmt = parse("SELECT * FROM a JOIN b USING (id, name)")
            j = stmt.from_clause.items[1].joins[1]
            @test j.condition isa SqlJoinUsingCondition
            @test length(j.condition.column_names) == 2
            # round-trip skipped: SqlJoinUsingCondition not yet registered in SqlToSyntax
        end

        # ── Subquery in FROM ─────────────────────────────────────────
        @testset "subquery FROM" begin
            sql = "SELECT * FROM (SELECT * FROM t) AS sub"
            stmt = parse(sql)
            base = stmt.from_clause.items[1].base_item
            @test base isa SqlSubqueryFromItem
            @test base.alias.name == "sub"
            @test base.subquery isa SqlSelectStatement
            @test roundtrip(stmt) == "SELECT * FROM (SELECT * FROM t ) AS sub"
        end

        # ── Boolean AND ──────────────────────────────────────────────
        @testset "AND" begin
            sql = "SELECT * FROM t WHERE a = 1 AND b = 2"
            stmt = parse(sql)
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlAnd
            @test expr.left isa SqlComparison
            @test expr.right isa SqlComparison
            @test roundtrip(stmt) == "SELECT * FROM t WHERE (a = 1 AND b = 2)"
        end

        # ── Boolean NOT ──────────────────────────────────────────────
        @testset "NOT" begin
            sql = "SELECT * FROM t WHERE NOT a = 1"
            stmt = parse(sql)
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlNot
            @test expr.expression isa SqlComparison
            @test roundtrip(stmt) == "SELECT * FROM t WHERE (NOT a = 1)"
        end

        # ── Precedence: AND binds tighter than OR ────────────────────
        @testset "OR/AND precedence" begin
            sql = "SELECT * FROM t WHERE a = 1 OR b = 2 AND c = 3"
            stmt = parse(sql)
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlOr
            @test expr.left isa SqlComparison
            @test expr.right isa SqlAnd
            @test roundtrip(stmt) == "SELECT * FROM t WHERE (a = 1 OR (b = 2 AND c = 3))"
        end

        # ── Line comment stripped ────────────────────────────────────
        @testset "line comment" begin
            sql = "-- comment\nSELECT * FROM t"
            stmt = parse(sql)
            @test stmt isa SqlSelectStatement
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── Block comment stripped ───────────────────────────────────
        @testset "block comment" begin
            sql = "SELECT /* inline */ * FROM t"
            stmt = parse(sql)
            @test stmt isa SqlSelectStatement
            @test stmt.select_clause.items[1].expression isa SqlAllColumns
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── Trailing clauses ignored ─────────────────────────────────
        @testset "trailing clause skipped" begin
            stmt = parse("SELECT * FROM t ORDER BY name")
            @test stmt isa SqlSelectStatement
            @test roundtrip(stmt) == "SELECT * FROM t"
        end

        # ── Fallback expression ──────────────────────────────────────
        @testset "fallback expression" begin
            stmt = parse("SELECT COUNT(*) FROM t")
            @test stmt isa SqlSelectStatement
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlScalarValue
            @test occursin("COUNT", string(item.expression.value))
        end

        # ── Non-SELECT raises ────────────────────────────────────────
        @testset "non-SELECT" begin
            @test_throws Exception sqlparse("INSERT INTO t VALUES (1)")
        end

        # ── Schema-qualified table ───────────────────────────────────
        @testset "schema.table" begin
            sql = "SELECT * FROM public.persons"
            stmt = parse(sql)
            tname = stmt.from_clause.items[1].base_item.table_name
            @test tname.schema_name == "public"
            @test tname.name == "persons"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── String literal in WHERE ──────────────────────────────────
        @testset "string literal" begin
            sql = "SELECT * FROM t WHERE name = 'hello'"
            stmt = parse(sql)
            cmp = stmt.where_clause.condition.expression
            @test cmp.right isa SqlScalarValue
            @test cmp.right.value == "hello"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── != normalised to <> ──────────────────────────────────────
        @testset "!= normalised" begin
            stmt = parse("SELECT * FROM t WHERE a != b")
            cmp = stmt.where_clause.condition.expression
            @test cmp.operator == "<>"
            @test roundtrip(stmt) == "SELECT * FROM t WHERE a <> b"
        end

        # ── qualifier.* in SELECT ────────────────────────────────────
        @testset "qualifier.*" begin
            sql = "SELECT p.* FROM persons AS p"
            stmt = parse(sql)
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlAllColumns
            @test item.expression.qualifier.name == "p"
            @test roundtrip(stmt) == normalize_sql(sql)
        end

        # ── Complex: nested subquery with aliases and WHERE ──────────
        @testset "complex nested statement" begin
            sql = "SELECT sub.person_name, sub.person_age FROM (SELECT p.name AS person_name, p.age AS person_age FROM persons AS p WHERE p.name <> 'X' ) AS sub WHERE sub.person_name <> 'X'"
            stmt = parse(sql)
            @test stmt isa SqlSelectStatement
            # outer SELECT
            @test length(stmt.select_clause.items) == 2
            @test stmt.select_clause.items[1].expression.qualifier.name == "sub"
            @test stmt.select_clause.items[1].expression.column_name.name == "person_name"
            @test stmt.select_clause.items[2].expression.column_name.name == "person_age"
            # outer FROM — subquery
            base = stmt.from_clause.items[1].base_item
            @test base isa SqlSubqueryFromItem
            @test base.alias.name == "sub"
            inner = base.subquery
            @test inner isa SqlSelectStatement
            # inner SELECT
            @test length(inner.select_clause.items) == 2
            @test inner.select_clause.items[1].column_alias.name == "person_name"
            @test inner.select_clause.items[2].column_alias.name == "person_age"
            # inner FROM
            @test inner.from_clause.items[1].base_item.table_name.name == "persons"
            @test inner.from_clause.items[1].base_item.alias.name == "p"
            # inner WHERE
            inner_cmp = inner.where_clause.condition.expression
            @test inner_cmp isa SqlComparison
            @test inner_cmp.left.qualifier.name == "p"
            @test inner_cmp.left.column_name.name == "name"
            @test inner_cmp.operator == "<>"
            @test inner_cmp.right.value == "X"
            # outer WHERE
            outer_cmp = stmt.where_clause.condition.expression
            @test outer_cmp isa SqlComparison
            @test outer_cmp.left.qualifier.name == "sub"
            @test outer_cmp.left.column_name.name == "person_name"
            # round-trip
            @test roundtrip(stmt) == normalize_sql(sql)
        end
    end
end

export test_sql_parser
