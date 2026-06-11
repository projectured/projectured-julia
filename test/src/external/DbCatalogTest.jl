using Test
using Projectured

# Read-only live-DB tests (T1–T6) for the DbCatalog hierarchy.
# No tables are created or modified — all queries target system catalogs.

# ── Catalog API tests ──────────────────────────────────────────────────────────

function test_db_catalog_databases(adapter)
    @testset "T1 — db_catalog_databases" begin
        dbs = db_catalog_databases(adapter)
        @test dbs isa Vector{String}
        @test "projectured_test" in dbs
        @info "Databases: $dbs"
    end
end

function test_db_catalog_schemas(adapter)
    @testset "T2 — db_catalog_schemas" begin
        schemas = db_catalog_schemas(adapter, "projectured_test")
        @test schemas isa Vector{String}
        @test "public" in schemas
        @info "Schemas: $schemas"
    end
end

function test_db_catalog_tables(adapter)
    @testset "T3 — db_catalog_tables" begin
        tables = db_catalog_tables(adapter, "public")
        @test tables isa Vector{String}
        @test "persons" in tables
        @info "Tables in public: $tables"
    end
end

function test_db_catalog_columns(adapter)
    @testset "T4 — db_catalog_columns" begin
        cols = db_catalog_columns(adapter, "public", "persons")
        @test cols isa Vector
        col_pairs = [(c.name, c.data_type) for c in cols]
        @test ("name", "text") in col_pairs
        @test ("age", "integer") in col_pairs
        @info "Columns in public.persons: $cols"
    end
end

# ── Document + show tests ──────────────────────────────────────────────────────

function test_db_catalog_document_show(adapter)
    @testset "T5 — document show (simple)" begin
        conn = DbCatalogConnection(adapter)
        @test sprint(show, conn) == "DbCatalogConnection($(conn.host):$(conn.port))"
        db = DbCatalogDatabase(conn, "mydb")
        @test sprint(show, db) == "DbCatalogDatabase(mydb)"
        schema = DbCatalogSchema(db, "public")
        @test sprint(show, schema) == "DbCatalogSchema(public)"
        table = DbCatalogTable(schema, "persons")
        @test sprint(show, table) == "DbCatalogTable(persons)"
        col = DbCatalogColumn(table, "name", "text")
        @test sprint(show, col) == "DbCatalogColumn(name::text)"
    end
end

# ── Projection tests ───────────────────────────────────────────────────────────

function test_db_catalog_projection_print(adapter)
    @testset "T6 — DbCatalogConnectionToChildren projection_print" begin
        conn  = DbCatalogConnection(adapter)
        p     = DbCatalogConnectionToChildren()
        iomap = projection_print(p, conn)
        @test iomap.output isa CellVector
        dbs = collect(iomap.output)
        @test all(d -> d isa DbCatalogDatabase, dbs)
        @info "Projected databases: $dbs"
    end
end

# ── Projection hierarchy tests (P1–P5) ────────────────────────────────────────

function test_db_catalog_projection_connection(adapter)
    @testset "P1 — DbCatalogConnectionToChildren" begin
        conn  = DbCatalogConnection(adapter)
        iomap = projection_print(DbCatalogConnectionToChildren(), conn)
        dbs   = collect(iomap.output)
        @test all(d -> d isa DbCatalogDatabase, dbs)
        @test any(d -> d.name == "projectured_test", dbs)
    end
end

function test_db_catalog_projection_database(adapter)
    @testset "P2 — DbCatalogDatabaseToChildren" begin
        conn    = DbCatalogConnection(adapter)
        db      = DbCatalogDatabase(conn, "projectured_test")
        iomap   = projection_print(DbCatalogDatabaseToChildren(), db)
        schemas = collect(iomap.output)
        @test all(s -> s isa DbCatalogSchema, schemas)
        @test any(s -> s.name == "public", schemas)
    end
end

function test_db_catalog_projection_schema(adapter)
    @testset "P3 — DbCatalogSchemaToChildren" begin
        conn   = DbCatalogConnection(adapter)
        db     = DbCatalogDatabase(conn, "projectured_test")
        schema = DbCatalogSchema(db, "public")
        iomap  = projection_print(DbCatalogSchemaToChildren(), schema)
        tables = collect(iomap.output)
        @test all(t -> t isa DbCatalogTable, tables)
        @test any(t -> t.name == "persons", tables)
    end
end

function test_db_catalog_projection_table(adapter)
    @testset "P4 — DbCatalogTableToChildren" begin
        conn   = DbCatalogConnection(adapter)
        db     = DbCatalogDatabase(conn, "projectured_test")
        schema = DbCatalogSchema(db, "public")
        table  = DbCatalogTable(schema, "persons")
        iomap  = projection_print(DbCatalogTableToChildren(), table)
        cols   = collect(iomap.output)
        @test all(c -> c isa DbCatalogColumn, cols)
        @test any(c -> c.name == "name"  && c.data_type == "text",    cols)
        @test any(c -> c.name == "age"   && c.data_type == "integer", cols)
    end
end

function test_db_catalog_projection_full(adapter)
    @testset "P5 — full hierarchy expansion" begin
        conn = DbCatalogConnection(adapter)

        dbs = collect(projection_print(DbCatalogConnectionToChildren(), conn).output)
        @test all(d -> d isa DbCatalogDatabase, dbs)
        db = first(filter(d -> d.name == "projectured_test", dbs))
        @test db isa DbCatalogDatabase

        schemas = collect(projection_print(DbCatalogDatabaseToChildren(), db).output)
        @test all(s -> s isa DbCatalogSchema, schemas)
        schema = first(filter(s -> s.name == "public", schemas))
        @test schema isa DbCatalogSchema

        tables = collect(projection_print(DbCatalogSchemaToChildren(), schema).output)
        @test all(t -> t isa DbCatalogTable, tables)
        table = first(filter(t -> t.name == "persons", tables))
        @test table isa DbCatalogTable

        cols = collect(projection_print(DbCatalogTableToChildren(), table).output)
        @test all(c -> c isa DbCatalogColumn, cols)
        @test any(c -> c.name == "name"  && c.data_type == "text",    cols)
        @test any(c -> c.name == "age"   && c.data_type == "integer", cols)
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog(; skip_if_no_db=true)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping DbCatalog tests (ODBC DSN unavailable): $e"
        false
    end

    can_connect || return

    @testset "DbCatalog (live DB, read-only)" begin
        try
            test_db_catalog_databases(adapter)
            test_db_catalog_schemas(adapter)
            test_db_catalog_tables(adapter)
            test_db_catalog_columns(adapter)
            test_db_catalog_document_show(adapter)
            test_db_catalog_projection_print(adapter)
            test_db_catalog_projection_connection(adapter)
            test_db_catalog_projection_database(adapter)
            test_db_catalog_projection_schema(adapter)
            test_db_catalog_projection_table(adapter)
            test_db_catalog_projection_full(adapter)
        finally
            db_close!(adapter)
        end
    end
end

export test_db_catalog
