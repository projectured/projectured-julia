"""
    DatabaseModule

Generic database access layer. Defines the abstract `DatabaseAdapter`
interface and `RawDatabaseResult`. This module is **dependency-free** — it
touches neither `ODBC`, `DBInterface`, nor `Tables`. The first concrete
implementation, `OdbcDatabaseAdapter`, lives in `OdbcModule`
(`source/adapter/odbc/OdbcAdapter.jl`) and is constructed through the
`make_database_adapter` factory, so live-database access can be confined to the
separate, opt-in `ProjecturedOdbc` package.

## Query API

`query_db(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into
the caller-specified target type with no intermediate allocation. Each target
type is a separate dispatch method; concrete adapters (e.g. the ODBC adapter)
implement the methods (e.g. the `RawDatabaseResult` target).
"""
module DatabaseModule

using ..CellModule
using ..DocumentModule
using ..OperationModule
using ..ReferenceModule

export DatabaseDocument, UpdateDatabaseCellOperation, InsertDatabaseRowOperation
export DatabaseInstanceDocument
export DatabaseAdapter,
       RawDatabaseResult,
       make_database_adapter,
       connect_db!, close_db!, is_db_alive,
       get_db_rowid_column,
       query_db, execute_db_raw,
       insert_into_db!, update_db!, delete_from_db!,
       get_db_catalog_databases, get_db_catalog_schemas, get_db_catalog_tables, get_db_catalog_columns,
       get_db_catalog_foreign_keys


include("DatabaseAdapters.jl")
include("DatabaseInstance.jl")
include("DatabaseDocument.jl")

end # module
