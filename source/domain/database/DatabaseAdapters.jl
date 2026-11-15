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

"""
    connect_db!(adapter::DatabaseAdapter) -> DatabaseAdapter

Opens the connection of `adapter` to its database and returns the adapter. A concrete adapter adds the method; the method of the abstract adapter raises an error.

Use it to open the connection before a query or a catalog read.

# Example

    adapter_1 = database_1.adapter
    connect_db!(adapter_1)

See also `is_db_alive` and `close_db!`.

For the assistant.
"""
function connect_db! end

function connect_db!(adapter::DatabaseAdapter)
    error("connect_db! not implemented for $(typeof(adapter))")
end

"""
    close_db!(adapter::DatabaseAdapter) -> DatabaseAdapter

Closes the connection of `adapter` to its database and returns the adapter. Closing an adapter that is not connected does nothing.

Use it to release the connection when the work on a database is done.

# Example

    adapter_1 = database_1.adapter
    close_db!(adapter_1)

See also `connect_db!` and `is_db_alive`.

For the assistant.
"""
function close_db! end

function close_db!(adapter::DatabaseAdapter)
    error("close_db! not implemented for $(typeof(adapter))")
end

"""
    is_db_alive(adapter::DatabaseAdapter) -> Bool

Whether `adapter` holds a connection that answers a query.

Use it to check the connection before a query, and connect again when it is gone.

# Example

    adapter_1 = database_1.adapter
    alive_1 = is_db_alive(adapter_1)

See also `connect_db!` and `close_db!`.

For the assistant.
"""
function is_db_alive end

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

"""
    query_db(adapter::DatabaseAdapter, table::String, ::Type{T}; columns = nothing, where = nothing, limit = nothing) -> T

Reads the rows of `table` into a value of type `T`. `columns` names the columns to read, `where` is a condition on the rows, and `limit` is the most rows to read. `RawDatabaseResult` holds the column names and the rows as they are. The connection of the adapter is open.

Use it to read some rows of a table of the database.

# Example

    adapter_1 = database_1.adapter
    result_1 = query_db(adapter_1, "orders", RawDatabaseResult; limit = 10)

See also `get_db_catalog_tables`, `get_db_catalog_columns` and `connect_db!`.

For the assistant.
"""
function query_db end

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

"""
    get_db_catalog_databases(adapter::DatabaseAdapter) -> Vector{String}

The names of the databases that the connection of `adapter` can see. It connects first when the adapter is not connected.

Use it to find out which databases there are before a schema is chosen.

# Example

    adapter_1 = database_1.adapter
    databases_1 = get_db_catalog_databases(adapter_1)

See also `get_db_catalog_schemas` and `get_db_catalog_tables`.

For the assistant.
"""
function get_db_catalog_databases end

function get_db_catalog_databases(adapter::DatabaseAdapter)::Vector{String}
    error("get_db_catalog_databases not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_schemas(adapter::DatabaseAdapter, database::String) -> Vector{String}

The names of the schemas of `database`. It connects first when the adapter is not connected.

Use it to find out which schemas a database holds before a table is chosen.

# Example

    adapter_1 = database_1.adapter
    schemas_1 = get_db_catalog_schemas(adapter_1, "shop")

See also `get_db_catalog_databases` and `get_db_catalog_tables`.

For the assistant.
"""
function get_db_catalog_schemas end

function get_db_catalog_schemas(adapter::DatabaseAdapter, database::String)::Vector{String}
    error("get_db_catalog_schemas not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_tables(adapter::DatabaseAdapter, schema::String) -> Vector{String}

The names of the tables of `schema`. It connects first when the adapter is not connected.

Use it to find out which tables a schema holds before one is queried.

# Example

    adapter_1 = database_1.adapter
    tables_1 = get_db_catalog_tables(adapter_1, "public")

See also `get_db_catalog_schemas`, `get_db_catalog_columns` and `query_db`.

For the assistant.
"""
function get_db_catalog_tables end

function get_db_catalog_tables(adapter::DatabaseAdapter, schema::String)::Vector{String}
    error("get_db_catalog_tables not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_columns(adapter, schema, table)

Return a vector of `(name, data_type)` named tuples for each column of
`schema.table`, ordered by `ordinal_position`.

Use it to find the columns of a table and their types before a query.

# Example

    adapter_1 = database_1.adapter
    columns_1 = get_db_catalog_columns(adapter_1, "public", "orders")

See also `get_db_catalog_tables` and `query_db`.

For the assistant.
"""
function get_db_catalog_columns end

function get_db_catalog_columns(adapter::DatabaseAdapter, schema::String, table::String)
    error("get_db_catalog_columns not implemented for $(typeof(adapter))")
end

"""
    get_db_catalog_foreign_keys(adapter, schema)

Return a vector of `(from_table, from_column, to_table, to_column)` named tuples,
one per foreign-key column in `schema`, where `from_table.from_column` references
`to_table.to_column`. Multi-column foreign keys yield one tuple per column.
Used to draw entity-relationship edges from the live database constraints.

Use it to find how the tables of a schema refer to one another.

# Example

    adapter_1 = database_1.adapter
    keys_1 = get_db_catalog_foreign_keys(adapter_1, "public")

See also `get_db_catalog_tables` and `get_db_catalog_columns`.

For the assistant.
"""
function get_db_catalog_foreign_keys end

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
