using Test
using Projectured

# Read-only live-DB tests for the DbCatalog hierarchy.
# No tables are created or modified — all queries target system catalogs.
#
# The catalog tree is now a pure data structure built by the
# DatabaseInstanceToDbCatalog projection from a DatabaseInstance, querying the
# database through an OdbcConnectionPool. The low-level db_catalog_* API still
# operates on a bare adapter and is tested directly.

# ── Catalog API tests (low-level, on a bare adapter) ────────────────────────────

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

# ── Document + show tests (pure values, no DB) ──────────────────────────────────

function test_db_catalog_document_show()
    @testset "T5 — document show (simple)" begin
        rdbms = DbCatalogRdbms("localhost", 5432, CellVector())
        @test sprint(show, rdbms) == "DbCatalogRdbms(localhost:5432)"
        db = DbCatalogDatabase("mydb", CellVector())
        @test sprint(show, db) == "DbCatalogDatabase(mydb)"
        schema = DbCatalogSchema("public", CellVector())
        @test sprint(show, schema) == "DbCatalogSchema(public)"
        table = DbCatalogTable("persons", CellVector())
        @test sprint(show, table) == "DbCatalogTable(persons)"
        col = DbCatalogColumn("name", "text")
        @test sprint(show, col) == "DbCatalogColumn(name::text)"
    end
end

# ── Projection tests — DatabaseInstanceToDbCatalog (live DB) ────────────────────

function test_db_catalog_projection_rdbms(instance, pool)
    @testset "P1 — DatabaseInstanceToDbCatalog produces an Rdbms tree" begin
        rdbms = projection_print(DatabaseInstanceToDbCatalog(pool), instance).output
        @test rdbms isa DbCatalogRdbms
        @test rdbms.databases isa CellVector
        dbs = collect(rdbms.databases)
        @test all(d -> d isa DbCatalogDatabase, dbs)
        @test any(d -> d.name == "projectured_test", dbs)
    end
end

function _force_persons_table(instance, pool)
    rdbms  = projection_print(DatabaseInstanceToDbCatalog(pool), instance).output
    db     = first(filter(d -> d.name == "projectured_test", collect(rdbms.databases)))
    schema = first(filter(s -> s.name == "public", collect(db.schemas)))
    table  = first(filter(t -> t.name == "persons", collect(schema.tables)))
    rdbms, db, schema, table
end

function test_db_catalog_projection_database(instance, pool)
    @testset "P2 — database level expands to schemas" begin
        rdbms = projection_print(DatabaseInstanceToDbCatalog(pool), instance).output
        db = first(filter(d -> d.name == "projectured_test", collect(rdbms.databases)))
        schemas = collect(db.schemas)
        @test all(s -> s isa DbCatalogSchema, schemas)
        @test any(s -> s.name == "public", schemas)
    end
end

function test_db_catalog_projection_schema(instance, pool)
    @testset "P3 — schema level expands to tables" begin
        _, _, schema, _ = _force_persons_table(instance, pool)
        tables = collect(schema.tables)
        @test all(t -> t isa DbCatalogTable, tables)
        @test any(t -> t.name == "persons", tables)
    end
end

function test_db_catalog_projection_table(instance, pool)
    @testset "P4 — table level expands to columns" begin
        _, _, _, table = _force_persons_table(instance, pool)
        cols = collect(table.columns)
        @test all(c -> c isa DbCatalogColumn, cols)
        @test any(c -> c.name == "name" && c.data_type == "text",    cols)
        @test any(c -> c.name == "age"  && c.data_type == "integer", cols)
    end
end

function test_db_catalog_projection_full(instance, pool)
    @testset "P5 — full hierarchy expansion" begin
        rdbms, db, schema, table = _force_persons_table(instance, pool)
        @test rdbms  isa DbCatalogRdbms
        @test db     isa DbCatalogDatabase
        @test schema isa DbCatalogSchema
        @test table  isa DbCatalogTable
        cols = collect(table.columns)
        @test any(c -> c.name == "name" && c.data_type == "text",    cols)
        @test any(c -> c.name == "age"  && c.data_type == "integer", cols)
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog(; skip_if_no_db=true)
    test_db_catalog_document_show()

    adapter  = _make_test_adapter()
    instance = _make_test_instance()
    pool     = _make_test_pool()
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
            setup_persons_table(adapter)
            test_db_catalog_databases(adapter)
            test_db_catalog_schemas(adapter)
            test_db_catalog_tables(adapter)
            test_db_catalog_columns(adapter)
            test_db_catalog_projection_rdbms(instance, pool)
            test_db_catalog_projection_database(instance, pool)
            test_db_catalog_projection_schema(instance, pool)
            test_db_catalog_projection_table(instance, pool)
            test_db_catalog_projection_full(instance, pool)
        finally
            db_close!(adapter)
            close_pool!(pool)
        end
    end
end

export test_db_catalog
