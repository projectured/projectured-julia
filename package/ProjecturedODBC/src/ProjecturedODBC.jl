"""
    Odbc

Opt-in package: live ODBC database access (OdbcDatabaseAdapter, connection pool,
and the live-query projections). Depends on `ProjecturedPlatform` + ODBC/DBInterface/
Tables; `using ProjecturedODBC` registers `make_database_adapter(:odbc)` and exposes
the adapter, pool, and live-query projection types. (The SQL/DbCatalog documents and
their pure projections stay in `ProjecturedPlatform` — only live querying lives here.)
"""
module ProjecturedODBC

using ProjecturedDatabase
using ProjecturedDBCatalog
using ProjecturedKernel
using ProjecturedPlatform
using ProjecturedSQL

include("../../../source/adapter/odbc/OdbcModule.jl")

# Re-export and export public symbols at the package top level so consumers can
# `using ProjecturedODBC` and name these types directly.
using .OdbcModule: OdbcDatabaseAdapter
using .OdbcModule: OdbcConnectionPool, with_connection, get_dsn, close_pool!
using .OdbcModule: SqlToCellTable
using .OdbcModule: DatabaseInstanceToDbCatalog

export OdbcDatabaseAdapter, OdbcConnectionPool, with_connection, get_dsn, close_pool!,
       SqlToCellTable,
       DatabaseInstanceToDbCatalog

end # module Odbc
