using Test
using Projectured

# ── Live-DB tests (all require a live DB; shared helpers are in DatabaseTest) ─

function test_query_to_tabular_grid(adapter)
    @testset "T1 — db_query into TabularGrid" begin
        g = db_query(adapter, "persons", TabularGrid)
        @test g isa TabularGrid
        @test g.col_count == 2
        nrows = length(g.rows)
        @test nrows >= 2   # at least header + 1 data row
    end
end

function test_header_content(adapter)
    @testset "T2 — header row content" begin
        g = db_query(adapter, "persons", TabularGrid)
        header_row = g.rows[1]
        @test header_row isa TabularRow
        first_cell = header_row.cells[1]
        @test first_cell isa TabularCell
        @test first_cell.content == "name"
        second_cell = header_row.cells[2]
        @test second_cell.content == "age"
    end
end

function test_query_filtered(adapter)
    @testset "T3 — db_query filtered" begin
        db_insert!(adapter, "persons", Dict("name" => "Charlie", "age" => 15))
        g = db_query(adapter, "persons", TabularGrid; where="age > 20")
        nrows = length(g.rows)
        @test nrows >= 2   # header + at least one row where age > 20
        for ri in 2:nrows
            cell = g.rows[ri].cells[2]
            @test parse(Int, string(cell.content)) > 20
        end
    end
end

function test_projection_print(adapter)
    @testset "T4 (proj) — print_document produces DatabaseTableIoMap" begin
        doc = DatabaseTable(adapter, "persons")
        p   = DatabaseTableToTabularGrid()
        iomap = print_document(p, doc)
        @test iomap isa DatabaseTableIoMap
        g = iomap.output
        @test g isa TabularGrid
        @test g.col_count == 2
        @test length(g.rows) >= 2
    end
end

function test_ctid_values_captured(adapter)
    @testset "T5 (proj) — ctid values captured" begin
        doc = DatabaseTable(adapter, "persons")
        p   = DatabaseTableToTabularGrid()
        iomap = print_document(p, doc)
        ctids = iomap.ctid_values[]
        @test length(ctids) == length(iomap.output.rows) - 1  # exclude header
        @test all(c -> c !== nothing, ctids)
    end
end

function test_projection_read_header_readonly(adapter)
    @testset "T6 (proj) — header row is read-only" begin
        doc   = DatabaseTable(adapter, "persons")
        p     = DatabaseTableToTabularGrid()
        iomap = print_document(p, doc)
        ref   = @reference rows[1].cells[1].content.value{0:3}
        op    = ReplaceStringRangeOperation(ref, "XYZ")
        result = read_intent(p, iomap, op)
        @test result === nothing
    end
end

function test_projection_read_data_row(adapter)
    @testset "T7 (proj) — data row edit → DatabaseUpdateOperation" begin
        doc   = DatabaseTable(adapter, "persons")
        p     = DatabaseTableToTabularGrid()
        iomap = print_document(p, doc)
        ref   = @reference rows[2].cells[1].content.value{0:5}
        op    = ReplaceStringRangeOperation(ref, "Dave")
        result = read_intent(p, iomap, op)
        @test result isa DatabaseUpdateOperation
        @test result.column == "name"
        @test result.table  == "persons"
        @test result.ctid   == iomap.ctid_values[][1]
    end
end

# ── Entry point ───────────────────────────────────────────────────────────────

function test_database_tabular(; skip_if_no_db=true)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping live-DB tabular tests (ODBC DSN unavailable): $e"
        false
    end

    can_connect || return

    @testset "DatabaseTabular (live DB)" begin
        try
            _setup_persons_table(adapter)
            test_query_to_tabular_grid(adapter)
            test_header_content(adapter)
            test_query_filtered(adapter)
            test_projection_print(adapter)
            test_ctid_values_captured(adapter)
            test_projection_read_header_readonly(adapter)
            test_projection_read_data_row(adapter)
        finally
            _teardown_persons_table(adapter)
            db_close!(adapter)
        end
    end
end

export test_database_tabular
