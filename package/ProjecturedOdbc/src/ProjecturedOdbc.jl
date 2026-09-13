"""
    Odbc

Opt-in package: live ODBC database access (OdbcDatabaseAdapter, connection pool,
and the live-query projections). Depends on `ProjecturedDomain` + ODBC/DBInterface/
Tables; `using ProjecturedOdbc` registers `make_database_adapter(:odbc)` and exposes
the adapter, pool, and live-query projection types. (The SQL/DbCatalog documents and
their pure projections stay in `ProjecturedDomain` — only live querying lives here.)
"""
module ProjecturedOdbc

using ProjecturedCollection
using ProjecturedDatabase
using ProjecturedDbCatalog
using ProjecturedCollection
using ProjecturedDatabase
using ProjecturedDbCatalog
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedSql
using ProjecturedSyntax
using ProjecturedText
using ProjecturedProjection
using ProjecturedSql
using ProjecturedSyntax
using ProjecturedText
using ProjecturedDatabase
using ProjecturedDbCatalog
using ProjecturedSql

include("../../../source/odbc/OdbcAdapter.jl")
include("../../../source/odbc/ConnectionPool.jl")
include("../../../source/odbc/SqlToCellTable.jl")
include("../../../source/odbc/DatabaseInstanceToDbCatalog.jl")

# Re-export and export public symbols at the package top level so consumers can
# `using ProjecturedOdbc` and name these types directly.
using .OdbcAdapterModule: OdbcDatabaseAdapter
using .ConnectionPoolModule: OdbcConnectionPool, with_connection, get_dsn, close_pool!
using .SqlToCellTableModule: SqlToCellTable
using .DatabaseInstanceToDbCatalogModule: DatabaseInstanceToDbCatalog

export OdbcDatabaseAdapter, OdbcConnectionPool, with_connection, get_dsn, close_pool!,
       SqlToCellTable,
       DatabaseInstanceToDbCatalog

end # module Odbc
