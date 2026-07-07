"""
    Odbc

Opt-in package: live ODBC database access (OdbcDatabaseAdapter, connection pool,
and the live-query projections). Depends on `ProjecturedDomain` + ODBC/DBInterface/
Tables; `using ProjecturedOdbc` registers `make_database_adapter(:odbc)` and exposes
the adapter, pool, and live-query projection types. (The SQL/DbCatalog documents and
their pure projections stay in `ProjecturedDomain` — only live querying lives here.)
"""
module ProjecturedOdbc

using ProjecturedDomain

module OdbcAdapterModule

import ODBC
import DBInterface
import Tables

import ProjecturedDomain.DatabaseModule: DatabaseAdapter, RawDatabaseResult,
                         db_connect!, db_close!, db_alive, db_rowid_column,
                         db_query, db_execute_raw,
                         db_insert!, db_update!, db_delete!,
                         db_catalog_databases, db_catalog_schemas,
                         db_catalog_tables, db_catalog_columns,
                         db_catalog_foreign_keys,
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
function db_catalog_foreign_keys(adapter::OdbcDatabaseAdapter, schema::String)
    if adapter._conn === nothing || !db_alive(adapter)
        db_connect!(adapter)
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

end # module OdbcAdapterModule

module ConnectionPoolModule

import ProjecturedDomain.DatabaseModule: db_connect!, db_close!, db_alive
import ..OdbcAdapterModule: OdbcDatabaseAdapter
import ProjecturedDomain.DatabaseInstanceDocumentModule: DatabaseInstance

export OdbcConnectionPool, with_connection, dsn_for, close_pool!

# ── OdbcConnectionPool ──────────────────────────────────────────────────────────

mutable struct OdbcConnectionPool
    driver::String          # ODBC driver, e.g. "{PostgreSQL Unicode}"
    rowid_column::String    # technical row-identity column, e.g. "ctid"
    max_size::Int           # max idle adapters retained per DSN
    lock::ReentrantLock
    idle::Dict{String, Vector{OdbcDatabaseAdapter}}   # DSN → idle adapters
end

OdbcConnectionPool(; driver::AbstractString="{PostgreSQL Unicode}",
                     rowid_column::AbstractString="ctid",
                     max_size::Integer=8) =
    OdbcConnectionPool(String(driver), String(rowid_column), Int(max_size),
                       ReentrantLock(), Dict{String, Vector{OdbcDatabaseAdapter}}())

# ── DSN derivation ──────────────────────────────────────────────────────────────

"""
    dsn_for(pool, inst::DatabaseInstance) -> String

Build the ODBC connection string for `inst` using the pool's driver. Adapters
are bucketed by this DSN, so two `DatabaseInstance`s that resolve to the same
DSN share connections.
"""
function dsn_for(pool::OdbcConnectionPool, inst::DatabaseInstance)::String
    "Driver=$(pool.driver);Server=$(inst.host);Port=$(inst.port);" *
    "Database=$(inst.database);Uid=$(inst.credentials.user);Pwd=$(inst.credentials.password);"
end

# ── Checkout / checkin ──────────────────────────────────────────────────────────

function _checkout(pool::OdbcConnectionPool, dsn::String)::OdbcDatabaseAdapter
    lock(pool.lock) do
        bucket = get(pool.idle, dsn, nothing)
        if bucket !== nothing
            while !isempty(bucket)
                a = pop!(bucket)
                db_alive(a) && return a
                try; db_close!(a); catch; end   # stale: drop it and try the next
            end
        end
        a = OdbcDatabaseAdapter(dsn=dsn, rowid_column=pool.rowid_column)
        db_connect!(a)
        return a
    end
end

function _checkin(pool::OdbcConnectionPool, dsn::String, a::OdbcDatabaseAdapter)
    lock(pool.lock) do
        bucket = get!(pool.idle, dsn, OdbcDatabaseAdapter[])
        if length(bucket) < pool.max_size && db_alive(a)
            push!(bucket, a)
        else
            try; db_close!(a); catch; end
        end
    end
    nothing
