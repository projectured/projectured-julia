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

        # ── A join that the parser does not read ─────────────────────
        @testset "a join that the parser does not read is an error" begin
            # The joins of the model are INNER, LEFT, RIGHT, FULL and CROSS, and
            # a base item is one table or one subquery. A join of another form is
            # an error for the whole statement, so its text is never dropped.
            @test_throws ErrorException parse("SELECT * FROM a NATURAL JOIN b")
            @test_throws ErrorException parse("SELECT * FROM a NATURAL LEFT JOIN b")
            @test_throws ErrorException parse("SELECT * FROM a NATURAL JOIN b WHERE a.x = 1")
            @test_throws ErrorException parse("SELECT * FROM a, b NATURAL JOIN c")
            @test_throws ErrorException parse("SELECT * FROM a JOIN (x, y) ON a.id = x.id")
            # An ON or a USING with no condition after it is an error too.
            @test_throws ErrorException parse("SELECT * FROM a JOIN b ON")
            @test_throws ErrorException parse("SELECT * FROM a JOIN b ON WHERE a.x = 1")
            @test_throws ErrorException parse("SELECT * FROM a JOIN b USING")
            # A join that names no condition at all is a join of the model.
            stmt = parse("SELECT * FROM a JOIN b")
            @test stmt.from_clause.items[1].joins[1].condition === nothing
            @test roundtrip(stmt) == "SELECT * FROM a INNER JOIN b"
        end

        # ── The printed text of a join ───────────────────────────────
        @testset "the printed text of a join parses back to the same document" begin
            for sql in ("SELECT * FROM a INNER JOIN b ON a.id = b.id",
                        "SELECT * FROM a LEFT OUTER JOIN b ON a.id = b.id",
                        "SELECT * FROM a RIGHT OUTER JOIN b ON a.id = b.id",
                        "SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id",
                        "SELECT * FROM a CROSS JOIN b",
                        "SELECT * FROM a INNER JOIN b USING (id, name)",
                        "SELECT * FROM a INNER JOIN b",
                        "SELECT * FROM a INNER JOIN b ON a.id = b.id + 1",
                        "SELECT * FROM a INNER JOIN b ON a.id = b.id CROSS JOIN c")
                @test roundtrip(parse(sql)) == sql
                @test roundtrip(parse(roundtrip(parse(sql)))) == sql
            end
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

        # ── A condition that the model does not have ─────────────────
        @testset "a condition that the model does not have keeps its text" begin
            # The printed text reads as the same document.
            reads_back(stmt) = roundtrip(parse(print_document(sql_pipe, stmt).output)) == roundtrip(stmt)
            where_expression(stmt) = stmt.where_clause.condition === nothing ? nothing :
                                     stmt.where_clause.condition.expression
            for text in ("a - 1 = 0", "a = -b", "name LIKE 'x%'", "a NOT LIKE 'x%'", "a IS NOT NULL",
                         "a IN (1, 2)", "a IN (SELECT id FROM u)", "a BETWEEN 1 AND 5", "(a - 1) = 0",
                         "EXISTS (SELECT * FROM u WHERE u.id = t.id AND u.x = 1)", "a = LEFT(name, 1)")
                sql = "SELECT * FROM t WHERE " * text
                stmt = try parse(sql) catch; nothing end
                @test stmt isa SqlSelectStatement
                stmt isa SqlSelectStatement || continue
                @test roundtrip(stmt) == sql
                @test where_expression(stmt) isa SqlRawCondition && where_expression(stmt).text == text
                @test reads_back(stmt)
            end
            # A condition after AND or OR stays, and so does each condition after it.
            stmt = parse("SELECT * FROM t WHERE a = 1 AND name LIKE 'x%' AND b = 2")
            @test roundtrip(stmt) == "SELECT * FROM t WHERE ((a = 1 AND name LIKE 'x%') AND b = 2)"
            expression = where_expression(stmt)
            @test expression isa SqlAnd && expression.right isa SqlComparison &&
                  expression.left.left isa SqlComparison && expression.left.right isa SqlRawCondition
            @test reads_back(stmt)
            stmt = parse("SELECT * FROM t WHERE a = 1 OR a - 1 = 0 OR NOT b LIKE 'y'")
            @test roundtrip(stmt) == "SELECT * FROM t WHERE ((a = 1 OR a - 1 = 0) OR (NOT b LIKE 'y'))"
            expression = where_expression(stmt)
            @test expression isa SqlOr && expression.right isa SqlNot &&
                  expression.right.expression isa SqlRawCondition && expression.left.right isa SqlRawCondition
            @test reads_back(stmt)
            # The AND of BETWEEN is part of the condition.
            stmt = parse("SELECT * FROM t WHERE a BETWEEN 1 AND 5 AND b = 2")
            expression = where_expression(stmt)
            @test expression isa SqlAnd && expression.left isa SqlRawCondition &&
                  expression.left.text == "a BETWEEN 1 AND 5" && expression.right isa SqlComparison
            # A condition ends before a clause that the parser skips.
            stmt = try parse("SELECT * FROM t WHERE name LIKE 'x%' ORDER BY lower(name)") catch; nothing end
            @test stmt isa SqlSelectStatement && where_expression(stmt) isa SqlRawCondition &&
                  where_expression(stmt).text == "name LIKE 'x%'"
            # The condition of a join keeps its text too.
            stmt = parse("SELECT * FROM a JOIN b ON a.id = b.id + 1 WHERE b.x = 1")
            condition = stmt.from_clause.items[1].joins[1].condition
            @test condition isa SqlJoinOnCondition && condition.expression isa SqlRawCondition &&
                  condition.expression.text == "a.id = b.id + 1"
            @test where_expression(stmt) isa SqlComparison
            @test roundtrip(stmt) == "SELECT * FROM a INNER JOIN b ON a.id = b.id + 1 WHERE b.x = 1"
            @test reads_back(stmt)
            # The forms that the model has stay structured.
            expression = where_expression(parse("SELECT * FROM t WHERE (a = 1 OR b <> 'x') AND NOT c >= -2"))
            @test expression isa SqlAnd && expression.left isa SqlOr &&
                  expression.left.left isa SqlComparison && expression.left.right isa SqlComparison &&
                  expression.right isa SqlNot && expression.right.expression isa SqlComparison
            # A parenthesis that does not close a condition is part of its text.
            expression = where_expression(parse("SELECT * FROM t WHERE (a = 1 OR) AND b = 2"))
            @test expression isa SqlAnd && expression.left isa SqlRawCondition &&
                  expression.left.text == "(a = 1 OR)"
            # A condition with no text is an error, so no text is dropped.
            @test_throws ErrorException parse("SELECT * FROM t WHERE")
            @test_throws ErrorException parse("SELECT * FROM t WHERE a = 1 AND")
        end

        # ── A clause that the parser skips ───────────────────────────
        @testset "a skipped clause with a parenthesis ends at the end of the statement" begin
            @test (try parse("SELECT * FROM t ORDER BY lower(name)") catch; nothing end) isa SqlSelectStatement
            stmt = try parse("SELECT * FROM (SELECT a FROM t GROUP BY f(a)) AS s WHERE s.a = 1") catch; nothing end
            @test stmt isa SqlSelectStatement && stmt.from_clause.items[1].base_item.alias.name == "s" &&
                  stmt.where_clause.condition.expression isa SqlComparison
        end

        # ── A number with an exponent ────────────────────────────────
        @testset "a number with an exponent reads as its value" begin
            stmt = parse("SELECT * FROM t WHERE a = 1e5")
            @test stmt.where_clause.condition.expression.right.value === 1.0e5
            @test roundtrip(stmt) == "SELECT * FROM t WHERE a = 100000.0"
            sql = "SELECT 2.5E-3, 1E+2, -3e2, 1e20 FROM t"
            values = [2.5e-3, 100.0, -300.0, 1.0e20]
            @test [item.expression.value for item in parse(sql).select_clause.items] == values
            # The printed text reads as the same values.
            again = parse(print_document(sql_pipe, parse(sql)).output)
            @test [item.expression.value for item in again.select_clause.items] == values
            # An `e` that no digit follows is not an exponent, and the text stays.
            @test parse("SELECT 2e FROM t").select_clause.items[1].expression.text == "2e"
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
