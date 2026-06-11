using Test
using Projectured

# Read-only tests for DbCatalogToJson projection.
# Tests that each DbCatalog document type projects to a JsonObject
# containing only its data fields (excluding parent references and selection).

# ── DbCatalogConnectionToJson tests ─────────────────────────────────────────────

function test_db_catalog_connection_to_json(; show_detail=false)
    @testset "DbCatalogConnectionToJson" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        conn = DbCatalogConnection(adapter; host="myhost", port=5433)
        
        iomap = projection_print(DbCatalogConnectionToJson(), conn)
        @test iomap.output isa JsonObject
        
        obj = iomap.output
        if show_detail
            println("  Connection JSON: ", obj)
        end
        @test haskey(obj, "host")
        @test haskey(obj, "port")
        @test obj["host"][] == "myhost"
        @test obj["port"][] == 5433
        
        # Verify no parent references or selection fields
        @test !haskey(obj, "adapter")
        @test !haskey(obj, "connection")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogDatabaseToJson tests ───────────────────────────────────────────────

function test_db_catalog_database_to_json(; show_detail=false)
    @testset "DbCatalogDatabaseToJson" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        conn = DbCatalogConnection(adapter)
        db = DbCatalogDatabase(conn, "mydb")
        
        iomap = projection_print(DbCatalogDatabaseToJson(), db)
        @test iomap.output isa JsonObject
        
        obj = iomap.output
        if show_detail
            println("  Database JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "mydb"
        
        # Verify no parent references or selection fields
        @test !haskey(obj, "connection")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogSchemaToJson tests ─────────────────────────────────────────────────

function test_db_catalog_schema_to_json(; show_detail=false)
    @testset "DbCatalogSchemaToJson" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        conn = DbCatalogConnection(adapter)
        db = DbCatalogDatabase(conn, "mydb")
        schema = DbCatalogSchema(db, "public")
        
        iomap = projection_print(DbCatalogSchemaToJson(), schema)
        @test iomap.output isa JsonObject
        
        obj = iomap.output
        if show_detail
            println("  Schema JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "public"
        
        # Verify no parent references or selection fields
        @test !haskey(obj, "database")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogTableToJson tests ───────────────────────────────────────────────────

function test_db_catalog_table_to_json(; show_detail=false)
    @testset "DbCatalogTableToJson" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        conn = DbCatalogConnection(adapter)
        db = DbCatalogDatabase(conn, "mydb")
        schema = DbCatalogSchema(db, "public")
        table = DbCatalogTable(schema, "persons")
        
        iomap = projection_print(DbCatalogTableToJson(), table)
        @test iomap.output isa JsonObject
        
        obj = iomap.output
        if show_detail
            println("  Table JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "persons"
        
        # Verify no parent references or selection fields
        @test !haskey(obj, "schema")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogColumnToJson tests ─────────────────────────────────────────────────

function test_db_catalog_column_to_json(; show_detail=false)
    @testset "DbCatalogColumnToJson" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        conn = DbCatalogConnection(adapter)
        db = DbCatalogDatabase(conn, "mydb")
        schema = DbCatalogSchema(db, "public")
        table = DbCatalogTable(schema, "persons")
        col = DbCatalogColumn(table, "name", "text")
        
        iomap = projection_print(DbCatalogColumnToJson(), col)
        @test iomap.output isa JsonObject
        
        obj = iomap.output
        if show_detail
            println("  Column JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test haskey(obj, "data_type")
        @test obj["name"][] == "name"
        @test obj["data_type"][] == "text"
        
        # Verify no parent references or selection fields
        @test !haskey(obj, "table")
        @test !haskey(obj, "selection")
    end
end

# ── TypeDispatchingProjection tests ─────────────────────────────────────────────

function test_db_catalog_to_json_dispatch(; show_detail=false)
    @testset "DbCatalogToJson type dispatching" begin
        adapter = OdbcDatabaseAdapter(dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=test;Uid=test;Pwd=test;", rowid_column="ctid")
        p = DbCatalogToJson()
        
        # Test dispatch for each type
        conn = DbCatalogConnection(adapter; host="testhost", port=5432)
        iomap1 = projection_print(p, conn)
        @test iomap1.output isa JsonObject
        @test iomap1.output["host"][] == "testhost"
        
        db = DbCatalogDatabase(conn, "testdb")
        iomap2 = projection_print(p, db)
        @test iomap2.output isa JsonObject
        @test iomap2.output["name"][] == "testdb"
        
        schema = DbCatalogSchema(db, "public")
        iomap3 = projection_print(p, schema)
        @test iomap3.output isa JsonObject
        @test iomap3.output["name"][] == "public"
        
        table = DbCatalogTable(schema, "persons")
        iomap4 = projection_print(p, table)
        @test iomap4.output isa JsonObject
        @test iomap4.output["name"][] == "persons"
        
        col = DbCatalogColumn(table, "age", "integer")
        iomap5 = projection_print(p, col)
        @test iomap5.output isa JsonObject
        @test iomap5.output["name"][] == "age"
        @test iomap5.output["data_type"][] == "integer"
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_json(; show_detail=false)
    @testset "DbCatalogToJson projection" begin
        test_db_catalog_connection_to_json(show_detail=show_detail)
        test_db_catalog_database_to_json(show_detail=show_detail)
        test_db_catalog_schema_to_json(show_detail=show_detail)
        test_db_catalog_table_to_json(show_detail=show_detail)
        test_db_catalog_column_to_json(show_detail=show_detail)
        test_db_catalog_to_json_dispatch(show_detail=show_detail)
    end
end

export test_db_catalog_json
