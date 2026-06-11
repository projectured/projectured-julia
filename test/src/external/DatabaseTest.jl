using Test
using Projectured

# ── Helpers that do not need a live DB ────────────────────────────────────────

function test_raw_database_result_show()
    @testset "RawDatabaseResult show" begin
        r = RawDatabaseResult(["name", "age"], [["Alice", 30], ["Bob", 25]])
        output = sprint(show, r)
        @test output == "name\tage\nAlice\t30\nBob\t25\n"
    end
end

function test_raw_database_result_struct()
    @testset "RawDatabaseResult struct" begin
        r = RawDatabaseResult(["x", "y"], [[1, 2], [3, 4]])
        @test r.columns == ["x", "y"]
        @test length(r.rows) == 2
        @test r.rows[1] == Any[1, 2]
        @test r.rows[2] == Any[3, 4]
    end
end

# ── Live-DB helpers (also used by DatabaseTabularTest) ────────────────────────

function _make_test_adapter()
    OdbcDatabaseAdapter(
        dsn=get(ENV, "TEST_ODBC_DSN",
                "Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
                "Database=projectured_test;" *
                "Uid=$(get(ENV, "PGUSER", "projectured"));" *
                "Pwd=$(get(ENV, "PGPASSWORD", "projectured"));"),
        rowid_column="ctid")
end

function _setup_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    db_execute_raw(adapter,
        "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    db_insert!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function _teardown_persons_table(adapter)
    db_execute_raw(adapter,
        "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end

# ── Live-DB tests ─────────────────────────────────────────────────────────────

function test_connect_close(adapter)
    @testset "T1 — connect / close" begin
        db_connect!(adapter)
        @test db_alive(adapter) == true
        db_close!(adapter)
        @test db_alive(adapter) == false
        db_connect!(adapter)   # reconnect for subsequent tests
    end
end

function test_insert(adapter)
    @testset "T2 — insert" begin
        count_before = db_query(adapter, "persons", RawDatabaseResult).rows |> length
        n = db_insert!(adapter, "persons", Dict("name" => "Bob", "age" => 25))
        @test n == 1
        count_after = db_query(adapter, "persons", RawDatabaseResult).rows |> length
        @test count_after == count_before + 1
    end
end

function test_query_to_raw(adapter)
    @testset "T3 — db_query into RawDatabaseResult" begin
        r = db_query(adapter, "persons", RawDatabaseResult)
        @test r isa RawDatabaseResult
        @test r.columns == ["name", "age"]
        @test length(r.rows) >= 1
        @test r.rows[1][1] isa String
    end
end

function test_update(adapter)
    @testset "T4 — update via db_update!" begin
        db_insert!(adapter, "persons", Dict("name" => "UpdateMe", "age" => 1))
        n = db_update!(adapter, "persons",
                       Dict("age" => 99),
                       "name = 'UpdateMe'")
        @test n == 1
        r = db_query(adapter, "persons", RawDatabaseResult; where="name = 'UpdateMe'")
        @test length(r.rows) == 1
        @test string(r.rows[1][2]) == "99"
    end
end

function test_delete(adapter)
    @testset "T5 — delete via db_delete!" begin
        db_insert!(adapter, "persons", Dict("name" => "DeleteMe", "age" => 0))
        n = db_delete!(adapter, "persons", "name = 'DeleteMe'")
        @test n == 1
        r = db_query(adapter, "persons", RawDatabaseResult; where="name = 'DeleteMe'")
        @test isempty(r.rows)
    end
end

function test_execute_raw(adapter)
    @testset "T6 — db_execute_raw into RawDatabaseResult" begin
        r = db_execute_raw(adapter,
                           "SELECT count(*) FROM persons",
                           RawDatabaseResult)
        @test r isa RawDatabaseResult
        @test length(r.rows) == 1
        @test parse(Int, string(r.rows[1][1])) >= 1
    end
end

# ── Entry points ──────────────────────────────────────────────────────────────

function test_database_connection()
    adapter = _make_test_adapter()
    @testset "Database connection" begin
        @test_nowarn db_connect!(adapter)
        @test db_alive(adapter) == true
        @test_nowarn db_close!(adapter)
        @test db_alive(adapter) == false
    end
end

function test_database_no_db()
    @testset "Database (no DB)" begin
        test_raw_database_result_show()
        test_raw_database_result_struct()
    end
end

function test_database(; skip_if_no_db=true)
    adapter = _make_test_adapter()
    can_connect = try
        db_connect!(adapter)
        true
    catch e
        skip_if_no_db && @info "Skipping live-DB tests (ODBC DSN unavailable): $e"
        false
    end

    test_database_no_db()

    can_connect || return

    @testset "Database (live DB)" begin
        try
            _setup_persons_table(adapter)
            test_connect_close(adapter)
            test_insert(adapter)
            test_query_to_raw(adapter)
            test_update(adapter)
            test_delete(adapter)
            test_execute_raw(adapter)
        finally
            db_close!(adapter)
        end
    end
end

export test_database_connection, test_database, test_database_no_db
