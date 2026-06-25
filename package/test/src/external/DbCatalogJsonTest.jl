using Test
using Projectured

# Tests for DbCatalogToJson projection. Pure construction — no live DB needed.
# Each DbCatalog document type projects to a JsonObject of its own data fields
# (excluding parent reference and selection) plus a nested array of its
# recursively-projected children, so the catalog renders as one nested JSON tree.
# These fixtures use empty child collections, so the children arrays are present
# but empty.

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
        @test obj["host"].value == "myhost"
        @test obj["port"].value == 5433

        # Children render as a nested (here empty) array; selection is excluded.
        @test haskey(obj, "databases")
        @test obj["databases"] isa JsonArray
        @test length(obj["databases"]) == 0
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
        @test obj["name"].value == "mydb"

        @test haskey(obj, "schemas")
        @test obj["schemas"] isa JsonArray
        @test length(obj["schemas"]) == 0
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
        @test obj["name"].value == "public"

        @test haskey(obj, "tables")
        @test obj["tables"] isa JsonArray
        @test length(obj["tables"]) == 0
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
        @test obj["name"].value == "persons"

        @test haskey(obj, "columns")
        @test obj["columns"] isa JsonArray
        @test length(obj["columns"]) == 0
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
        @test obj["name"].value == "name"
        @test obj["data_type"].value == "text"

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
        @test iomap1.output["host"].value == "testhost"

        db = DbCatalogDatabase("testdb", CellVector())
        iomap2 = projection_print(p, db)
        @test iomap2.output isa JsonObject
        @test iomap2.output["name"].value == "testdb"

        schema = DbCatalogSchema("public", CellVector())
        iomap3 = projection_print(p, schema)
        @test iomap3.output isa JsonObject
        @test iomap3.output["name"].value == "public"

        table = DbCatalogTable("persons", CellVector())
        iomap4 = projection_print(p, table)
        @test iomap4.output isa JsonObject
        @test iomap4.output["name"].value == "persons"

        col = DbCatalogColumn("age", "integer")
        iomap5 = projection_print(p, col)
        @test iomap5.output isa JsonObject
        @test iomap5.output["name"].value == "age"
        @test iomap5.output["data_type"].value == "integer"
    end
end

# ── Nested-walk test ─────────────────────────────────────────────────────────
# Wrapped in a RecursiveProjection, DbCatalogToJson fully walks the catalog: each
# level's children are recursively projected into its nested array. Builds a small
# rdbms → database → schema → table → column tree (no live DB) and descends it.

function test_db_catalog_to_json_walk(; show_detail=false)
    @testset "DbCatalogToJson nested walk" begin
        col    = DbCatalogColumn("id", "integer")
        table  = DbCatalogTable("film", CellVector(Cell[Cell(col)]))
        schema = DbCatalogSchema("public", CellVector(Cell[Cell(table)]))
        db     = DbCatalogDatabase("dvdrental", CellVector(Cell[Cell(schema)]))
        rdbms  = DbCatalogRdbms("localhost", 5432, CellVector(Cell[Cell(db)]))

        obj = projection_print(RecursiveProjection(DbCatalogToJson()), rdbms).output
        if show_detail
            println("  Nested catalog JSON: ", obj)
        end
        @test obj isa JsonObject
        @test length(obj["databases"]) == 1

        dbj = obj["databases"][1]
        @test dbj["name"].value == "dvdrental"
        @test length(dbj["schemas"]) == 1

        schemaj = dbj["schemas"][1]
        @test schemaj["name"].value == "public"
        @test length(schemaj["tables"]) == 1

        tablej = schemaj["tables"][1]
        @test tablej["name"].value == "film"
        @test length(tablej["columns"]) == 1

        colj = tablej["columns"][1]
        @test colj["name"].value == "id"
        @test colj["data_type"].value == "integer"
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
        test_db_catalog_to_json_walk(show_detail=show_detail)
    end
end

export test_db_catalog_json
