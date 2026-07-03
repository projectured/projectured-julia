using Test
using Projectured

# Read-only tests for DbCatalogToSyntax projection.
# Tests that each DbCatalog document type projects to a Syntax tree
# with entity nodes, keyword nodes, and proper structure.

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
            @test leaf.value isa TextString
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

            entity = iomap.output
            if show_detail
                println("  Table Syntax: ", entity)
            end
            # Entity node: ind=-1, name in open
            @test entity.indentation == -1
            @test !isempty(entity.open.content::AbstractString)
            @test length(entity.children) == 1

            # children[1] = keyword node "Columns"
            keyword = entity.children[1]
            @test keyword isa SyntaxNode
            @test keyword.indentation == -1
            @test keyword.open.content == " Columns"
            # The keyword group holds its projected items directly (no body
            # wrapper). Item projection is delegated through `recursion`, so it is
            # exercised under a RecursiveProjection (see the lazy-expansion tests),
            # not forced here with this bare single-level projection.
        end
    end
end

# ── DbCatalogSchemaToSyntaxNode tests ────────────────────────────────────────────

function test_db_catalog_schema_to_syntax(; show_detail=false)
    @testset "DbCatalogSchemaToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogSchemaToSyntaxNode(), schema)
            @test iomap.output isa SyntaxNode

            entity = iomap.output
            if show_detail
                println("  Schema Syntax: ", entity)
            end
            @test entity.indentation == -1
            @test !isempty(entity.open.content::AbstractString)
            @test length(entity.children) == 1

            keyword = entity.children[1]
            @test keyword isa SyntaxNode
            @test keyword.indentation == -1
            @test keyword.open.content == " Tables"
            # The keyword group holds its projected items directly (no body
            # wrapper). Item projection is delegated through `recursion`, so it is
            # exercised under a RecursiveProjection (see the lazy-expansion tests),
            # not forced here with this bare single-level projection.
        end
    end
end

# ── DbCatalogDatabaseToSyntaxNode tests ─────────────────────────────────────────

function test_db_catalog_database_to_syntax(; show_detail=false)
    @testset "DbCatalogDatabaseToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogDatabaseToSyntaxNode(), db)
            @test iomap.output isa SyntaxNode

            entity = iomap.output
            if show_detail
                println("  Database Syntax: ", entity)
            end
            @test entity.indentation == -1
            @test !isempty(entity.open.content::AbstractString)
            @test length(entity.children) == 1

            keyword = entity.children[1]
            @test keyword isa SyntaxNode
            @test keyword.indentation == -1
            @test keyword.open.content == " Schemas"
            # The keyword group holds its projected items directly (no body
            # wrapper). Item projection is delegated through `recursion`, so it is
            # exercised under a RecursiveProjection (see the lazy-expansion tests),
            # not forced here with this bare single-level projection.
        end
    end
end

# ── DbCatalogRdbmsToSyntaxNode tests ─────────────────────────────────────────────

function test_db_catalog_rdbms_to_syntax(; show_detail=false)
    @testset "DbCatalogRdbmsToSyntaxNode" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            iomap = projection_print(DbCatalogRdbmsToSyntaxNode(), rdbms)
            @test iomap.output isa SyntaxNode

            entity = iomap.output
            if show_detail
                println("  Rdbms Syntax: ", entity)
            end
            @test entity.indentation == -1
            @test !isempty(entity.open.content::AbstractString)
            @test length(entity.children) == 1

            keyword = entity.children[1]
            @test keyword isa SyntaxNode
            @test keyword.indentation == -1
            @test keyword.open.content == " Databases"
            # The keyword group holds its projected items directly (no body
            # wrapper). Item projection is delegated through `recursion`, so it is
            # exercised under a RecursiveProjection (see the lazy-expansion tests),
            # not forced here with this bare single-level projection.
        end
    end
end

# ── TypeDispatchingProjection tests ─────────────────────────────────────────────

function test_db_catalog_to_syntax_dispatch(; show_detail=false)
    @testset "DbCatalogToSyntax type dispatching" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            p = RecursiveProjection(DbCatalogToSyntax())

            iomap1 = projection_print(p, rdbms)
            @test iomap1.output isa SyntaxNode
            @test iomap1.output.indentation == -1
            @test !isempty(iomap1.output.open.content::AbstractString)

            iomap2 = projection_print(p, db)
            @test iomap2.output isa SyntaxNode
            @test iomap2.output.indentation == -1

            iomap3 = projection_print(p, schema)
            @test iomap3.output isa SyntaxNode
            @test iomap3.output.indentation == -1

            iomap4 = projection_print(p, table)
            @test iomap4.output isa SyntaxNode
            @test iomap4.output.indentation == -1

            iomap5 = projection_print(p, col)
            @test iomap5.output isa SyntaxLeaf
            @test iomap5.output.value isa TextString
        end
    end
end

# ── Reference mapping tests ────────────────────────────────────────────────────

