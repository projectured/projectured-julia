# Fragment of `OdbcModule` — the ODBC database adapter: the statements it
# builds, and the connection it runs them against.

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

function connect_db!(adapter::OdbcDatabaseAdapter)
    adapter._conn = ODBC.Connection(adapter.dsn)
    return adapter
end

function close_db!(adapter::OdbcDatabaseAdapter)
    if adapter._conn !== nothing
        DBInterface.close!(adapter._conn)
        adapter._conn = nothing
    end
    return adapter
end

function is_db_alive(adapter::OdbcDatabaseAdapter)::Bool
    adapter._conn === nothing && return false
    try
        DBInterface.execute(adapter._conn, "SELECT 1")
        return true
    catch
        return false
    end
end

get_db_rowid_column(adapter::OdbcDatabaseAdapter) = adapter.rowid_column

# ── OdbcDatabaseAdapter — RawDatabaseResult target ───────────────────────────

function query_db(adapter::OdbcDatabaseAdapter, table::String,
                  ::Type{RawDatabaseResult};
                  columns=nothing, where=nothing, limit=nothing)::RawDatabaseResult
    sql, _ = _build_select(table, columns, where, limit)
    cursor = DBInterface.execute(adapter._conn, sql)
    col_names, rows = _materialize(cursor)
    RawDatabaseResult(col_names, rows)
end

function execute_db_raw(adapter::OdbcDatabaseAdapter, sql::String,
                        ::Type{RawDatabaseResult};
                        params=())::RawDatabaseResult
    cursor = DBInterface.execute(adapter._conn, sql, collect(params))
    col_names, rows = _materialize(cursor)
    RawDatabaseResult(col_names, rows)
end

# ── OdbcDatabaseAdapter — mutations ───────────────────────────────────────────

function insert_into_db!(adapter::OdbcDatabaseAdapter,
                    table::String, row::AbstractDict)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    placeholders = join(fill("?", length(cols)), ", ")
    col_list = join(["\"$(c)\"" for c in cols], ", ")
    sql = "INSERT INTO \"$(table)\" ($(col_list)) VALUES ($(placeholders))"
    cursor = DBInterface.execute(adapter._conn, sql, vals)
    cursor.rows
end

function update_db!(adapter::OdbcDatabaseAdapter,
                    table::String, row::AbstractDict, where::String)::Int
    cols = collect(keys(row))
    vals = collect(values(row))
    set_clause = join(["\"$(c)\" = ?" for c in cols], ", ")
    sql = "UPDATE \"$(table)\" SET $(set_clause) WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql, vals)
    cursor.rows
end

function delete_from_db!(adapter::OdbcDatabaseAdapter,
                    table::String, where::String)::Int
    sql = "DELETE FROM \"$(table)\" WHERE $(where)"
    cursor = DBInterface.execute(adapter._conn, sql)
    cursor.rows
end

# ── OdbcDatabaseAdapter — catalog queries ────────────────────────────────────

# The text of the query that lists every database of the server, except the
# templates. `information_schema` shows a connection its own database only, so
# the list comes from `pg_database`.
_make_catalog_databases_query() =
    "SELECT datname FROM pg_database WHERE NOT datistemplate " *
    "ORDER BY datname"

# The text of the query that lists the schemas of `database`. A connection sees
# the schemas of its own database only, so the schemas of another database are
# an empty list.
_make_catalog_schemas_query(database::String) =
    "SELECT schema_name FROM information_schema.schemata " *
    "WHERE catalog_name = '$(database)' " *
    "AND schema_name NOT LIKE 'pg_%' AND schema_name <> 'information_schema' " *
    "ORDER BY schema_name"

function get_db_catalog_databases(adapter::OdbcDatabaseAdapter)::Vector{String}
    if adapter._conn === nothing || !is_db_alive(adapter)
        connect_db!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn, _make_catalog_databases_query())
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function get_db_catalog_schemas(adapter::OdbcDatabaseAdapter, database::String)::Vector{String}
    if adapter._conn === nothing || !is_db_alive(adapter)
        connect_db!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn, _make_catalog_schemas_query(database))
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function get_db_catalog_tables(adapter::OdbcDatabaseAdapter, schema::String)::Vector{String}
    if adapter._conn === nothing || !is_db_alive(adapter)
        connect_db!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT table_name FROM information_schema.tables " *
        "WHERE table_schema = '$(schema)' AND table_type = 'BASE TABLE' " *
        "ORDER BY table_name")
    _, rows = _materialize(cursor)
    String[String(row[1]) for row in rows]
end

function get_db_catalog_columns(adapter::OdbcDatabaseAdapter,
                             schema::String, table::String)
    if adapter._conn === nothing || !is_db_alive(adapter)
        connect_db!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT column_name, data_type FROM information_schema.columns " *
        "WHERE table_schema = '$(schema)' AND table_name = '$(table)' ORDER BY ordinal_position")
    _, rows = _materialize(cursor)
    [(name=String(row[1]), data_type=String(row[2])) for row in rows]
end

# PostgreSQL-specific FK query against pg_catalog rather than the ANSI
# information_schema. The information_schema constraint views
# (table_constraints / key_column_usage / constraint_column_usage) are
# privilege-filtered: they expose a table's constraints only to the table's
# owner (or a role with non-SELECT privileges). Our examples connect as a
# SELECT-only role (e.g. `projectured`) against tables owned by `postgres`, so
# the information_schema query returns zero FKs even when they exist. pg_catalog
# is visible to any role that can see the catalog, so it reports the real FKs
# regardless of ownership. `unnest(... WITH ORDINALITY)` pairs each
# `conkey[i]` (referencing column) with the matching `confkey[i]` (referenced
# column), yielding one row per FK column — multi-column FKs span multiple rows.
function get_db_catalog_foreign_keys(adapter::OdbcDatabaseAdapter, schema::String)
    if adapter._conn === nothing || !is_db_alive(adapter)
        connect_db!(adapter)
    end
    cursor = DBInterface.execute(adapter._conn,
        "SELECT rel.relname  AS from_table, " *
        "       att.attname  AS from_column, " *
        "       frel.relname AS to_table, " *
        "       fatt.attname AS to_column " *
        "FROM pg_constraint con " *
        "JOIN pg_class rel  ON rel.oid  = con.conrelid " *
        "JOIN pg_class frel ON frel.oid = con.confrelid " *
        "JOIN pg_namespace ns ON ns.oid = con.connamespace " *
        "JOIN unnest(con.conkey)  WITH ORDINALITY AS ck(attnum, ord)  ON true " *
        "JOIN unnest(con.confkey) WITH ORDINALITY AS fk(attnum, ord2) ON ck.ord = fk.ord2 " *
        "JOIN pg_attribute att  ON att.attrelid  = con.conrelid  AND att.attnum  = ck.attnum " *
        "JOIN pg_attribute fatt ON fatt.attrelid = con.confrelid AND fatt.attnum = fk.attnum " *
        "WHERE con.contype = 'f' AND ns.nspname = '$(schema)' " *
        "ORDER BY from_table, from_column")
    _, rows = _materialize(cursor)
    [(from_table=String(row[1]), from_column=String(row[2]),
      to_table=String(row[3]), to_column=String(row[4])) for row in rows]
end
