"""
    DatabaseModule

Generic database access layer. Defines the abstract `DatabaseAdapter`
interface and `RawDatabaseResult`, with `OdbcDatabaseAdapter` as the
first concrete implementation using `ODBC.jl`. ODBC is a universal standard:
a single adapter talks to PostgreSQL, SQL Server, MySQL, Oracle, SQLite, and
more by varying only the connection string.

## Query API

`db_query(adapter, table, ::Type{T}; ...)::T` pipelines rows directly into
the caller-specified target type with no intermediate allocation. Each target
type is a separate dispatch method; the `RawDatabaseResult` target is
implemented here. The `TabularGrid` target lives in the bridge module
(`DatabaseTabular.jl`) to avoid a backend → document dependency.

## Dependencies (program/Project.toml)

    ODBC = "be6f12e9-ca4f-5eb2-a339-a4f995cc0291"
    DBInterface = "a10d1c49-ce27-4219-8d33-6db1a4562965"
"""
module DatabaseModule

import ODBC
import DBInterface
import Tables

export DatabaseAdapter,
       RawDatabaseResult,
       OdbcDatabaseAdapter,
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

There is no universal row-identity column across databases, so this is a
constructor parameter on `OdbcDatabaseAdapter` (e.g. `"ctid"` for PostgreSQL,
`"rowid"` for SQLite).
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

# An `ODBC.Cursor` is a Tables.jl *source*, not a row iterator: it implements
# neither `iterate` nor `length`. We materialize it through `Tables.columntable`
# — a NamedTuple of column vectors — which exposes the column names via
# `propertynames` and preserves the schema even when the result is empty.
function _materialize(cursor)
    ct = Tables.columntable(cursor)
    col_names = String[String(n) for n in propertynames(ct)]
    ncols = length(col_names)
    nrows = ncols == 0 ? 0 : length(ct[1])
    rows = Vector{Vector{Any}}(undef, nrows)
    for i in 1:nrows
        rows[i] = Any[ct[j][i] for j in 1:ncols]
    end
    col_names, rows
end

# ── OdbcDatabaseAdapter ───────────────────────────────────────────────────────

"""
    OdbcDatabaseAdapter

Universal database adapter using ODBC.jl. Implements `DatabaseAdapter` over any
ODBC-reachable database (PostgreSQL, SQL Server, MySQL, Oracle, SQLite, …) by
varying only the connection string.

# Constructors

    OdbcDatabaseAdapter(; dsn, rowid_column="rowid")

`dsn` is a full ODBC connection string. `rowid_column` is the technical
row-identity column for the target database — PostgreSQL users pass `"ctid"`,
SQLite users `"rowid"`.

```julia
OdbcDatabaseAdapter(
    dsn="Driver={PostgreSQL Unicode};Server=localhost;Port=5432;" *
        "Database=mydb;Uid=user;Pwd=pass;",
    rowid_column="ctid")
```
"""
mutable struct OdbcDatabaseAdapter <: DatabaseAdapter
    dsn::String                         # ODBC connection string
    rowid_column::String                # configurable; no universal ctid equivalent
    _conn::Union{Nothing, ODBC.Connection}
end

OdbcDatabaseAdapter(; dsn::AbstractString,
                      rowid_column::AbstractString="rowid") =
    OdbcDatabaseAdapter(String(dsn), String(rowid_column), nothing)

function db_connect!(adapter::OdbcDatabaseAdapter)
    adapter._conn = ODBC.Connection(adapter.dsn)
    return adapter
end

function db_close!(adapter::OdbcDatabaseAdapter)
    if adapter._conn !== nothing
        DBInterface.close!(adapter._conn)
        adapter._conn = nothing
    end
    return adapter
end

function db_alive(adapter::OdbcDatabaseAdapter)::Bool
    adapter._conn === nothing && return false
    try
        DBInterface.execute(adapter._conn, "SELECT 1")
        return true
    catch
        return false
    end
end

db_rowid_column(adapter::OdbcDatabaseAdapter) = adapter.rowid_column

# ── OdbcDatabaseAdapter — RawDatabaseResult target ───────────────────────────

function db_query(adapter::OdbcDatabaseAdapter, table::String,
                  ::Type{RawDatabaseResult};
                  columns=nothing, where=nothing, limit=nothing)::RawDatabaseResult
    sql, _ = _build_select(table, columns, where, limit)
    cursor = DBInterface.execute(adapter._conn, sql)
    col_names, rows = _materialize(cursor)
    RawDatabaseResult(col_names, rows)
end

function db_execute_raw(adapter::OdbcDatabaseAdapter, sql::String,
                        ::Type{RawDatabaseResult};
                        params=())::RawDatabaseResult
    cursor = DBInterface.execute(adapter._conn, sql, collect(params))
    col_names, rows = _materialize(cursor)
    RawDatabaseResult(col_names, rows)
end

# ── OdbcDatabaseAdapter — mutations ───────────────────────────────────────────

function db_insert!(adapter::OdbcDatabaseAdapter,
                    table::String, row::AbstractDict)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    placeholders = join(fill("?", length(cols)), ", ")
    col_list = join(["\"$(c)\"" for c in cols], ", ")
    sql = "INSERT INTO \"$(table)\" ($(col_list)) VALUES ($(placeholders))"
    cursor = DBInterface.execute(adapter._conn, sql, vals)
    DBInterface.rowcount(cursor)
end

function db_update!(adapter::OdbcDatabaseAdapter,
                    table::String, row::AbstractDict, where::String)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    set_clause = join(["\"$(c)\" = ?" for c in cols], ", ")
    sql = "UPDATE \"$(table)\" SET $(set_clause) WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql, vals)
    DBInterface.rowcount(cursor)
end

function db_delete!(adapter::OdbcDatabaseAdapter,
                    table::String, where::String)::Int
    sql = "DELETE FROM \"$(table)\" WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql)
    DBInterface.rowcount(cursor)
end

# ── OdbcDatabaseAdapter — catalog queries ────────────────────────────────────

function db_catalog_databases(adapter::OdbcDatabaseAdapter)::Vector{String}
    if adapter._conn === nothing || !db_alive(adapter)
        db_connect!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT DISTINCT table_catalog FROM information_schema.tables " *
        "ORDER BY table_catalog")
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function db_catalog_schemas(adapter::OdbcDatabaseAdapter, database::String)::Vector{String}
    if adapter._conn === nothing || !db_alive(adapter)
        db_connect!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT schema_name FROM information_schema.schemata " *
        "WHERE schema_name NOT LIKE 'pg_%' AND schema_name <> 'information_schema' " *
        "ORDER BY schema_name")
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function db_catalog_tables(adapter::OdbcDatabaseAdapter, schema::String)::Vector{String}
    if adapter._conn === nothing || !db_alive(adapter)
        db_connect!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT table_name FROM information_schema.tables " *
        "WHERE table_schema = ? AND table_type = 'BASE TABLE' " *
        "ORDER BY table_name",
        [schema])
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function db_catalog_columns(adapter::OdbcDatabaseAdapter,
                             schema::String, table::String)
    if adapter._conn === nothing || !db_alive(adapter)
        db_connect!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT column_name, data_type FROM information_schema.columns " *
        "WHERE table_schema = ? AND table_name = ? ORDER BY ordinal_position",
        [schema, table])
    _, rows = _materialize(cursor)
    [(name=String(row[1]), data_type=String(row[2])) for row in rows]
end

end # module
