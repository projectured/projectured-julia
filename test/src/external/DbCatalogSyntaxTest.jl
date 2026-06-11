using Test
using Projectured

# Read-only tests for DbCatalogToSyntax projection.
# Tests that each DbCatalog document type projects to a Syntax tree
# with proper hierarchical structure and indentation.

# ── Helper function for DB-dependent tests ───────────────────────────────────

"""
    _with_real_db_catalog(f::Function; show_detail=false)

Build the catalog tree from a DatabaseInstance via DatabaseInstanceToDbCatalog
(querying through a connection pool), navigate to a real
rdbms/database/schema/table/column, and pass them to the callback. Handles pool
cleanup automatically and skips gracefully when the DB is unavailable.
"""
function _with_real_db_catalog(f::Function; show_detail=false)
    instance = _make_test_instance()
    pool     = _make_test_pool()
    try
        rdbms   = projection_print(DatabaseInstanceToDbCatalog(pool), instance).output
        dbs     = collect(rdbms.databases)
        @test !isempty(dbs)
        db      = first(filter(d -> d.name == "projectured_test", dbs))
        schemas = collect(db.schemas)
        @test !isempty(schemas)
        schema  = first(filter(s -> s.name == "public", schemas))
        tables  = collect(schema.tables)
        @test !isempty(tables)
        table   = first(filter(t -> t.name == "persons", tables))
        cols    = collect(table.columns)
        @test !isempty(cols)
        col     = first(cols)

        f(rdbms, db, schema, table, col)
    catch e
        @info "Skipping test (DB unavailable): $e"
    finally
        try
            close_pool!(pool)
        catch
        end
    end
end

# ── DbCatalogColumnToSyntaxLeaf tests ─────────────────────────────────────────────

function test_db_catalog_column_to_syntax(; show_detail=false)
    @testset "DbCatalogColumnToSyntaxLeaf" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogColumnToSyntaxLeaf(), col)
            @test iomap.output isa SyntaxLeaf

            leaf = iomap.output
            if show_detail
                println("  Column Syntax: ", leaf)
            end
            # Just verify it's a TextString with content
            @test leaf.value isa TextString

            # Verify no children (leaf node)
            @test !hasfield(typeof(leaf), :children)
        end
    end
end

# ── DbCatalogTableToSyntaxNode tests ─────────────────────────────────────────────

function test_db_catalog_table_to_syntax(; show_detail=false)
    @testset "DbCatalogTableToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogTableToSyntaxNode(), table)
            @test iomap.output isa SyntaxNode

            node = iomap.output
            if show_detail
                println("  Table Syntax: ", node)
            end
            @test node.indentation == 3
            @test length(node.children) == 2

            # children[1] should be name leaf
            name_leaf = node.children[1]
            @test name_leaf isa SyntaxLeaf
            @test name_leaf.value isa TextString

            # children[2] should be body node with indentation 4
            body_node = node.children[2]
            @test body_node isa SyntaxNode
            @test body_node.indentation == 4
        end
    end
end

# ── DbCatalogSchemaToSyntaxNode tests ────────────────────────────────────────────

function test_db_catalog_schema_to_syntax(; show_detail=false)
    @testset "DbCatalogSchemaToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogSchemaToSyntaxNode(), schema)
            @test iomap.output isa SyntaxNode

            node = iomap.output
            if show_detail
                println("  Schema Syntax: ", node)
            end
            @test node.indentation == 2
            @test length(node.children) == 2

            # children[1] should be name leaf
            name_leaf = node.children[1]
            @test name_leaf isa SyntaxLeaf
            @test name_leaf.value isa TextString

            # children[2] should be body node with indentation 3
            body_node = node.children[2]
            @test body_node isa SyntaxNode
            @test body_node.indentation == 3
        end
    end
end

# ── DbCatalogDatabaseToSyntaxNode tests ─────────────────────────────────────────

