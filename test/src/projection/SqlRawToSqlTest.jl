using Test
using Projectured

# SqlRawToSql projection tests — parser-only, no DB needed.

function test_sql_raw_to_sql()
    @testset "SqlRawToSql" begin
        proj = SqlRawToSql()

        # ── helper: parse and return the output document ──────────────
        parse(sql) = begin
            raw = SqlRawStatement(sql)
            iomap = projection_print(proj, raw)
            iomap === nothing ? nothing : iomap.output
        end

        # ── simplest case ─────────────────────────────────────────────
        @testset "SELECT * FROM table" begin
            stmt = parse("SELECT * FROM persons")
            @test stmt isa SqlSelectStatement
            @test length(stmt.select_clause.items) == 1
            @test stmt.select_clause.items[1].expression isa SqlAllColumns
            @test length(stmt.from_clause.items) == 1
            @test stmt.from_clause.items[1].base_item.table_name.name == "persons"
        end

        # ── multi-column ──────────────────────────────────────────────
        @testset "multi-column SELECT" begin
            stmt = parse("SELECT name, age FROM persons")
            @test length(stmt.select_clause.items) == 2
            @test stmt.select_clause.items[1].expression isa SqlColumnReference
            @test stmt.select_clause.items[1].expression.column_name.name == "name"
            @test stmt.select_clause.items[2].expression.column_name.name == "age"
        end

        # ── qualifier + alias ─────────────────────────────────────────
        @testset "qualifier and alias" begin
            stmt = parse("SELECT p.name AS n FROM persons AS p")
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlColumnReference
            @test item.expression.qualifier.name == "p"
            @test item.column_alias.name == "n"
            @test stmt.from_clause.items[1].base_item.alias.name == "p"
        end

        # ── DISTINCT ──────────────────────────────────────────────────
        @testset "DISTINCT" begin
            stmt = parse("SELECT DISTINCT name FROM persons")
            @test stmt.select_clause.distinct isa SqlDistinct
        end

        # ── WHERE with comparison ─────────────────────────────────────
        @testset "WHERE comparison" begin
            stmt = parse("SELECT * FROM persons WHERE age >= 18")
            @test stmt.where_clause.condition isa SqlWhereFilterCondition
            cmp = stmt.where_clause.condition.expression
            @test cmp isa SqlComparison
            @test cmp.operator == ">="
            @test cmp.left isa SqlColumnReference
            @test cmp.right isa SqlScalarValue
            @test cmp.right.value == 18
        end

        # ── JOIN ──────────────────────────────────────────────────────
        @testset "INNER JOIN" begin
            stmt = parse("SELECT * FROM a JOIN b ON a.id = b.id")
            fi = stmt.from_clause.items[1]
            @test length(fi.joins) == 1
            j = fi.joins[1]
            @test j.join_type isa SqlInnerJoin
            @test j.condition isa SqlJoinOnCondition
        end

        # ── LEFT JOIN ────────────────────────────────────────────────
        @testset "LEFT JOIN" begin
            stmt = parse("SELECT * FROM a LEFT JOIN b ON a.id = b.id")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlLeftOuterJoin
        end

        # ── RIGHT JOIN ───────────────────────────────────────────────
        @testset "RIGHT JOIN" begin
            stmt = parse("SELECT * FROM a RIGHT JOIN b ON a.id = b.id")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlRightOuterJoin
        end

        # ── FULL OUTER JOIN ──────────────────────────────────────────
        @testset "FULL OUTER JOIN" begin
            stmt = parse("SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlFullOuterJoin
        end

        # ── CROSS JOIN ───────────────────────────────────────────────
        @testset "CROSS JOIN" begin
            stmt = parse("SELECT * FROM a CROSS JOIN b")
            j = stmt.from_clause.items[1].joins[1]
            @test j.join_type isa SqlCrossJoin
            @test j.condition === nothing
        end

        # ── JOIN USING ───────────────────────────────────────────────
        @testset "JOIN USING" begin
            stmt = parse("SELECT * FROM a JOIN b USING (id, name)")
            j = stmt.from_clause.items[1].joins[1]
            @test j.condition isa SqlJoinUsingCondition
            @test length(j.condition.column_names) == 2
        end

        # ── Subquery in FROM ─────────────────────────────────────────
        @testset "subquery FROM" begin
            stmt = parse("SELECT * FROM (SELECT * FROM t) AS sub")
            base = stmt.from_clause.items[1].base_item
            @test base isa SqlSubqueryFromItem
            @test base.alias.name == "sub"
            @test base.subquery isa SqlSelectStatement
        end

        # ── Boolean AND ──────────────────────────────────────────────
        @testset "AND" begin
            stmt = parse("SELECT * FROM t WHERE a = 1 AND b = 2")
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlAnd
            @test expr.left isa SqlComparison
            @test expr.right isa SqlComparison
        end

        # ── Boolean NOT ──────────────────────────────────────────────
        @testset "NOT" begin
            stmt = parse("SELECT * FROM t WHERE NOT a = 1")
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlNot
            @test expr.expression isa SqlComparison
        end

        # ── Precedence: AND binds tighter than OR ────────────────────
        @testset "OR/AND precedence" begin
            stmt = parse("SELECT * FROM t WHERE a = 1 OR b = 2 AND c = 3")
            expr = stmt.where_clause.condition.expression
            @test expr isa SqlOr
            @test expr.left isa SqlComparison
            @test expr.right isa SqlAnd
        end

        # ── Line comment stripped ────────────────────────────────────
        @testset "line comment" begin
            stmt = parse("-- comment\nSELECT * FROM t")
            @test stmt isa SqlSelectStatement
        end

        # ── Block comment stripped ───────────────────────────────────
        @testset "block comment" begin
            stmt = parse("SELECT /* inline */ * FROM t")
            @test stmt isa SqlSelectStatement
            @test stmt.select_clause.items[1].expression isa SqlAllColumns
        end

        # ── Trailing clauses ignored ─────────────────────────────────
        @testset "trailing clause skipped" begin
            stmt = parse("SELECT * FROM t ORDER BY name")
            @test stmt isa SqlSelectStatement
        end

        # ── Fallback expression ──────────────────────────────────────
        @testset "fallback expression" begin
            stmt = parse("SELECT COUNT(*) FROM t")
            @test stmt isa SqlSelectStatement
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlScalarValue
            @test occursin("COUNT", string(item.expression.value))
        end

        # ── Non-SELECT returns nothing ───────────────────────────────
        @testset "non-SELECT" begin
            @test parse("INSERT INTO t VALUES (1)") === nothing
        end

        # ── Schema-qualified table ───────────────────────────────────
        @testset "schema.table" begin
            stmt = parse("SELECT * FROM public.persons")
            tname = stmt.from_clause.items[1].base_item.table_name
            @test tname.schema_name == "public"
            @test tname.name == "persons"
        end

        # ── String literal in WHERE ──────────────────────────────────
        @testset "string literal" begin
            stmt = parse("SELECT * FROM t WHERE name = 'hello'")
            cmp = stmt.where_clause.condition.expression
            @test cmp.right isa SqlScalarValue
            @test cmp.right.value == "hello"
        end

        # ── != normalised to <> ──────────────────────────────────────
        @testset "!= normalised" begin
            stmt = parse("SELECT * FROM t WHERE a != b")
            cmp = stmt.where_clause.condition.expression
            @test cmp.operator == "<>"
        end

        # ── qualifier.* in SELECT ────────────────────────────────────
        @testset "qualifier.*" begin
            stmt = parse("SELECT p.* FROM persons AS p")
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlAllColumns
            @test item.expression.qualifier.name == "p"
        end
    end
end

export test_sql_raw_to_sql
