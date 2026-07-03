using Test
using Projectured

# ── Helpers that do not need a live DB ────────────────────────────────────────

function test_raw_database_result_show()
    @testset "RawDatabaseResult show" begin
        r = RawDatabaseResult(["name", "age"], [["Alice", 30], ["Bob", 25]])
        output = sprint(show, r)
        @test output == "name\tage\nAlice\t30\nBob\t25\n"
    end
end

function test_raw_database_result_struct()
    @testset "RawDatabaseResult struct" begin
        r = RawDatabaseResult(["x", "y"], [[1, 2], [3, 4]])
        @test r.columns == ["x", "y"]
        @test length(r.rows) == 2
        @test r.rows[1] == Any[1, 2]
        @test r.rows[2] == Any[3, 4]
    end
end

# ── Live-DB helpers (also used by DatabaseTabularTest) ────────────────────────
#
# Test-database conventions (keep new live-DB tests consistent with these):
#
#   • Database — all live-DB tests run against `projectured_test`
#     (localhost:5432, user/pwd `projectured`). Override via the PG* / TEST_ODBC_DSN
#     env vars below; never point these at a real/shared database.
#
#   • Schema — any test that CREATEs schemas or tables must work inside the
#     dedicated `test` schema, never `public`. `public` is reserved for other
#     purposes (and pre-existing fixtures); creating/dropping objects there can
#     clobber unrelated state. Schema-qualify created objects as `test.<name>`.
#
#   • Teardown — create in order (schema → table) and drop in REVERSE order
#     (table → schema), with a reverse-order `finally` safety net using
#     `DROP … IF EXISTS` so a mid-test failure still cleans up and leaves the
#     `test` schema gone. See `test_create_ddl_in_test_schema` /
#     `test_db_catalog_to_sql_live` for the pattern to copy.

function _make_test_adapter()
    OdbcDatabaseAdapter(
        dsn=get(ENV, "TEST_ODBC_DSN",
                "Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
                "Database=projectured_test;" *
                "Uid=$(get(ENV, "PGUSER", "projectured"));" *
                "Pwd=$(get(ENV, "PGPASSWORD", "projectured"));"),
        rowid_column="ctid")
end