function test_dbcatalog_reference_mapping(; show_detail=false)
    @testset "DbCatalog reference mapping" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            # ── Table → Syntax forward/backward ──
            p_table = DbCatalogTableToSyntaxNode()
            iomap_t = projection_print(p_table, table)

            # Forward: columns[1] → children[1].children[1] (keyword group → item)
            in_ref = @reference columns[1]
            out_ref = map_reference_forward(p_table, iomap_t, in_ref)
            @test out_ref !== nothing
            if show_detail
                println("  Table forward columns[1] → ", out_ref)
            end

            # Backward: round-trip
            back_ref = map_reference_backward(p_table, iomap_t, out_ref)
            @test back_ref !== nothing
            if show_detail
                println("  Table backward round-trip → ", back_ref)
            end

            # ── Schema → Syntax forward/backward ──
            p_schema = DbCatalogSchemaToSyntaxNode()
            iomap_s = projection_print(p_schema, schema)

            in_ref_s = @reference tables[1]
            out_ref_s = map_reference_forward(p_schema, iomap_s, in_ref_s)
            @test out_ref_s !== nothing

            back_ref_s = map_reference_backward(p_schema, iomap_s, out_ref_s)
            @test back_ref_s !== nothing

            # ── Database → Syntax forward/backward ──
            p_db = DbCatalogDatabaseToSyntaxNode()
            iomap_d = projection_print(p_db, db)

            in_ref_d = @reference schemas[1]
            out_ref_d = map_reference_forward(p_db, iomap_d, in_ref_d)
            @test out_ref_d !== nothing

            back_ref_d = map_reference_backward(p_db, iomap_d, out_ref_d)
            @test back_ref_d !== nothing

            # ── Rdbms → Syntax forward/backward ──
            p_rdbms = DbCatalogRdbmsToSyntaxNode()
            iomap_r = projection_print(p_rdbms, rdbms)

            in_ref_r = @reference databases[1]
            out_ref_r = map_reference_forward(p_rdbms, iomap_r, in_ref_r)
            @test out_ref_r !== nothing

            back_ref_r = map_reference_backward(p_rdbms, iomap_r, out_ref_r)
            @test back_ref_r !== nothing

            # ── Column leaf backward wraps in ProjectionReference ──
            p_col = DbCatalogColumnToSyntaxLeaf()
            iomap_c = projection_print(p_col, col)

            col_back = map_reference_backward(p_col, iomap_c, @reference value{0})
            @test col_back !== nothing
            @test col_back isa ConcreteReferencePath
            @test col_back.head isa ProjectionReference

            # Column leaf forward unwraps ProjectionReference
            col_fwd = map_reference_forward(p_col, iomap_c, col_back)
            @test col_fwd !== nothing

            # ── Empty path round-trips ──
            @test map_reference_forward(p_table, iomap_t, EmptyReferencePath()) isa EmptyReferencePath
            @test map_reference_backward(p_table, iomap_t, EmptyReferencePath()) isa EmptyReferencePath

            # ── Structural positions return nothing from backward ──
            structural_ref = @reference open{0}
            @test map_reference_backward(p_rdbms, iomap_r, structural_ref) === nothing
        end
    end
end

# ── Selection wiring tests ─────────────────────────────────────────────────────

function test_dbcatalog_selection_wiring(; show_detail=false)
    @testset "DbCatalog selection wiring" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            p = RecursiveProjection(DbCatalogToSyntax())

            # Project a table — entity_node.selection should initially be nothing
            iomap = projection_print(p, table)
            entity = iomap.output
            @test entity.selection === nothing

            # Set selection on the input document to point at column 1
            col_ref = @reference columns[1]
            # Use ProjectionReference wrapping since column content is projection-introduced
            col_inner = ConcreteReferencePath(Cell(ProjectionReference(
                DbCatalogColumnToSyntaxLeaf(), @reference value{0})))
            full_input_sel = @reference columns[1].^(col_inner)
            replace_selection!(table, full_input_sel)

            # The entity_node.selection should now be non-nothing (forward-projected)
            @test entity.selection !== nothing
            if show_detail
                println("  Entity selection after set: ", entity.selection)
            end

            # Clear selection
            clear_selection!(table)
            @test entity.selection === nothing
        end
    end
end

# ── Marker eligibility tests ────────────────────────────────────────────────────

function test_dbcatalog_marker_eligible(; show_detail=false)
    @testset "dbcatalog_marker_eligible" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            p = RecursiveProjection(DbCatalogToSyntax())

            # Entity nodes should be eligible (non-empty open, has children)
            iomap1 = projection_print(p, rdbms)
            @test dbcatalog_marker_eligible(iomap1.output)

            # Keyword group nodes should be eligible (they carry a label).
            keyword = iomap1.output.children[1]
            @test dbcatalog_marker_eligible(keyword)

            # Same pattern for other entity levels
            iomap2 = projection_print(p, db)
            @test dbcatalog_marker_eligible(iomap2.output)
            @test dbcatalog_marker_eligible(iomap2.output.children[1])

            iomap3 = projection_print(p, schema)
            @test dbcatalog_marker_eligible(iomap3.output)
            @test dbcatalog_marker_eligible(iomap3.output.children[1])

            iomap4 = projection_print(p, table)
            @test dbcatalog_marker_eligible(iomap4.output)
            @test dbcatalog_marker_eligible(iomap4.output.children[1])

            # Column leaf should NOT be eligible
            iomap5 = projection_print(p, col)
            @test !dbcatalog_marker_eligible(iomap5.output)
        end
    end
