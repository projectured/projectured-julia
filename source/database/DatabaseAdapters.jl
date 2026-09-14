# Fragment of `DatabaseModule` — the database adapter seam: the abstract
# `DatabaseAdapter` and the registry that turns a symbolic kind into a concrete
# adapter a higher package registered.

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