# Connection spec for the catalog / SQL projection tests. These drive the
# database through an OdbcConnectionPool rather than a bare adapter.
function _make_test_instance()
    DatabaseInstance(
        database=get(ENV, "PGDATABASE", "projectured_test"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")),
        credentials=DatabaseCredentials(
            user=get(ENV, "PGUSER", "projectured"),
            password=get(ENV, "PGPASSWORD", "projectured")))
end

_make_test_pool() = OdbcConnectionPool(rowid_column="ctid")

function _setup_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    db_execute_raw(adapter,
        "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    db_insert!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function _teardown_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end

# ── Live-DB tests ─────────────────────────────────────────────────────────────

function test_connect_close(adapter)
    @testset "T1 — connect / close" begin
        db_connect!(adapter)
        @test db_alive(adapter) == true
        db_close!(adapter)
        @test db_alive(adapter) == false
        db_connect!(adapter)   # reconnect for subsequent tests
    end
end

function test_insert(adapter)
    @testset "T2 — insert" begin
        count_before = db_query(adapter, "persons", RawDatabaseResult).rows |> length
        n = db_insert!(adapter, "persons", Dict("name" => "Bob", "age" => 25))
        @test n == 1
        count_after = db_query(adapter, "persons", RawDatabaseResult).rows |> length
        @test count_after == count_before + 1
    end
end

function test_query_to_raw(adapter)
    @testset "T3 — db_query into RawDatabaseResult" begin
        r = db_query(adapter, "persons", RawDatabaseResult)
        @test r isa RawDatabaseResult
        @test r.columns == ["name", "age"]
        @test length(r.rows) >= 1
        @test r.rows[1][1] isa String
    end
end

function test_update(adapter)
    @testset "T4 — update via db_update!" begin
        db_insert!(adapter, "persons", Dict("name" => "UpdateMe", "age" => 1))
        n = db_update!(adapter, "persons",
                       Dict("age" => 99),
                       "name = 'UpdateMe'")
        @test n == 1
        r = db_query(adapter, "persons", RawDatabaseResult; where="name = 'UpdateMe'")
        @test length(r.rows) == 1
        @test string(r.rows[1][2]) == "99"
    end
end

function test_delete(adapter)
    @testset "T5 — delete via db_delete!" begin
        db_insert!(adapter, "persons", Dict("name" => "DeleteMe", "age" => 0))
        n = db_delete!(adapter, "persons", "name = 'DeleteMe'")
        @test n == 1
        r = db_query(adapter, "persons", RawDatabaseResult; where="name = 'DeleteMe'")
        @test isempty(r.rows)
    end
end

function test_execute_raw(adapter)
    @testset "T6 — db_execute_raw into RawDatabaseResult" begin
        r = db_execute_raw(adapter,
                           "SELECT count(*) FROM persons",
                           RawDatabaseResult)
        @test r isa RawDatabaseResult
        @test length(r.rows) == 1
        @test parse(Int, string(r.rows[1][1])) >= 1
    end
end

# Render a parsed/constructed SQL document to executable text through the
# Sql→Syntax→Text→String pipeline (the same path an LLM-facing DDL view uses).
_ddl_render_pipe() = ChainingProjection(
    RecursiveProjection(SqlToSyntax()),
    RecursiveProjection(SyntaxToText()),
    RecursiveProjection(TextToString()))
_ddl_to_sql(stmt) = projection_print(_ddl_render_pipe(), stmt).output[]

# Full DDL lifecycle, run entirely inside a dedicated `test` schema (the `public`
# schema is reserved for other purposes here). Each statement is parsed from
# external SQL text, rendered back through the Sql→Syntax→Text→String pipeline,
# and the rendered text executed against the live database — proving the parser
# and SqlToSyntax emit executable PostgreSQL.
#
# Order of operations:
#   1. CREATE SCHEMA test
#   2. CREATE TABLE test.ddl_roundtrip (…)
# then teardown in reverse:
#   3. DROP TABLE test.ddl_roundtrip
#   4. DROP SCHEMA test
function test_create_ddl_in_test_schema(adapter)
    @testset "T7 — CREATE SCHEMA/TABLE DDL round-trip (test schema)" begin
        schema_stmt = sqlparse("CREATE SCHEMA test")
        @test schema_stmt isa SqlCreateSchemaStatement
        @test schema_stmt.schema_name == "test"

        table_stmt = sqlparse(
            "CREATE TABLE test.ddl_roundtrip (id integer, name text, price numeric(10, 2))")
        @test table_stmt isa SqlCreateTableStatement
        @test table_stmt.table_name.schema_name == "test"
        @test table_stmt.table_name.name == "ddl_roundtrip"
        @test length(table_stmt.columns) == 3

        # Clean slate (reverse order) in case a previous run left artifacts behind.
        db_execute_raw(adapter, "DROP TABLE IF EXISTS test.ddl_roundtrip", RawDatabaseResult)
        db_execute_raw(adapter, "DROP SCHEMA IF EXISTS test", RawDatabaseResult)

        try
            # 1. CREATE SCHEMA test
            db_execute_raw(adapter, _ddl_to_sql(schema_stmt), RawDatabaseResult)
            @test length(db_execute_raw(adapter,
                "SELECT schema_name FROM information_schema.schemata " *
                "WHERE schema_name = 'test'", RawDatabaseResult).rows) == 1

            # 2. CREATE TABLE test.ddl_roundtrip (…)
            db_execute_raw(adapter, _ddl_to_sql(table_stmt), RawDatabaseResult)
            cols = db_execute_raw(adapter,
                "SELECT column_name, data_type FROM information_schema.columns " *
                "WHERE table_schema = 'test' AND table_name = 'ddl_roundtrip' " *
                "ORDER BY ordinal_position",
                RawDatabaseResult)
            @test [string(r[1]) for r in cols.rows] == ["id", "name", "price"]
            @test [string(r[2]) for r in cols.rows] == ["integer", "text", "numeric"]

            # 3. DROP TABLE test.ddl_roundtrip
            db_execute_raw(adapter, "DROP TABLE test.ddl_roundtrip", RawDatabaseResult)
            @test isempty(db_execute_raw(adapter,
                "SELECT 1 FROM information_schema.tables " *
                "WHERE table_schema = 'test' AND table_name = 'ddl_roundtrip'",
                RawDatabaseResult).rows)

            # 4. DROP SCHEMA test
            db_execute_raw(adapter, "DROP SCHEMA test", RawDatabaseResult)
            @test isempty(db_execute_raw(adapter,
                "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'test'",
                RawDatabaseResult).rows)
        finally
            # Safety net (reverse order) if an assertion above failed mid-lifecycle.
            db_execute_raw(adapter, "DROP TABLE IF EXISTS test.ddl_roundtrip", RawDatabaseResult)
            db_execute_raw(adapter, "DROP SCHEMA IF EXISTS test", RawDatabaseResult)
        end
    end
end

# Layer 3 end-to-end: build a catalog tree, project it to a DDL script via
# DbCatalogToSql, and run that generated script against the live database — inside
# the dedicated `test` schema, torn down in reverse order. Statements are executed
# one at a time (split on the blank-line separator) since the ODBC path runs a
# single statement per call.
function test_db_catalog_to_sql_live(adapter)
    @testset "T9 — DbCatalogToSql → execute generated DDL (test schema)" begin
        film = DbCatalogTable("film", CellVector(Cell[
            Cell(DbCatalogColumn("title", "text")),
            Cell(DbCatalogColumn("length", "integer"))]))
        schema = DbCatalogSchema("test", CellVector(Cell[Cell(film)]))

        pipe = ChainingProjection(
            RecursiveProjection(DbCatalogToSql()),
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        script = projection_print(pipe, schema).output[]
        @test occursin("CREATE SCHEMA test", script)
        @test occursin("CREATE TABLE test.film", script)

        db_execute_raw(adapter, "DROP TABLE IF EXISTS test.film", RawDatabaseResult)
        db_execute_raw(adapter, "DROP SCHEMA IF EXISTS test", RawDatabaseResult)
        try
            for stmt in split(script, "\n\n")
                s = strip(stmt)
                isempty(s) && continue
                db_execute_raw(adapter, String(s), RawDatabaseResult)
            end
            cols = db_execute_raw(adapter,
                "SELECT column_name, data_type FROM information_schema.columns " *
                "WHERE table_schema = 'test' AND table_name = 'film' " *
                "ORDER BY ordinal_position",
                RawDatabaseResult)
            @test [string(r[1]) for r in cols.rows] == ["title", "length"]
            @test [string(r[2]) for r in cols.rows] == ["text", "integer"]
        finally
            db_execute_raw(adapter, "DROP TABLE IF EXISTS test.film", RawDatabaseResult)
            db_execute_raw(adapter, "DROP SCHEMA IF EXISTS test", RawDatabaseResult)
        end
    end
end

# ── Entry points ──────────────────────────────────────────────────────────────

function test_database_connection()
    adapter = _make_test_adapter()
    @testset "Database connection" begin
        @test_nowarn db_connect!(adapter)
        @test db_alive(adapter) == true
        @test_nowarn db_close!(adapter)
        @test db_alive(adapter) == false
    end
end

function test_database_no_db()
    @testset "Database (no DB)" begin
        test_raw_database_result_show()
        test_raw_database_result_struct()
    end
end

function test_database(; skip_if_no_db=true)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping live-DB tests (ODBC DSN unavailable): $e"
        false
    end

    test_database_no_db()

    can_connect || return

    @testset "Database (live DB)" begin
        try
            _setup_persons_table(adapter)
            test_connect_close(adapter)
            test_insert(adapter)
            test_query_to_raw(adapter)
            test_update(adapter)
            test_delete(adapter)
            test_execute_raw(adapter)
            test_create_ddl_in_test_schema(adapter)
            test_db_catalog_to_sql_live(adapter)
        finally
            db_close!(adapter)
        end
    end
end

export test_database_connection, test_database, test_database_no_db
