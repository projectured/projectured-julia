"""
    OdbcAdapterModule

Concrete `OdbcDatabaseAdapter` implementing the abstract `DatabaseAdapter`
interface (`DatabaseModule`) over any ODBC-reachable database (PostgreSQL,
SQL Server, MySQL, Oracle, SQLite, …) by varying only the connection string.

This is the only module that touches `ODBC`, `DBInterface`, and `Tables`. It is
isolated from the interface module so that the live-database dependency can be
moved into an optional package extension: code that needs only the abstract
interface depends on `DatabaseModule`, while constructing a live adapter goes
through `make_database_adapter(:odbc; …)`.

## Dependencies (program/Project.toml — weakdeps after the extension split)

    ODBC = "be6f12e9-ca4f-5eb2-a339-a4f995cc0291"
    DBInterface = "a10d1c49-ce27-4219-8d33-6db1a4562965"
    Tables = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
"""
module OdbcAdapterModule

import ODBC
import DBInterface
import Tables

import ..DatabaseModule: DatabaseAdapter, RawDatabaseResult,
                         db_connect!, db_close!, db_alive, db_rowid_column,
                         db_query, db_execute_raw,
                         db_insert!, db_update!, db_delete!,
                         db_catalog_databases, db_catalog_schemas,
                         db_catalog_tables, db_catalog_columns,
                         make_database_adapter

export OdbcDatabaseAdapter

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

# Factory entry point on the abstract interface, so callers need not name the
# concrete type. `make_database_adapter(:odbc; dsn=…, rowid_column=…)`.
make_database_adapter(::Val{:odbc}; kwargs...) = OdbcDatabaseAdapter(; kwargs...)

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
    cursor.rows
end

function db_update!(adapter::OdbcDatabaseAdapter,
                    table::String, row::AbstractDict, where::String)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    set_clause = join(["\"$(c)\" = ?" for c in cols], ", ")
    sql = "UPDATE \"$(table)\" SET $(set_clause) WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql, vals)
    cursor.rows
end

function db_delete!(adapter::OdbcDatabaseAdapter,
                    table::String, where::String)::Int
    sql = "DELETE FROM \"$(table)\" WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql)
    cursor.rows
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
        "WHERE table_schema = '$(schema)' AND table_type = 'BASE TABLE' " *
        "ORDER BY table_name")
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
        "WHERE table_schema = '$(schema)' AND table_name = '$(table)' ORDER BY ordinal_position")
    _, rows = _materialize(cursor)
    [(name=String(row[1]), data_type=String(row[2])) for row in rows]
end

end # module
