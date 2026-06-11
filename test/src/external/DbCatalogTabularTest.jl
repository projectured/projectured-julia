using Test
using Projectured

# Live-DB tests for the SQL result path: SqlSelectStatement → CellTable → TableTable.
#
# This replaces the old DbCatalogTableToTabularGrid path (which navigated a
# parent-pointer chain to an embedded adapter — removed in the catalog refactor).
# In-place, ctid-based editing of result grids is deferred to a later stage; v1 is
# a read-only result table.
#
# Read-only: queries the existing `persons` table and asserts structure rather
# than specific data, so it does not depend on (or mutate) table contents.

function test_sql_to_cell_table(instance, pool; show_detail=false)
    @testset "SqlToCellTable → CellTable on persons" begin
        stmt = SqlSelectStatement("persons")
        ct = projection_print(SqlToCellTable(pool, instance), stmt).output
        @test ct isa CellTable

        nr, nc = size(ct)
        @test nc >= 2          # persons has at least name + age
        @test nr >= 1          # at least the header row

        header = String[string(ct[1, c]) for c in 1:nc]
        @test "name" in header
        @test "age"  in header

        if show_detail
            for r in 1:nr
                println("  ", join((string(ct[r, c]) for c in 1:nc), "\t"))
            end
        end
    end
end

function test_cell_table_to_table(instance, pool)
    @testset "CellTableToTable → TableTable" begin
        stmt = SqlSelectStatement("persons")
        ct = projection_print(SqlToCellTable(pool, instance), stmt).output
        nr, nc = size(ct)

        tt = projection_print(CellTableToTable(), ct).output
        @test tt isa TableTable
        @test length(tt.columns) == nc                  # one column per result column
        @test length(tt.rows)    == max(0, nr - 1)       # one row per data row
        @test length(tt.cells)   == max(0, nr - 1) * nc  # row-major data cells
    end
end

# ── Entry point ────────────────────────────────────────────────────────────────

function test_db_catalog_tabular(; skip_if_no_db=true, show_detail=false)
    adapter  = _make_test_adapter()
    instance = _make_test_instance()
    pool     = _make_test_pool()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping DbCatalogTabular tests (ODBC DSN unavailable): $e"
        false
    end

    can_connect || return

    @testset "DbCatalogTabular (live DB) — SQL result path" begin
        try
            test_sql_to_cell_table(instance, pool; show_detail)
            test_cell_table_to_table(instance, pool)
        finally
            db_close!(adapter)
            close_pool!(pool)
        end
    end
end

export test_db_catalog_tabular
