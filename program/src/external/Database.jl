"""
    DatabaseModule

Generic database access layer. Defines the abstract `DatabaseAdapter`
interface and `RawDatabaseResult`, with `PostgresDatabaseAdapter` as the
first concrete implementation using `LibPQ.jl`.

## Query API

`db_query(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into
the caller-specified target type with no intermediate allocation. Each target
type is a separate dispatch method; the `RawDatabaseResult` target is
implemented here. The `TabularGrid` target lives in the bridge module
(`DatabaseTabular.jl`) to avoid a backend → document dependency.

## Dependencies (program/Project.toml)

    LibPQ = "194296ae-ab2e-5f79-8cd4-7183a0a5a0d1"
"""
module DatabaseModule

import LibPQ

export DatabaseAdapter,
       RawDatabaseResult,
       PostgresDatabaseAdapter,
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
    db_rowid_column(adapter) -> String

Return the name of the technical row-identity column for this adapter.
Used by the projection bridge to identify rows without knowing business keys.

- `PostgresDatabaseAdapter` → `"ctid"`
- Future `SQLiteDatabaseAdapter` → `"rowid"`
"""
function db_rowid_column(adapter::DatabaseAdapter)::String
    error("db_rowid_column not implemented for $(typeof(adapter))")
end

"""
    db_query(adapter, table, ::Type{T}; columns, where, limit) -> T

Execute a single-table SELECT and pipeline the result directly into `T`.
`columns` is a `Vector{String}` or `nothing` (all). `where` is a raw SQL
WHERE fragment string or `nothing`. `limit` is an `Int` or `nothing`.
"""
function db_query(adapter::DatabaseAdapter, table::String, ::Type{T};
                  columns=nothing, where=nothing, limit=nothing) where T
    error("db_query not implemented for $(typeof(adapter)) → $(T)")
end

"""
    db_execute_raw(adapter, sql, ::Type{T}; params=()) -> T

Execute arbitrary SQL and pipeline the result into `T`. `params` is a
tuple or vector of positional bind parameters.
"""
function db_execute_raw(adapter::DatabaseAdapter, sql::String, ::Type{T};
                        params=()) where T
    error("db_execute_raw not implemented for $(typeof(adapter)) → $(T)")
end

"""
    db_insert!(adapter, table, row) -> Int

Insert `row` (an `AbstractDict` mapping column name → value) into `table`.
Returns the number of affected rows.
"""
function db_insert!(adapter::DatabaseAdapter, table::String, row::AbstractDict)::Int
    error("db_insert! not implemented for $(typeof(adapter))")
end

"""
    db_update!(adapter, table, row, where) -> Int

Update the column(s) in `row` for all rows matching `where` in `table`.
Returns the number of affected rows.
"""
function db_update!(adapter::DatabaseAdapter, table::String,
                    row::AbstractDict, where::String)::Int
    error("db_update! not implemented for $(typeof(adapter))")
end

"""
    db_delete!(adapter, table, where) -> Int

Delete all rows matching `where` from `table`. Returns the number of deleted rows.
"""
function db_delete!(adapter::DatabaseAdapter, table::String, where::String)::Int
    error("db_delete! not implemented for $(typeof(adapter))")
end

"""
    db_catalog_databases(adapter) -> Vector{String}

Return the names of all non-template databases visible to the adapter.
"""
function db_catalog_databases(adapter::DatabaseAdapter)::Vector{String}
    error("db_catalog_databases not implemented for $(typeof(adapter))")
end

"""
    db_catalog_schemas(adapter, database) -> Vector{String}

Return the names of all user schemas in the current connection's database.
The `database` argument is accepted for interface symmetry but PostgreSQL
requires a separate connection per database — the adapter queries the
currently connected database.
"""
function db_catalog_schemas(adapter::DatabaseAdapter, database::String)::Vector{String}
    error("db_catalog_schemas not implemented for $(typeof(adapter))")
end

"""
    db_catalog_tables(adapter, schema) -> Vector{String}

Return the names of all tables in `schema` for the current connection.
"""
function db_catalog_tables(adapter::DatabaseAdapter, schema::String)::Vector{String}
    error("db_catalog_tables not implemented for $(typeof(adapter))")
end

"""
    db_catalog_columns(adapter, schema, table) -> Vector{NamedTuple}

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

# ── Private helpers ───────────────────────────────────────────────────────────

function _build_select(table::String, columns, where_clause, limit)
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT \"$(table)\".* FROM \"$(table)\""
    if columns !== nothing
        sql = "SELECT $(col_part) FROM \"$(table)\""
    end
    params = Any[]
    if where_clause !== nothing
        sql *= " WHERE $(where_clause)"
    end
    if limit !== nothing
        sql *= " LIMIT $(limit)"
    end
    sql, params
end

function _col_names(result)
    String[String(n) for n in LibPQ.column_names(result)]
end

function _materialize_rows(result, col_names)
    n = length(col_names)
    rows = Vector{Vector{Any}}()
    for row in result
        push!(rows, Any[row[i] for i in 1:n])
    end
    rows
end

# ── PostgresDatabaseAdapter ───────────────────────────────────────────────────

