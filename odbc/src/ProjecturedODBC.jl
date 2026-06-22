"""
    ProjecturedODBC

Opt-in package: live ODBC database access (OdbcDatabaseAdapter, connection pool,
and the live-query projections). Depends on `ProjecturedDomain` + ODBC/DBInterface/
Tables; `using ProjecturedODBC` registers `make_database_adapter(:odbc)` and exposes
the adapter, pool, and live-query projection types. (The SQL/DbCatalog documents and
their pure projections stay in `ProjecturedDomain` — only live querying lives here.)
"""
module ProjecturedODBC

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

module DatabaseTabularModule

import DBInterface
import Tables
import ProjecturedDomain.DatabaseModule: db_query
import ..OdbcAdapterModule: OdbcDatabaseAdapter
import ProjecturedDomain.TabularModule: TabularGrid, TabularRow, TabularCell
import ProjecturedDomain.CollectionModule: CellVector
import ProjecturedDomain.ReactiveModule: Cell

"""
    db_query(adapter, table, ::Type{TabularGrid}; columns, where, limit) -> TabularGrid

Single-pass query into a `TabularGrid`. Row 1 is the header (column names as
`TabularCell` values); rows 2..n are data rows. `ctid` is fetched internally
but not included in the grid. Use `DatabaseTableToTabularGrid` projection when
you need the full `DatabaseTableIoMap` with `ctid` values for editing.
"""
function db_query(adapter::OdbcDatabaseAdapter, table::String,
                  ::Type{TabularGrid};
                  columns=nothing, where=nothing, limit=nothing)::TabularGrid
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT $(col_part) FROM \"$(table)\""
    where !== nothing && (sql *= " WHERE $(where)")
    limit !== nothing && (sql *= " LIMIT $(limit)")
    ct = Tables.columntable(DBInterface.execute(adapter._conn, sql))
    col_names = String[String(n) for n in propertynames(ct)]
    col_count = length(col_names)
    nrows = col_count == 0 ? 0 : length(ct[1])
    header = Cell(TabularRow(CellVector(
        Cell[Cell(TabularCell(name)) for name in col_names])))
    data_rows = Cell[]
    for r in 1:nrows
        vals = Any[ct[j][r] for j in 1:col_count]
        push!(data_rows, Cell(TabularRow(CellVector(
            Cell[Cell(TabularCell(v)) for v in vals]))))
    end
    TabularGrid(CellVector(vcat([header], data_rows)), col_count)
end

end # module DatabaseTabularModule

module DatabaseTableToTabularGridModule

import DBInterface
import Tables
import ProjecturedDomain.DatabaseModule: db_update!, db_insert!
import ..OdbcAdapterModule: OdbcDatabaseAdapter
import ProjecturedDomain.DatabaseDocumentModule: DatabaseTable,
                                  DatabaseUpdateOperation, DatabaseInsertOperation
import ProjecturedDomain.TabularModule: TabularGrid, TabularRow, TabularCell
import ProjecturedDomain.CollectionModule: CellVector
import ProjecturedDomain.ReactiveModule: Cell
import ProjecturedDomain.ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedDomain.IoMapApiModule: IoMap
import ProjecturedDomain.ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath, skip_type_checkpoints,
                          FieldReference, RangeReference, is_element_reference, strip_reference_types
import ProjecturedDomain.OperationModule: ReplaceSelectionOperation
import ProjecturedDomain.PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ProjecturedDomain.OperationApiModule: evaluate_operation
import ProjecturedDomain.ReferenceBuilderModule: var"@reference"

export DatabaseTableIoMap, DatabaseTableToTabularGrid

# ── DatabaseTableIoMap ────────────────────────────────────────────────────────

"""
    DatabaseTableIoMap

Custom IoMap for `DatabaseTableToTabularGrid`. Carries `column_names` and
`ctid_values` captured at query time so the reader can map a grid cell edit
to a SQL UPDATE without re-querying.
"""
struct DatabaseTableIoMap <: IoMap
    projection::Any     # DatabaseTableToTabularGrid
    input::Any          # DatabaseTable
    output::Any         # TabularGrid
    column_names::Cell  # Vector{String} — reactive, recomputed on re-query
    ctid_values::Cell   # Vector{Any}    — one ctid per data row (rows 2..n)
end

# ── DatabaseTableToTabularGrid ────────────────────────────────────────────────

"""
    DatabaseTableToTabularGrid

Projection: `DatabaseTable` → `TabularGrid`.

The printer lazily executes `SELECT ctid, * FROM <table> [WHERE ...] [LIMIT ...]`
inside a reactive Cell thunk. The query fires on first render and automatically
re-executes when any field of the `DatabaseTable` document changes.

Row 1 of the produced `TabularGrid` is a header containing column names as
`TabularCell` values. Rows 2..n are data rows. `ctid` is fetched but not
displayed — it is stored in `DatabaseTableIoMap.ctid_values` for the reader.
"""
struct DatabaseTableToTabularGrid <: Projection end