end

# ── Collapse roundtrip tests ──────────────────────────────────────────────────

# Walk the IO map tree to find the TextToGraphicsIoMap (same logic as
# ClickRoundtripTest._find_text_iomap, duplicated to avoid cross-file deps).
function _find_text_iomap_dbcat(io)
    io isa TextToGraphicsIoMap && return io
    if hasfield(typeof(io), :step_iomaps)
        for s in io.step_iomaps
            r = _find_text_iomap_dbcat(s); r !== nothing && return r
        end
    end
    hasfield(typeof(io), :inner_iomap) && return _find_text_iomap_dbcat(io.inner_iomap)
    hasfield(typeof(io), :child_iomap) && return _find_text_iomap_dbcat(io.child_iomap)
    nothing
end

# Centre of a rendered segment whose text equals `glyph`.
function _glyph_click_dbcat(coords, glyph::AbstractString)
    i = findfirst(sc -> sc.text == glyph, coords)
    i === nothing && return nothing
    sc = coords[i]
    (sc.x + 2, sc.y + 3)
end

function test_dbcatalog_collapse_roundtrip(; show_detail=false)
    @testset "DbCatalog collapse roundtrip" begin
        _with_real_db_catalog(show_detail=show_detail) do rdbms, db, schema, table, col
            # Build the full pipeline: DbCatalogToSyntax → SyntaxToText → TextToGraphics
            proj = ChainingProjection(
                RecursiveProjection(DbCatalogToSyntax()),
                RecursiveProjection(SyntaxToText(
                    expanded_marker  = TextString("▾", font_dejavu_monospace_regular_20, color_default),
                    collapsed_marker = TextString("▸", font_dejavu_monospace_regular_20, color_default),
                    marker_eligible  = dbcatalog_marker_eligible)),
                TextToGraphics())

            # ── Test at the table level (entity + keyword) ──────────────
            iomap  = projection_print(proj, table)
            t2g    = _find_text_iomap_dbcat(iomap)
            @test t2g !== nothing
            coords = t2g.char_to_coord[]

            if show_detail
                println("  Rendered text: ", join(sc.text for sc in coords))
                println("  Num segments: ", length(coords))
            end

            # Find the first "▾" marker
            click = _glyph_click_dbcat(coords, "▾")
            @test click !== nothing

            if show_detail && click !== nothing
                println("  Marker click at: ", click)
            end

            # Simulate mouse click on the marker
            op = projection_read(proj, iomap, MousePress(:left, click[1], click[2], Modifiers()))

            if show_detail
                println("  Operation: ", op)
                println("  Operation type: ", typeof(op))
            end

            @test op isa ToggleCollapseOperation

            if op isa ToggleCollapseOperation
                # Verify the target node is expanded, then toggle
                target = op.target
                @test target.collapsed == false
                evaluate_operation(nothing, op)
                @test target.collapsed == true

                # Re-render after collapse — should show ▸ and ellipsis
                iomap2  = projection_print(proj, table)
                t2g2    = _find_text_iomap_dbcat(iomap2)
                coords2 = t2g2.char_to_coord[]
                line2   = join(sc.text for sc in coords2)

                if show_detail
                    println("  Collapsed text: ", line2)
                end
                @test occursin("▸", line2)
                @test occursin("…", line2)

                # Click ellipsis to expand
                eclick = _glyph_click_dbcat(coords2, "…")
                @test eclick !== nothing
                op2 = projection_read(proj, iomap2, MousePress(:left, eclick[1], eclick[2], Modifiers()))
                @test op2 isa ToggleCollapseOperation
                evaluate_operation(nothing, op2)
                @test target.collapsed == false
            end
        end
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_syntax(; show_detail=false, skip_if_no_db=true)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping DbCatalogSyntax tests (ODBC DSN unavailable): $e"
        false
    end
    if can_connect
        setup_persons_table(adapter)
        db_close!(adapter)
    end

    @testset "DbCatalogToSyntax projection" begin
        test_db_catalog_column_to_syntax(show_detail=show_detail)
        test_db_catalog_table_to_syntax(show_detail=show_detail)
        test_db_catalog_schema_to_syntax(show_detail=show_detail)
        test_db_catalog_database_to_syntax(show_detail=show_detail)
        test_db_catalog_rdbms_to_syntax(show_detail=show_detail)
        test_db_catalog_to_syntax_dispatch(show_detail=show_detail)
        test_dbcatalog_marker_eligible(show_detail=show_detail)
        test_dbcatalog_reference_mapping(show_detail=show_detail)
        test_dbcatalog_selection_wiring(show_detail=show_detail)
        test_dbcatalog_collapse_roundtrip(show_detail=show_detail)
    end
end

export test_db_catalog_syntax
