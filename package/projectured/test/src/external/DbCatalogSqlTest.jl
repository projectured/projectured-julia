using Test
using Projectured

# Tests for DbCatalogToSql projection. Pure construction — no live DB needed.
# Each DbCatalog document type projects directly to SQL DDL documents:
#   column → SqlColumnDefinition, table → CREATE TABLE, schema → CREATE SCHEMA
#   + its CREATE TABLEs (a SqlStatementList), database/rdbms → flattened list.
# The full pipeline (DbCatalog → Sql → Syntax → Text → String) renders the
# executable `CREATE …` script.

# Render a catalog node to its DDL text through the whole pipeline.
_ddl_pipe() = ChainingProjection(
    RecursiveProjection(DbCatalogToSql()),
    RecursiveProjection(SqlToSyntax()),
    RecursiveProjection(SyntaxToText()),
    RecursiveProjection(TextToString()))
_catalog_ddl(node) = print_document(_ddl_pipe(), node).output[]

# ── Per-type construction ─────────────────────────────────────────────────────

function test_db_catalog_column_to_sql()
    @testset "DbCatalogColumnToSql" begin
        out = print_document(DbCatalogColumnToSql(), DbCatalogColumn("title", "text")).output
        @test out isa SqlColumnDefinition
        @test out.column_name.name == "title"
        @test out.data_type == "text"
    end
end

function test_db_catalog_table_to_sql()
    @testset "DbCatalogTableToSql" begin
        table = DbCatalogTable("film", CellVector(Cell[
            Cell(DbCatalogColumn("title", "text")),
            Cell(DbCatalogColumn("length", "integer"))]))

        # Standalone (no enclosing schema): unqualified table name.
        out = print_document(RecursiveProjection(DbCatalogToSql()), table).output
        @test out isa SqlCreateTableStatement
        @test out.table_name.schema_name === nothing
        @test out.table_name.name == "film"
        @test length(out.columns) == 2
        @test out.columns[1].column_name.name == "title"
        @test out.columns[2].data_type == "integer"

        @test _catalog_ddl(table) ==
            "CREATE TABLE film (\n  title text,\n  length integer\n);"
    end
end

function test_db_catalog_schema_to_sql()
    @testset "DbCatalogSchemaToSql" begin
        film  = DbCatalogTable("film", CellVector(Cell[Cell(DbCatalogColumn("title", "text"))]))
        actor = DbCatalogTable("actor", CellVector(Cell[Cell(DbCatalogColumn("first_name", "text"))]))
        schema = DbCatalogSchema("public", CellVector(Cell[Cell(film), Cell(actor)]))

        out = print_document(RecursiveProjection(DbCatalogToSql()), schema).output
        @test out isa SqlStatementList
        # CREATE SCHEMA + one CREATE TABLE per table.
        @test length(out.statements) == 3
        @test out.statements[1] isa SqlCreateSchemaStatement
        @test out.statements[1].schema_name == "public"
        @test out.statements[2] isa SqlCreateTableStatement
        # Tables are schema-qualified through the threaded context.
        @test out.statements[2].table_name.schema_name == "public"
        @test out.statements[2].table_name.name == "film"

        @test _catalog_ddl(schema) ==
            "CREATE SCHEMA public;\n\n" *
            "CREATE TABLE public.film (\n  title text\n);\n\n" *
            "CREATE TABLE public.actor (\n  first_name text\n);"
    end
end

function test_db_catalog_database_to_sql()
    @testset "DbCatalogDatabaseToSql flattens schemas" begin
        film   = DbCatalogTable("film", CellVector(Cell[Cell(DbCatalogColumn("title", "text"))]))
        schema = DbCatalogSchema("public", CellVector(Cell[Cell(film)]))
        db     = DbCatalogDatabase("dvdrental", CellVector(Cell[Cell(schema)]))

        out = print_document(RecursiveProjection(DbCatalogToSql()), db).output
        @test out isa SqlStatementList
        # Flattened: CREATE SCHEMA + CREATE TABLE (not a nested list).
        @test length(out.statements) == 2
        @test out.statements[1] isa SqlCreateSchemaStatement
        @test out.statements[2] isa SqlCreateTableStatement

        @test _catalog_ddl(db) ==
            "CREATE SCHEMA public;\n\nCREATE TABLE public.film (\n  title text\n);"
    end
end

function test_db_catalog_rdbms_to_sql()
    @testset "DbCatalogRdbmsToSql flattens databases" begin
        film   = DbCatalogTable("film", CellVector(Cell[Cell(DbCatalogColumn("title", "text"))]))
        schema = DbCatalogSchema("public", CellVector(Cell[Cell(film)]))
        db     = DbCatalogDatabase("dvdrental", CellVector(Cell[Cell(schema)]))
        rdbms  = DbCatalogRdbms("localhost", 5432, CellVector(Cell[Cell(db)]))

        out = print_document(RecursiveProjection(DbCatalogToSql()), rdbms).output
        @test out isa SqlStatementList
        @test length(out.statements) == 2
        @test out.statements[1] isa SqlCreateSchemaStatement
        @test out.statements[2] isa SqlCreateTableStatement
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_sql()
    @testset "DbCatalogToSql projection" begin
        test_db_catalog_column_to_sql()
        test_db_catalog_table_to_sql()
        test_db_catalog_schema_to_sql()
        test_db_catalog_database_to_sql()
        test_db_catalog_rdbms_to_sql()
    end
end

export test_db_catalog_sql