# ── Private helpers ───────────────────────────────────────────────────────────

function _query_with_ctid(adapter, table, columns, where_clause, limit)
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT ctid, $(col_part) FROM \"$(table)\""
    where_clause !== nothing && (sql *= " WHERE $(where_clause)")
    limit        !== nothing && (sql *= " LIMIT $(limit)")
    ct = Tables.columntable(DBInterface.execute(adapter._conn, sql))
    all_cols = String[String(n) for n in propertynames(ct)]
    ctid_idx = findfirst(==("ctid"), all_cols)
    col_names   = String[c for (i, c) in enumerate(all_cols) if i != ctid_idx]
    nrows       = isempty(all_cols) ? 0 : length(ct[1])
    ctid_values = Any[]
    data_rows   = Vector{Vector{Any}}()
    for r in 1:nrows
        push!(ctid_values, ct[ctid_idx][r])
        push!(data_rows, Any[ct[i][r] for i in 1:length(all_cols) if i != ctid_idx])
    end
    col_names, ctid_values, data_rows
end

function _make_header_row(col_names::Vector{String})
    TabularRow(CellVector(Cell[Cell(TabularCell(name)) for name in col_names]))
end

function _make_data_row(vals::Vector{Any})
    TabularRow(CellVector(Cell[Cell(TabularCell(v)) for v in vals]))
end

function _decode_grid_cell(path::ReferencePath)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return nothing, nothing
    path.head isa FieldReference && path.head.name == "rows" || return nothing, nothing
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    h = path.head
    h isa RangeReference && is_element_reference(h) || return nothing, nothing
    r = h.start + 1
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    path.head isa FieldReference && path.head.name == "cells" || return nothing, nothing
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    h = path.head
    h isa RangeReference && is_element_reference(h) || return nothing, nothing
    c = h.start + 1

    r, c
end

function _cell_string_value(grid::TabularGrid, r::Int, c::Int)
    row = grid.rows[r]
    row isa TabularRow || return nothing
    length(row.cells) < c && return nothing
    cell = row.cells[c]
    cell isa TabularCell || return nothing
    string(cell.content)
end

function _apply_range_replacement(current::String, step::RangeReference, replacement::String)
    s = max(0, step.start)
    e = min(length(current), step.stop)
    current[1:s] * replacement * current[e+1:end]
end

function _compute_new_value(grid::TabularGrid, r::Int, c::Int,
                             ref::ReferencePath, replacement::String)
    current = _cell_string_value(grid, r, c)
    current === nothing && return replacement
    range_step = nothing
    path = strip_reference_types(ref)
    while path isa ConcreteReferencePath
        h = path.head
        if h isa RangeReference && !(path.tail isa ConcreteReferencePath)
            range_step = h
        end
        path = path.tail
    end
    range_step === nothing && return replacement
    _apply_range_replacement(current, range_step, replacement)
end

# ── projection_print ──────────────────────────────────────────────────────────

function projection_print(p::DatabaseTableToTabularGrid,
                           recursion,
                           doc::DatabaseTable, ctx)
    raw = Cell(() -> _query_with_ctid(doc.adapter, doc.table,
                                      doc.columns, doc.where_clause, doc.limit))
    col_names_cell   = Cell(() -> raw[][1])
    ctid_values_cell = Cell(() -> raw[][2])
    rows = CellVector(() -> begin
        col_names, _, data_rows = raw[]
        header = _make_header_row(col_names)
        data   = [_make_data_row(r) for r in data_rows]
        vcat([header], data)
    end)
    col_count = Cell(() -> length(col_names_cell[]))
    grid = TabularGrid(rows, col_count, Cell(nothing))
    DatabaseTableIoMap(p, doc, grid, col_names_cell, ctid_values_cell)
end

# ── Reference mapping ─────────────────────────────────────────────────────────

function map_reference_forward(::DatabaseTableToTabularGrid, iomap, reference)
    skip_type_checkpoints(reference) isa EmptyReferencePath ? EmptyReferencePath() : nothing
end

function map_reference_backward(p::DatabaseTableToTabularGrid, iomap, reference)
    skip_type_checkpoints(reference) isa EmptyReferencePath && return EmptyReferencePath()
    @reference proj(p, ^(reference))
