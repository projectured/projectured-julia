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

`db_query(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into
the caller-specified target type with no intermediate allocation. Each target
type is a separate dispatch method; concrete adapters (e.g. the ODBC adapter)
implement the methods. The `TabularGrid` target lives in the bridge module
(`DatabaseTabular.jl`) to avoid a backend → document dependency.
"""
module DatabaseModule

export DatabaseAdapter,
       RawDatabaseResult,
       make_database_adapter,
       db_connect!, db_close!, db_alive,
       db_rowid_column,
       db_query, db_execute_raw,
       db_insert!, db_update!, db_delete!,
       db_catalog_databases, db_catalog_schemas, db_catalog_tables, db_catalog_columns

# ── Abstract adapter ──────────────────────────────────────────────────────────

"""
    DatabaseAdapter

Abstract supertype for all database connection adapters. Concrete subtypes
implement `db_connect!`, `db_close!`, `db_alive`, `db_rowid_column`, and the
target-type dispatch methods for `db_query` / `db_execute_raw`.
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

function db_connect!(adapter::DatabaseAdapter)
    error("db_connect! not implemented for $(typeof(adapter))")
end

function db_close!(adapter::DatabaseAdapter)
    error("db_close! not implemented for $(typeof(adapter))")
end

function db_alive(adapter::DatabaseAdapter)::Bool
    error("db_alive not implemented for $(typeof(adapter))")
end

"""
    db_rowid_column(adapter)::String

The technical row-identity column for this adapter's database. Set via a
constructor parameter on the concrete adapter (e.g. `"ctid"` for PostgreSQL,
`"rowid"` for SQLite).
"""
function db_rowid_column(adapter::DatabaseAdapter)::String
    error("db_rowid_column not implemented for $(typeof(adapter))")
end

function db_query(adapter::DatabaseAdapter, table::String, ::Type{T};
                  columns=nothing, where=nothing, limit=nothing) where {T}
    error("db_query(::$(typeof(adapter)), ::String, ::Type{$(T)}) not implemented")
end

function db_execute_raw(adapter::DatabaseAdapter, sql::String, ::Type{T};
                        params=()) where {T}
    error("db_execute_raw(::$(typeof(adapter)), ::String, ::Type{$(T)}) not implemented")
end

function db_insert!(adapter::DatabaseAdapter, table::String, row::AbstractDict)::Int
    error("db_insert! not implemented for $(typeof(adapter))")
end

function db_update!(adapter::DatabaseAdapter, table::String,
                    row::AbstractDict, where::String)::Int
    error("db_update! not implemented for $(typeof(adapter))")
end

function db_delete!(adapter::DatabaseAdapter, table::String, where::String)::Int
    error("db_delete! not implemented for $(typeof(adapter))")
end

function db_catalog_databases(adapter::DatabaseAdapter)::Vector{String}
    error("db_catalog_databases not implemented for $(typeof(adapter))")
end

function db_catalog_schemas(adapter::DatabaseAdapter, database::String)::Vector{String}
    error("db_catalog_schemas not implemented for $(typeof(adapter))")
end

function db_catalog_tables(adapter::DatabaseAdapter, schema::String)::Vector{String}
    error("db_catalog_tables not implemented for $(typeof(adapter))")
end

"""
    db_catalog_columns(adapter, schema, table)

Return a vector of `(name, data_type)` named tuples for each column of
`schema.table`, ordered by `ordinal_position`.
"""
function db_catalog_columns(adapter::DatabaseAdapter, schema::String, table::String)
    error("db_catalog_columns not implemented for $(typeof(adapter))")
end

# ── RawDatabaseResult ─────────────────────────────────────────────────────────

"""
    RawDatabaseResult

Explicit raw materialization of a query result. Allocate only when you need
to inspect, cache, or serialise the data outside the projection pipeline.
Use `db_query(adapter, table, RawDatabaseResult)` to produce one.
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

end # module
