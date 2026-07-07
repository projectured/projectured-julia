"""
    ProjecturedOdbcTest

Test package for the opt-in `ProjecturedOdbc` adapter. Hosts the live-database
suites moved down from the umbrella:

- `DatabaseTest` — the ODBC adapter, raw execute/insert, and DDL round-trips;
- `DbCatalogTest` — the catalog introspection + DbCatalog projections.

Most tests skip when no database is reachable (`skip_if_no_db`), so the suite is
inert without a live DB. Needs the ODBC driver, so it precompiles and runs only
where that is installed. Resolves through the root env and uses the flat
`Projectured` namespace plus `ProjecturedOdbc`.
"""
module ProjecturedOdbcTest

using Test
using Projectured
using ProjecturedExample
using ProjecturedOdbc

# Live-DB fixture helpers shared by the two suites (moved down with them from the
# umbrella). `db_execute_raw` / `db_insert!` / `RawDatabaseResult` come from
# `using ProjecturedOdbc`.
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

end # module ProjecturedOdbcTest