end

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(p::DatabaseTableToTabularGrid,
                          iomap::DatabaseTableIoMap,
                          op)
    if op isa ReplaceSelectionOperation
        ref = map_reference_backward(p, iomap, op.path)
        ref === nothing && return nothing
        return ReplaceSelectionOperation(ref, op.from_click)
    end

    ref_path    = nothing
    replacement = ""
    if op isa StringReplaceRangeOperation
        ref_path    = op.reference
        replacement = op.replacement
    elseif op isa NumberReplaceRangeOperation
        ref_path    = op.reference
        replacement = op.replacement
    else
        return nothing
    end

    r, c = _decode_grid_cell(ref_path)
    r === nothing && return nothing
    r == 1        && return nothing  # header row: read-only

    ctids = iomap.ctid_values[]
    (r - 1) > length(ctids) && return nothing
    ctid = ctids[r - 1]

    col_names = iomap.column_names[]
    c > length(col_names) && return nothing
    column = col_names[c]

    new_value = _compute_new_value(iomap.output, r, c, ref_path, replacement)
    DatabaseUpdateOperation(iomap.input.adapter, iomap.input.table,
                            ctid, column, new_value)
end

# ── Operation evaluators ──────────────────────────────────────────────────────

function evaluate_operation(editor, op::DatabaseUpdateOperation)
    where_clause = "ctid = '$(op.ctid)'::tid"
    db_update!(op.adapter, op.table,
               Dict{String,Any}(op.column => op.new_value),
               where_clause)
    nothing
end

function evaluate_operation(editor, op::DatabaseInsertOperation)
    db_insert!(op.adapter, op.table, op.row)
    nothing
end

end # module DatabaseTableToTabularGridModule

module SqlToCellTableModule

import ProjecturedDomain.ReactiveModule: Cell
import ProjecturedDomain.CollectionModule: CellVector, CellTable
import ProjecturedDomain.ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ProjecturedDomain.SqlDocumentModule: SqlSelectStatement
import ProjecturedDomain.SqlToSyntaxModule: SqlToSyntax
import ProjecturedDomain.SyntaxToTextModule: SyntaxToText
import ProjecturedDomain.TextToStringModule: TextToString
import ProjecturedDomain.RecursiveProjectionModule: RecursiveProjection
import ProjecturedDomain.SequentialProjectionModule: SequentialProjection
import ProjecturedDomain.DatabaseInstanceDocumentModule: DatabaseInstance
import ProjecturedDomain.DatabaseModule: RawDatabaseResult, db_execute_raw
import ..ConnectionPoolModule: OdbcConnectionPool, with_connection
import ProjecturedDomain.IoMapModule: SimpleIoMap

export SqlToCellTable

struct SqlToCellTable <: Projection
    pool::OdbcConnectionPool
    instance::DatabaseInstance
end

function projection_print(p::SqlToCellTable, recursion, stmt::SqlSelectStatement, ctx)
    raw = Cell(() -> begin
        pipe = SequentialProjection(
            RecursiveProjection(SqlToSyntax()),
            RecursiveProjection(SyntaxToText()),
            RecursiveProjection(TextToString()))
        sql = projection_print(pipe, stmt).output[]
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
projection_read(::SqlToCellTable, iomap, op) = nothing

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
import ProjecturedDomain.ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection

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

function projection_print(p::DatabaseInstanceToDbCatalog,
                          recursion, inst::DatabaseInstance, ctx)
    rdbms = DbCatalogRdbms(inst.host, inst.port, _build_databases(p.pool, inst))
    SimpleIoMap(p, inst, rdbms)
end

map_reference_forward(::DatabaseInstanceToDbCatalog, iomap, ref) = nothing
map_reference_backward(::DatabaseInstanceToDbCatalog, iomap, ref) = nothing
# No projection_read override — the generic default in Projection.jl handles
# ToggleCollapseOperation (pass-through) and ReplaceSelectionOperation (returns
# nothing because map_reference_backward returns nothing) correctly.

end # module DatabaseInstanceToDbCatalogModule

# Re-export and export public symbols at the package top level so consumers can
# `using ProjecturedODBC` and name these types directly.
using .OdbcAdapterModule: OdbcDatabaseAdapter
using .ConnectionPoolModule: OdbcConnectionPool, with_connection, dsn_for, close_pool!
using .DatabaseTableToTabularGridModule: DatabaseTableToTabularGrid, DatabaseTableIoMap
using .SqlToCellTableModule: SqlToCellTable
using .DatabaseInstanceToDbCatalogModule: DatabaseInstanceToDbCatalog

export OdbcDatabaseAdapter, OdbcConnectionPool, with_connection, dsn_for, close_pool!,
       DatabaseTableToTabularGrid, DatabaseTableIoMap, SqlToCellTable,
       DatabaseInstanceToDbCatalog

end # module ProjecturedODBC
