"""
    DatabaseModule

Generic database access layer. Defines the abstract `DatabaseAdapter`
interface and `RawDatabaseResult`. This module is **dependency-free** — it
touches neither `ODBC`, `DBInterface`, nor `Tables`. The first concrete
implementation, `OdbcDatabaseAdapter`, lives in `OdbcAdapterModule`
(`external/OdbcAdapter.jl`) and is constructed through the
`make_database_adapter` factory, so live-database access can be confined to an
optional package extension.

## Query API

`query_db(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into
the caller-specified target type with no intermediate allocation. Each target
type is a separate dispatch method; concrete adapters (e.g. the ODBC adapter)
implement the methods (e.g. the `RawDatabaseResult` target).
"""
module DatabaseModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
import ..OperationModule: Operation

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

# ── Abstract adapter ──────────────────────────────────────────────────────────

"""
    DatabaseAdapter

Abstract supertype for all database connection adapters. Concrete subtypes
implement `connect_db!`, `close_db!`, `is_db_alive`, `get_db_rowid_column`, and the
target-type dispatch methods for `query_db` / `execute_db_raw`.
"""
abstract type DatabaseAdapter end

"""
    make_database_adapter(kind::Symbol; kwargs...) -> DatabaseAdapter

Construct a database adapter by symbolic `kind` (e.g. `:odbc`). Concrete adapter
modules add a method `make_database_adapter(::Val{kind}; kwargs...)`. This lets
callers build a live adapter without naming its concrete type — important once
the concrete adapter lives in an optional package extension. A missing method
(its dependency not loaded) raises a helpful error.
"""
make_database_adapter(kind::Symbol; kwargs...) = make_database_adapter(Val(kind); kwargs...)
make_database_adapter(::Val{K}; kwargs...) where {K} = error(
    "No database adapter registered for :$(K). Is the package/extension that " *
    "provides it loaded?")

function connect_db!(adapter::DatabaseAdapter)
    error("connect_db! not implemented for $(typeof(adapter))")
end

function close_db!(adapter::DatabaseAdapter)
    error("close_db! not implemented for $(typeof(adapter))")
end

function is_db_alive(adapter::DatabaseAdapter)::Bool
    error("is_db_alive not implemented for $(typeof(adapter))")
end

"""
    get_db_rowid_column(adapter)::String

The technical row-identity column for this adapter's database. Set via a
constructor parameter on the concrete adapter (e.g. `"ctid"` for PostgreSQL,
`"rowid"` for SQLite).
"""
function get_db_rowid_column(adapter::DatabaseAdapter)::String
    error("get_db_rowid_column not implemented for $(typeof(adapter))")
end

function query_db(adapter::DatabaseAdapter, table::String, ::Type{T};
                  columns=nothing, where=nothing, limit=nothing) where {T}
    error("query_db(::$(typeof(adapter)), ::String, ::Type{$(T)}) not implemented")
end

function execute_db_raw(adapter::DatabaseAdapter, sql::String, ::Type{T};
                        params=()) where {T}
    error("execute_db_raw(::$(typeof(adapter)), ::String, ::Type{$(T)}) not implemented")
end

function insert_into_db!(adapter::DatabaseAdapter, table::String, row::AbstractDict)::Int
    error("insert_into_db! not implemented for $(typeof(adapter))")
end

function update_db!(adapter::DatabaseAdapter, table::String,
                    row::AbstractDict, where::String)::Int
    error("update_db! not implemented for $(typeof(adapter))")
end

function delete_from_db!(adapter::DatabaseAdapter, table::String, where::String)::Int
    error("delete_from_db! not implemented for $(typeof(adapter))")
end

function get_db_catalog_databases(adapter::DatabaseAdapter)::Vector{String}
    error("get_db_catalog_databases not implemented for $(typeof(adapter))")
end

function get_db_catalog_schemas(adapter::DatabaseAdapter, database::String)::Vector{String}
    error("get_db_catalog_schemas not implemented for $(typeof(adapter))")
end

function get_db_catalog_tables(adapter::DatabaseAdapter, schema::String)::Vector{String}
    error("get_db_catalog_tables not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_columns(adapter, schema, table)

Return a vector of `(name, data_type)` named tuples for each column of
`schema.table`, ordered by `ordinal_position`.
"""
function get_db_catalog_columns(adapter::DatabaseAdapter, schema::String, table::String)
    error("get_db_catalog_columns not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_foreign_keys(adapter, schema)

Return a vector of `(from_table, from_column, to_table, to_column)` named tuples,
one per foreign-key column in `schema`, where `from_table.from_column` references
`to_table.to_column`. Multi-column foreign keys yield one tuple per column.
Used to draw entity-relationship edges from the live database constraints.
"""
function get_db_catalog_foreign_keys(adapter::DatabaseAdapter, schema::String)
    error("get_db_catalog_foreign_keys not implemented for $(typeof(adapter))")
end

# ── RawDatabaseResult ─────────────────────────────────────────────────────────

"""
    RawDatabaseResult

Explicit raw materialization of a query result. Allocate only when you need
to inspect, cache, or serialise the data outside the projection pipeline.
Use `query_db(adapter, table, RawDatabaseResult)` to produce one.
"""
struct RawDatabaseResult
    columns::Vector{String}
    rows::Vector{Vector{Any}}
end

function Base.show(io::IO, r::RawDatabaseResult)
    println(io, join(r.columns, "\t"))
    for row in r.rows
        println(io, join(string.(row), "\t"))
    end
end

include("DatabaseInstance.jl")
include("DatabaseDocument.jl")

end # module