end

"""
    with_connection(f, pool, inst::DatabaseInstance)

Check out a live pooled `OdbcDatabaseAdapter` for `inst`, run `f(adapter)`, and
return the adapter to the pool. On error the connection is discarded (closed)
rather than returned, so a broken connection is never reused.
"""
function with_connection(f, pool::OdbcConnectionPool, inst::DatabaseInstance)
    dsn = dsn_for(pool, inst)
    a = _checkout(pool, dsn)
    ok = false
    try
        result = f(a)
        ok = true
        return result
    finally
        if ok
            _checkin(pool, dsn, a)
        else
            try; db_close!(a); catch; end
        end
    end
end

"""
    close_pool!(pool)

Close and discard every idle adapter in the pool. Connections currently checked
out (inside a `with_connection` call) are unaffected.
"""
function close_pool!(pool::OdbcConnectionPool)
    lock(pool.lock) do
        for (_, bucket) in pool.idle
            for a in bucket
                try; db_close!(a); catch; end
            end
            empty!(bucket)
        end
    end
    pool
end

end # module ConnectionPoolModule



module SqlToCellTableModule

import ProjecturedDomain.CellModule: Cell
import ProjecturedDomain.CollectionModule: CellVector, CellTable
import ProjecturedDomain.ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedDomain.SqlDocumentModule: SqlSelectStatement
import ProjecturedDomain.SqlToSyntaxModule: SqlToSyntax
import ProjecturedDomain.SyntaxToTextModule: SyntaxToText
import ProjecturedDomain.TextToStringModule: TextToString
import ProjecturedDomain.RecursiveProjectionModule: RecursiveProjection
import ProjecturedDomain.ChainingProjectionModule: ChainingProjection
import ProjecturedDomain.DatabaseInstanceDocumentModule: DatabaseInstance
import ProjecturedDomain.DatabaseModule: RawDatabaseResult, db_execute_raw
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ProjecturedDomain.IoMapModule: SimpleIoMap

export SqlToCellTable

struct SqlToCellTable <: Projection
    pool::OdbcConnectionPool
    instance::DatabaseInstance
end

function print_document(p::SqlToCellTable, recursion, stmt::SqlSelectStatement, ctx)
    raw = Cell(() -> begin
        pipe = ChainingProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql = print_document(pipe, stmt).output[]
        with_connection(p.pool, p.instance) do adapter
            db_execute_raw(adapter, sql, RawDatabaseResult)
        end
    end)
    rows = CellVector(() -> begin
        r = raw[]
        header = CellVector(r.columns)               # row 1: column names
        data   = [CellVector(row) for row in r.rows]  # rows 2..n: data rows
        vcat([header], data)
    end)
    SimpleIoMap(p, stmt, CellTable(rows, Cell(nothing)))
end

map_reference_forward(::SqlToCellTable, iomap, ref) = nothing
map_reference_backward(::SqlToCellTable, iomap, ref) = nothing
read_intent(::SqlToCellTable, iomap, op) = nothing

end # module SqlToCellTableModule

module DatabaseInstanceToDbCatalogModule

import ProjecturedDomain.CollectionModule: CellVector
import ProjecturedDomain.DatabaseInstanceDocumentModule: DatabaseInstance
import ProjecturedDomain.DbCatalogDocumentModule: DbCatalogRdbms, DbCatalogDatabase,
                                  DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ProjecturedDomain.DatabaseModule: db_catalog_databases, db_catalog_schemas,
                         db_catalog_tables, db_catalog_columns
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ProjecturedDomain.IoMapModule: SimpleIoMap
import ProjecturedDomain.ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedDomain.CellModule: set_function!
import ProjecturedDomain.ReferenceModule: EmptyReferencePath
import ProjecturedDomain.ReferenceCaseModule: var"@reference_case"
import ProjecturedDomain.ReferenceBuilderModule: var"@reference"

