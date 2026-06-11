using Test
using Projectured

# Tests for DbCatalogToJson projection. Pure construction — no live DB needed.
# Each DbCatalog document type projects to a JsonObject containing only its own
# data fields (excluding child collections and selection).

# ── DbCatalogRdbmsToJson tests ───────────────────────────────────────────────────

function test_db_catalog_rdbms_to_json(; show_detail=false)
    @testset "DbCatalogRdbmsToJson" begin
        rdbms = DbCatalogRdbms("myhost", 5433, CellVector())

        iomap = projection_print(DbCatalogRdbmsToJson(), rdbms)
        @test iomap.output isa JsonObject

        obj = iomap.output
        if show_detail
            println("  Rdbms JSON: ", obj)
        end
        @test haskey(obj, "host")
        @test haskey(obj, "port")
        @test obj["host"][] == "myhost"
        @test obj["port"][] == 5433

        # Verify no child collections or selection fields
        @test !haskey(obj, "databases")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogDatabaseToJson tests ───────────────────────────────────────────────

function test_db_catalog_database_to_json(; show_detail=false)
    @testset "DbCatalogDatabaseToJson" begin
        db = DbCatalogDatabase("mydb", CellVector())

        iomap = projection_print(DbCatalogDatabaseToJson(), db)
        @test iomap.output isa JsonObject

        obj = iomap.output
        if show_detail
            println("  Database JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "mydb"

        @test !haskey(obj, "schemas")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogSchemaToJson tests ─────────────────────────────────────────────────

function test_db_catalog_schema_to_json(; show_detail=false)
    @testset "DbCatalogSchemaToJson" begin
        schema = DbCatalogSchema("public", CellVector())

        iomap = projection_print(DbCatalogSchemaToJson(), schema)
        @test iomap.output isa JsonObject

        obj = iomap.output
        if show_detail
            println("  Schema JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "public"

        @test !haskey(obj, "tables")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogTableToJson tests ───────────────────────────────────────────────────

function test_db_catalog_table_to_json(; show_detail=false)
    @testset "DbCatalogTableToJson" begin
        table = DbCatalogTable("persons", CellVector())

        iomap = projection_print(DbCatalogTableToJson(), table)
        @test iomap.output isa JsonObject

        obj = iomap.output
        if show_detail
            println("  Table JSON: ", obj)
        end
        @test haskey(obj, "name")
        @test obj["name"][] == "persons"

        @test !haskey(obj, "columns")
        @test !haskey(obj, "selection")
    end
end

# ── DbCatalogColumnToJson tests ─────────────────────────────────────────────────

function test_db_catalog_column_to_json(; show_detail=false)
    @testset "DbCatalogColumnToJson" begin
        col = DbCatalogColumn("name", "text")

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

        @test !haskey(obj, "selection")
    end
end

# ── TypeDispatchingProjection tests ─────────────────────────────────────────────

function test_db_catalog_to_json_dispatch(; show_detail=false)
    @testset "DbCatalogToJson type dispatching" begin
        p = DbCatalogToJson()

        rdbms = DbCatalogRdbms("testhost", 5432, CellVector())
        iomap1 = projection_print(p, rdbms)
        @test iomap1.output isa JsonObject
        @test iomap1.output["host"][] == "testhost"

        db = DbCatalogDatabase("testdb", CellVector())
        iomap2 = projection_print(p, db)
        @test iomap2.output isa JsonObject
        @test iomap2.output["name"][] == "testdb"

        schema = DbCatalogSchema("public", CellVector())
        iomap3 = projection_print(p, schema)
        @test iomap3.output isa JsonObject
        @test iomap3.output["name"][] == "public"

        table = DbCatalogTable("persons", CellVector())
        iomap4 = projection_print(p, table)
        @test iomap4.output isa JsonObject
        @test iomap4.output["name"][] == "persons"

        col = DbCatalogColumn("age", "integer")
        iomap5 = projection_print(p, col)
        @test iomap5.output isa JsonObject
        @test iomap5.output["name"][] == "age"
        @test iomap5.output["data_type"][] == "integer"
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_json(; show_detail=false)
    @testset "DbCatalogToJson projection" begin
        test_db_catalog_rdbms_to_json(show_detail=show_detail)
        test_db_catalog_database_to_json(show_detail=show_detail)
        test_db_catalog_schema_to_json(show_detail=show_detail)
        test_db_catalog_table_to_json(show_detail=show_detail)
        test_db_catalog_column_to_json(show_detail=show_detail)
        test_db_catalog_to_json_dispatch(show_detail=show_detail)
    end
end

export test_db_catalog_json
