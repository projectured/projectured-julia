using Test
using Projectured

# ── Live-DB tests (all require a live DB; shared helpers are in DatabaseTest) ─

function test_db_catalog_tabular_grid(adapter; show_detail=false)
    @testset "TabularGrid — DbCatalogTableToTabularGrid on persons" begin
        conn   = DbCatalogConnection(adapter)
        show_detail && println("  conn:   ", conn)
        db     = DbCatalogDatabase(conn, "projectured_test")
        show_detail && println("  db:     ", db)
        schema = DbCatalogSchema(db, "public")
        show_detail && println("  schema: ", schema)
        table  = DbCatalogTable(schema, "persons")
        show_detail && println("  table:  ", table)

        iomap = projection_print(DbCatalogTableToTabularGrid(), table)
        @test iomap isa DbCatalogTableIoMap
        g = iomap.output
        @test g isa TabularGrid
        @test g.col_count == 2

        nrows = length(g.rows)
        @test nrows >= 2  # header + at least Alice

        header = g.rows[1]
        @test header isa TabularRow
        @test header.cells[1].content == "name"
        @test header.cells[2].content == "age"

        data_row = g.rows[2]
        @test data_row isa TabularRow
        @test data_row.cells[1].content == "Alice"
        @test string(data_row.cells[2].content) == "30"

        ctids = iomap.ctid_values[]
        @test length(ctids) == nrows - 1
        @test all(c -> c !== nothing, ctids)

        if show_detail
            col_names = iomap.column_names[]
            println("  ", join(col_names, "\t"))
            for ri in 2:nrows
                vals = [string(g.rows[ri].cells[ci].content) for ci in 1:length(col_names)]
                println("  ", join(vals, "\t"))
            end
        end
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_tabular(; skip_if_no_db=true, show_detail=false)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping DbCatalogTabular tests (PostgreSQL unavailable): $e"
        false
    end

    can_connect || return

    @testset "DbCatalogTabular (live DB)" begin
        try
            test_db_catalog_tabular_grid(adapter; show_detail)
        finally
            db_close!(adapter)
        end
    end
end

export test_db_catalog_tabular