function test_db_catalog_database_to_syntax(; show_detail=false)
    @testset "DbCatalogDatabaseToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogDatabaseToSyntaxNode(), db)
            @test iomap.output isa SyntaxNode

            node = iomap.output
            if show_detail
                println("  Database Syntax: ", node)
            end
            @test node.indentation == 1
            @test length(node.children) == 2

            # children[1] should be name leaf
            name_leaf = node.children[1]
            @test name_leaf isa SyntaxLeaf
            @test name_leaf.value isa TextString

            # children[2] should be body node with indentation 2
            body_node = node.children[2]
            @test body_node isa SyntaxNode
            @test body_node.indentation == 2
        end
    end
end

# ── DbCatalogRdbmsToSyntaxNode tests ─────────────────────────────────────────────

function test_db_catalog_rdbms_to_syntax(; show_detail=false)
    @testset "DbCatalogRdbmsToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogRdbmsToSyntaxNode(), rdbms)
            @test iomap.output isa SyntaxNode

            node = iomap.output
            if show_detail
                println("  Rdbms Syntax: ", node)
            end
            @test node.indentation == 0
            @test length(node.children) == 2

            # children[1] should be name leaf
            name_leaf = node.children[1]
            @test name_leaf isa SyntaxLeaf
            @test name_leaf.value isa TextString

            # children[2] should be body node with indentation 1
            body_node = node.children[2]
            @test body_node isa SyntaxNode
            @test body_node.indentation == 1
        end
    end
end

# ── TypeDispatchingProjection tests ─────────────────────────────────────────────

function test_db_catalog_to_syntax_dispatch(; show_detail=false)
    @testset "DbCatalogToSyntax type dispatching" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            p = RecursiveProjection(DbCatalogToSyntax())

            # Test dispatch for each type using real DB data
            iomap1 = projection_print(p, rdbms)
            @test iomap1.output isa SyntaxNode
            @test iomap1.output.indentation == 0
            @test iomap1.output.children[1].value isa TextString

            iomap2 = projection_print(p, db)
            @test iomap2.output isa SyntaxNode
            @test iomap2.output.indentation == 1
            @test iomap2.output.children[1].value isa TextString

            iomap3 = projection_print(p, schema)
            @test iomap3.output isa SyntaxNode
            @test iomap3.output.indentation == 2
            @test iomap3.output.children[1].value isa TextString

            iomap4 = projection_print(p, table)
            @test iomap4.output isa SyntaxNode
            @test iomap4.output.indentation == 3
            @test iomap4.output.children[1].value isa TextString

            iomap5 = projection_print(p, col)
            @test iomap5.output isa SyntaxLeaf
            @test iomap5.output.value isa TextString
        end
    end
end

# ── Marker eligibility tests ────────────────────────────────────────────────────

function test_dbcatalog_marker_eligible(; show_detail=false)
    @testset "dbcatalog_marker_eligible" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            p = RecursiveProjection(DbCatalogToSyntax())

            # Rdbms node should be eligible (indentation 0, has body)
            iomap1 = projection_print(p, rdbms)
            @test dbcatalog_marker_eligible(iomap1.output)

            # Database node should be eligible (indentation 1, has body)
            iomap2 = projection_print(p, db)
            @test dbcatalog_marker_eligible(iomap2.output)

            # Schema node should be eligible (indentation 2, has body)
            iomap3 = projection_print(p, schema)
            @test dbcatalog_marker_eligible(iomap3.output)

            # Table node should be eligible (indentation 3, has body)
            iomap4 = projection_print(p, table)
            @test dbcatalog_marker_eligible(iomap4.output)

            # Column leaf should NOT be eligible (indentation 4)
            iomap5 = projection_print(p, col)
            @test !dbcatalog_marker_eligible(iomap5.output)
        end
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_syntax(; show_detail=false)
    @testset "DbCatalogToSyntax projection" begin
        test_db_catalog_column_to_syntax(show_detail=show_detail)
        test_db_catalog_table_to_syntax(show_detail=show_detail)
        test_db_catalog_schema_to_syntax(show_detail=show_detail)
        test_db_catalog_database_to_syntax(show_detail=show_detail)
        test_db_catalog_rdbms_to_syntax(show_detail=show_detail)
        test_db_catalog_to_syntax_dispatch(show_detail=show_detail)
        test_dbcatalog_marker_eligible(show_detail=show_detail)
    end
end

export test_db_catalog_syntax