export DatabaseInstanceToDbCatalog

# ── Lazy tree builders ──────────────────────────────────────────────────────────
# Each helper returns a CellVector whose contents are recomputed lazily by
# querying through the pool. The pool + instance are captured by closure.

function _build_columns(pool, inst, schema_name::String, table_name::String)
    CellVector(() -> begin
        cols = with_connection(pool, inst) do adapter
            db_catalog_columns(adapter, schema_name, table_name)
        end
        DbCatalogColumn[DbCatalogColumn(c.name, c.data_type) for c in cols]
    end)
end

function _build_tables(pool, inst, schema_name::String)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_tables(adapter, schema_name)
        end
        DbCatalogTable[DbCatalogTable(n, _build_columns(pool, inst, schema_name, n))
                       for n in names]
    end)
end

function _build_schemas(pool, inst, database_name::String)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_schemas(adapter, database_name)
        end
        DbCatalogSchema[DbCatalogSchema(n, _build_tables(pool, inst, n))
                        for n in names]
    end)
end

function _build_databases(pool, inst)
    CellVector(() -> begin
        names = with_connection(pool, inst) do adapter
            db_catalog_databases(adapter)
        end
        DbCatalogDatabase[DbCatalogDatabase(n, _build_schemas(pool, inst, n))
                          for n in names]
    end)
end

# ── DatabaseInstanceToDbCatalog ─────────────────────────────────────────────────

struct DatabaseInstanceToDbCatalog <: Projection
    pool::OdbcConnectionPool
end

function print_document(p::DatabaseInstanceToDbCatalog,
                          recursion, inst::DatabaseInstance, ctx)
    rdbms = DbCatalogRdbms(inst.host, inst.port, _build_databases(p.pool, inst))
    iomap = SimpleIoMap(p, inst, rdbms)
    # Forward-project the DatabaseInstance's selection onto the freshly-built
    # catalog tree so DbCatalogToSyntax can render a cursor after set_selection!.
    # The instance stores its selection in DbCatalog-domain coordinates wrapped
    # as proj(p, …) (see map_reference_backward); the forward map unwraps it.
    set_function!(getfield(rdbms, :selection), () -> begin
        sel = inst.selection
        sel === nothing && return nothing
        map_reference_forward(p, iomap, sel)
    end)
    iomap
end

# DatabaseInstanceToDbCatalog is opaque (School B): the DbCatalog tree is derived
# by querying the instance, so a selection has no structural counterpart in the
# DatabaseInstance itself. Backward wraps the catalog-domain reference as
# proj(p, …) so it can live on inst.selection; forward unwraps it. Mirrors the
# generic Projection default but strips the leading TypeReference checkpoint that
# set_selection! annotates onto the (now canonical) instance selection.
function map_reference_forward(p::DatabaseInstanceToDbCatalog, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference()
        proj(^(p), inner) => inner
    end
end

function map_reference_backward(p::DatabaseInstanceToDbCatalog, iomap, reference)
    reference isa EmptyReferencePath && return @reference()
    @reference proj(p, ^(reference))
end
# No read_intent override — the generic default in Projection.jl handles
# ToggleCollapseOperation (pass-through) and ReplaceSelectionOperation (which now
# re-targets via the non-nothing map_reference_backward above).

end # module DatabaseInstanceToDbCatalogModule

# Re-export and export public symbols at the package top level so consumers can
# `using ProjecturedOdbc` and name these types directly.
using .OdbcAdapterModule: OdbcDatabaseAdapter
using .ConnectionPoolModule: OdbcConnectionPool, with_connection, dsn_for, close_pool!
using .SqlToCellTableModule: SqlToCellTable
using .DatabaseInstanceToDbCatalogModule: DatabaseInstanceToDbCatalog

export OdbcDatabaseAdapter, OdbcConnectionPool, with_connection, dsn_for, close_pool!,
       SqlToCellTable,
       DatabaseInstanceToDbCatalog

end # module Odbc
