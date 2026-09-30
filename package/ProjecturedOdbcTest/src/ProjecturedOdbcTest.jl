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
using ProjecturedKernelTest

# Live-DB fixture helpers shared by the two suites (moved down with them from the
# umbrella). `execute_db_raw` / `insert_into_db!` / `RawDatabaseResult` come from
# `using ProjecturedOdbc`.
include("../../../test/adapter/odbc/OdbcSuite.jl")

end # module ProjecturedOdbcTest
