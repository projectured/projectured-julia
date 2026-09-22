using Test

# SqlParser tests — parser-only, no DB needed.

function test_sql_parser()
    @testset "SqlParser" begin
        # ── helper: parse and return the output document ──────────────
        parse(sql) = parse_sql_text(sql)

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
        roundtrip(stmt) = normalize_sql(print_document(sql_pipe, stmt).output)

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
            @test roundtrip(stmt) == "SELECT * FROM a INNER JOIN b USING (id, name)"
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
            # The source text of an expression that the parser does not model
            # prints back as it is written, not as a quoted string.
            @test item.expression isa SqlRawExpression
            @test item.expression.text == "COUNT(*)"
            @test roundtrip(stmt) == "SELECT COUNT(*) FROM t"
            @test roundtrip(parse("SELECT UPPER(name) AS n, COUNT(*) FROM t")) ==
                  "SELECT UPPER(name) AS n, COUNT(*) FROM t"
        end

        # ── An expression that starts with a column keeps its text ────
        @testset "an expression that starts with a column is kept whole" begin
            stmt = parse("SELECT a + 1 FROM t")
            item = stmt.select_clause.items[1]
            @test item.expression isa SqlRawExpression
            @test item.expression.text == "a + 1"
            @test stmt.from_clause.items[1].base_item.table_name.name == "t"
            @test roundtrip(stmt) == "SELECT a + 1 FROM t"
            @test roundtrip(parse("SELECT 1 + a AS b, c FROM t")) == "SELECT 1 + a AS b, c FROM t"
            @test roundtrip(parse("SELECT p.a * 2 FROM t AS p")) == "SELECT p.a * 2 FROM t AS p"
            # A column that is the whole expression stays a column.
            @test parse("SELECT a, b FROM t").select_clause.items[1].expression isa SqlColumnReference
        end

        # ── A sign in front of a number ──────────────────────────────
        @testset "a sign in front of a number is part of the number" begin
            stmt = parse("SELECT * FROM t WHERE a = -1")
            @test stmt.where_clause.condition.expression.right.value === -1
            @test roundtrip(stmt) == "SELECT * FROM t WHERE a = -1"
            stmt = parse("SELECT * FROM t WHERE a > -2.5")
            @test stmt.where_clause.condition.expression.right.value === -2.5
            @test roundtrip(stmt) == "SELECT * FROM t WHERE a > -2.5"
            @test parse("SELECT * FROM t WHERE a = +3").where_clause.condition.expression.right.value === 3
            items = parse("SELECT -1, - 2 FROM t").select_clause.items
            @test items[1].expression.value === -1 && items[2].expression.value === -2
            # Between two operands, a sign is an operator, and the expression keeps its text.
            item = parse("SELECT a - 1 FROM t").select_clause.items[1]
            @test item.expression isa SqlRawExpression
            @test item.expression.text == "a - 1"
            @test parse("SELECT a + 1 FROM t").select_clause.items[1].expression.text == "a + 1"
            @test parse("SELECT -a FROM t").select_clause.items[1].expression.text == "-a"
            # The printed text reads as the same document.
            again = parse(print_document(sql_pipe, parse("SELECT * FROM t WHERE a = -1")).output)
            @test again.where_clause.condition.expression.right.value === -1
            again = parse(print_document(sql_pipe, parse("SELECT * FROM t WHERE a > -2.5")).output)
            @test again.where_clause.condition.expression.right.value === -2.5
            again = parse(print_document(sql_pipe, parse("SELECT a - 1 FROM t")).output)
            @test again.select_clause.items[1].expression.text == "a - 1"
            @test again.from_clause.items[1].base_item.table_name.name == "t"
        end

        # ── A quote in a string literal ──────────────────────────────
        @testset "two quotes in a string literal read as one, and a quote prints as two" begin
            stmt = parse("SELECT * FROM t WHERE name = 'it''s'")
            @test stmt.where_clause.condition.expression.right.value == "it's"
            @test roundtrip(stmt) == "SELECT * FROM t WHERE name = 'it''s'"
            stmt = parse("SELECT '''a''', '' FROM t")
            @test stmt.select_clause.items[1].expression.value == "'a'"
            @test stmt.select_clause.items[2].expression.value == ""
            # A value with a quote prints as text that reads back as that value.
            stmt.select_clause.items[2].expression.value = "o'clock"
            again = parse(print_document(sql_pipe, stmt).output)
            @test again.select_clause.items[1].expression.value == "'a'"
            @test again.select_clause.items[2].expression.value == "o'clock"
        end

        # ── A SELECT with no FROM ────────────────────────────────────
        @testset "a SELECT with no FROM prints no FROM and reads back" begin
            stmt = parse("SELECT 1")
            @test isempty(stmt.from_clause.items)
            @test roundtrip(stmt) == "SELECT 1"
            @test roundtrip(parse(print_document(sql_pipe, stmt).output)) == "SELECT 1"
            @test roundtrip(parse("SELECT 1 WHERE a = 2")) == "SELECT 1 WHERE a = 2"
        end

        # ── Text that is not ASCII ───────────────────────────────────
        @testset "a string literal and an identifier with text that is not ASCII" begin
            stmt = parse("SELECT 'é' FROM t")
            @test stmt.select_clause.items[1].expression.value == "é"
            @test roundtrip(stmt) == "SELECT 'é' FROM t"
            stmt = parse("SELECT café FROM tablé WHERE naïve = 'ü'")
            @test stmt.select_clause.items[1].expression.column_name.name == "café"
            @test stmt.from_clause.items[1].base_item.table_name.name == "tablé"
            @test roundtrip(parse(print_document(sql_pipe, stmt).output)) == roundtrip(stmt)
            stmt = parse("SELECT \"café\" FROM t -- é\n")
            @test stmt.select_clause.items[1].expression.column_name.name == "café"
            stmt = parse("SELECT upper('é') AS ü FROM t /* ö */")
            @test stmt.select_clause.items[1].expression.text == "upper('é')"
            @test stmt.select_clause.items[1].column_alias.name == "ü"
        end

        # ── Several statements ───────────────────────────────────────
        @testset "several statements" begin
            list = parse("SELECT * FROM a; SELECT * FROM b;")
            @test list isa SqlStatementList
            @test length(list.statements) == 2
            @test list.statements[2].from_clause.items[1].base_item.table_name.name == "b"
            # One statement stays a bare statement, with or without a trailing `;`.
            @test parse("SELECT * FROM a;") isa SqlSelectStatement
            @test parse("SELECT * FROM a") isa SqlSelectStatement
            ddl = parse("CREATE SCHEMA s; CREATE TABLE s.t (id integer)")
            @test ddl isa SqlStatementList
            @test ddl.statements[1] isa SqlCreateSchemaStatement
            @test ddl.statements[2] isa SqlCreateTableStatement
            # A printed list reads back as the same list.
            for document in (list, ddl)
                again = parse(print_document(sql_pipe, document).output)
                @test again isa SqlStatementList
                @test length(again.statements) == length(document.statements)
                @test roundtrip(again) == roundtrip(document)
            end
            # One statement that does not parse fails the whole text.
            @test_throws Exception parse("SELECT * FROM a; INSERT INTO t VALUES (1)")
            @test_throws Exception parse(";")
        end

        # ── Non-SELECT raises ────────────────────────────────────────
        @testset "non-SELECT" begin
            @test_throws Exception parse_sql_text("INSERT INTO t VALUES (1)")
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