"""
    PostgresDatabaseAdapter

PostgreSQL adapter using LibPQ.jl. Implements `DatabaseAdapter` with
`ctid` as the technical row identifier.

# Constructors

    PostgresDatabaseAdapter(; host, port, dbname, user, password)
"""
mutable struct PostgresDatabaseAdapter <: DatabaseAdapter
    host::String
    port::Int
    dbname::String
    user::String
    password::String
    _conn::Union{Nothing, LibPQ.Connection}
end

PostgresDatabaseAdapter(; host::AbstractString="localhost",
                          port::Integer=5432,
                          dbname::AbstractString,
                          user::AbstractString,
                          password::AbstractString) =
    PostgresDatabaseAdapter(String(host), Int(port), String(dbname),
                            String(user), String(password), nothing)

function db_connect!(adapter::PostgresDatabaseAdapter)
    dsn = "host=$(adapter.host) port=$(adapter.port) " *
          "dbname=$(adapter.dbname) user=$(adapter.user) " *
          "password=$(adapter.password)"
    adapter._conn = LibPQ.Connection(dsn)
    return adapter
end

function db_close!(adapter::PostgresDatabaseAdapter)
    if adapter._conn !== nothing
        close(adapter._conn)
        adapter._conn = nothing
    end
    return adapter
end

function db_alive(adapter::PostgresDatabaseAdapter)::Bool
    adapter._conn === nothing && return false
    try
        LibPQ.execute(adapter._conn, "SELECT 1")
        return true
    catch
        return false
    end
end

db_rowid_column(::PostgresDatabaseAdapter) = "ctid"

# ── PostgresDatabaseAdapter — RawDatabaseResult target ───────────────────────

function db_query(adapter::PostgresDatabaseAdapter, table::String,
                  ::Type{RawDatabaseResult};
                  columns=nothing, where=nothing, limit=nothing)::RawDatabaseResult
    sql, _ = _build_select(table, columns, where, limit)
    result = LibPQ.execute(adapter._conn, sql)
    col_names = _col_names(result)
    RawDatabaseResult(col_names, _materialize_rows(result, col_names))
end

function db_execute_raw(adapter::PostgresDatabaseAdapter, sql::String,
                        ::Type{RawDatabaseResult};
                        params=())::RawDatabaseResult
    result = LibPQ.execute(adapter._conn, sql, collect(params))
    col_names = _col_names(result)
    RawDatabaseResult(col_names, _materialize_rows(result, col_names))
end

# ── PostgresDatabaseAdapter — mutations ───────────────────────────────────────

function db_insert!(adapter::PostgresDatabaseAdapter,
                    table::String, row::AbstractDict)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    placeholders = join(["\$$(i)" for i in 1:length(cols)], ", ")
    col_list = join(["\"$(c)\"" for c in cols], ", ")
    sql = "INSERT INTO \"$(table)\" ($(col_list)) VALUES ($(placeholders))"
    result = LibPQ.execute(adapter._conn, sql, vals)
    LibPQ.num_affected_rows(result)
end

function db_update!(adapter::PostgresDatabaseAdapter,
                    table::String, row::AbstractDict, where::String)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    set_clause = join(["\"$(c)\" = \$$(i)" for (i, c) in enumerate(cols)], ", ")
    sql = "UPDATE \"$(table)\" SET $(set_clause) WHERE $(where)"
    result = LibPQ.execute(adapter._conn, sql, vals)
    LibPQ.num_affected_rows(result)
end

function db_delete!(adapter::PostgresDatabaseAdapter,
                    table::String, where::String)::Int
    sql = "DELETE FROM \"$(table)\" WHERE $(where)"
    result = LibPQ.execute(adapter._conn, sql)
    LibPQ.num_affected_rows(result)
end

# ── PostgresDatabaseAdapter — catalog queries ────────────────────────────────

function db_catalog_databases(adapter::PostgresDatabaseAdapter)::Vector{String}
    result = LibPQ.execute(adapter._conn,
        "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
    String[row[1] for row in result]
end

function db_catalog_schemas(adapter::PostgresDatabaseAdapter, database::String)::Vector{String}
    result = LibPQ.execute(adapter._conn,
        "SELECT nspname FROM pg_namespace " *
        "WHERE nspname NOT LIKE 'pg_%' AND nspname <> 'information_schema' " *
        "ORDER BY nspname")
    String[row[1] for row in result]
end

function db_catalog_tables(adapter::PostgresDatabaseAdapter, schema::String)::Vector{String}
    result = LibPQ.execute(adapter._conn,
        "SELECT tablename FROM pg_tables WHERE schemaname = \$1 ORDER BY tablename",
        [schema])
    String[row[1] for row in result]
end

function db_catalog_columns(adapter::PostgresDatabaseAdapter,
                             schema::String, table::String)
    result = LibPQ.execute(adapter._conn,
        "SELECT column_name, data_type FROM information_schema.columns " *
        "WHERE table_schema = \$1 AND table_name = \$2 ORDER BY ordinal_position",
        [schema, table])
    [(name=String(row[1]), data_type=String(row[2])) for row in result]
end

end # module
