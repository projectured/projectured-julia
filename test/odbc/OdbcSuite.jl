function setup_persons_table(adapter)
    db_execute_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
    db_execute_raw(adapter, "CREATE TABLE persons (name TEXT, age INT)", RawDatabaseResult)
    db_insert!(adapter, "persons", Dict("name" => "Alice", "age" => 30))
end

function teardown_persons_table(adapter)
    db_execute_raw(adapter, "DROP TABLE IF EXISTS persons", RawDatabaseResult)
end

include("external/DatabaseTest.jl")
include("external/DbCatalogTest.jl")
include("external/DbCatalogSyntaxTest.jl")

"Run the ODBC database + catalog suite (skips when no DB is reachable)."
function test_odbc()
    @testset "ProjecturedOdbc" begin
        test_database_no_db()
        test_database()
        test_db_catalog()
        test_db_catalog_syntax()
    end
end

export test_odbc, test_database, test_database_no_db, test_db_catalog, test_db_catalog_syntax
