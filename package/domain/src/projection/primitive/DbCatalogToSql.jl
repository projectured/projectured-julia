"""
    DbCatalogToSqlModule

DbCatalog → Sql (DDL) projection. Maps the catalog tree into **SQL DDL document
nodes** built directly, so the existing SQL pipeline
(`SqlToSyntax → SyntaxToText → TextToString`) turns the catalog into an
executable `CREATE …` script:

    DbCatalogColumn   → SqlColumnDefinition(name, data_type)
    DbCatalogTable    → CREATE TABLE [schema.]table ( <column-def>, … )
    DbCatalogSchema   → CREATE SCHEMA name;  +  one CREATE TABLE per table
    DbCatalogDatabase → every schema's statements, flattened
    DbCatalogRdbms    → every database's statements, flattened

The DDL view is the compound `ChainingProjection(DbCatalogToSql(), SqlToSyntax())`
(each stage wrapped in `RecursiveProjection`) — `SqlToSyntax` stays the single
source of truth for SQL text. This projection **constructs the SQL documents
directly** (not print-and-parse).

The enclosing schema name is threaded down through the printer context (the
`:sql_schema_name` property) so a table can schema-qualify its `CREATE TABLE`.

Read-only: a serialiser for LLM consumption, not an editor view, so reference
mapping / read support return `nothing`. The catalog child collections are lazy
`CellVector`s, and recursing each child through `projection_printer_recurse`
forces the whole subtree, so wrapping this in a `RecursiveProjection` fully walks
the catalog.
"""
module DbCatalogToSqlModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..DbCatalogDocumentModule: DbCatalogDocument, DbCatalogRdbms, DbCatalogDatabase,
                                  DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..SqlDocumentModule: SqlColumnDefinition, SqlCreateTableStatement,
                            SqlCreateSchemaStatement, SqlStatementList,
                            SqlTableName, SqlColumnName
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: ElementReference
import ..PrinterContextModule: child_context, with_property, get_property

export DbCatalogRdbmsToSql, DbCatalogDatabaseToSql, DbCatalogSchemaToSql,
       DbCatalogTableToSql, DbCatalogColumnToSql, DbCatalogToSql

# Property key under which the enclosing schema name is threaded down the context.
const SCHEMA_PROPERTY = :sql_schema_name

# Recurse a single catalog child through the dispatcher, returning its built Sql
# document. Iterating a (lazy) child `CellVector` forces its query.
_recurse(recursion, ctx, child, i) =
    projection_printer_recurse(recursion, child, child_context(ctx, ElementReference(i))).output

# Flatten a sequence of catalog children — each of which projects to a
# `SqlStatementList` — into one flat vector of statements.
function _flatten_statements(recursion, ctx, children)
    stmts = Any[]
    for (i, child) in enumerate(children)
        sub = _recurse(recursion, ctx, child, i)
        append!(stmts, collect(sub.statements))
    end
    stmts
end

# ── DbCatalogColumnToSql ─────────────────────────────────────────────────────────

struct DbCatalogColumnToSql <: Projection end

function projection_print(p::DbCatalogColumnToSql, recursion, col::DbCatalogColumn, ctx)
    SimpleIoMap(p, col, SqlColumnDefinition(SqlColumnName(col.name), col.data_type))
end

map_reference_forward(::DbCatalogColumnToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogColumnToSql, iomap, ref) = nothing
projection_read(::DbCatalogColumnToSql, iomap, op) = nothing

# ── DbCatalogTableToSql ──────────────────────────────────────────────────────────

struct DbCatalogTableToSql <: Projection end

function projection_print(p::DbCatalogTableToSql, recursion, table::DbCatalogTable, ctx)
    schema = get_property(ctx, SCHEMA_PROPERTY, nothing)
    table_name = schema === nothing ? SqlTableName(table.name) :
                                      SqlTableName(schema, table.name)
    columns = SqlColumnDefinition[
        _recurse(recursion, ctx, col, i) for (i, col) in enumerate(table.columns)]
    SimpleIoMap(p, table,
        SqlCreateTableStatement(table_name, CellVector(columns)))
end

map_reference_forward(::DbCatalogTableToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToSql, iomap, ref) = nothing
projection_read(::DbCatalogTableToSql, iomap, op) = nothing

# ── DbCatalogSchemaToSql ─────────────────────────────────────────────────────────

struct DbCatalogSchemaToSql <: Projection end

function projection_print(p::DbCatalogSchemaToSql, recursion, schema::DbCatalogSchema, ctx)
    # Thread the schema name down so each table can schema-qualify its name.
    table_ctx = with_property(ctx, SCHEMA_PROPERTY, schema.name)
    stmts = Any[SqlCreateSchemaStatement(schema.name)]
    for (i, table) in enumerate(schema.tables)
        push!(stmts, _recurse(recursion, table_ctx, table, i))
    end
    SimpleIoMap(p, schema, SqlStatementList(CellVector(stmts)))
end

map_reference_forward(::DbCatalogSchemaToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToSql, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToSql, iomap, op) = nothing

# ── DbCatalogDatabaseToSql ───────────────────────────────────────────────────────

struct DbCatalogDatabaseToSql <: Projection end

function projection_print(p::DbCatalogDatabaseToSql, recursion, db::DbCatalogDatabase, ctx)
    stmts = _flatten_statements(recursion, ctx, db.schemas)
    SimpleIoMap(p, db, SqlStatementList(CellVector(stmts)))
end

map_reference_forward(::DbCatalogDatabaseToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToSql, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToSql, iomap, op) = nothing

# ── DbCatalogRdbmsToSql ──────────────────────────────────────────────────────────

struct DbCatalogRdbmsToSql <: Projection end

function projection_print(p::DbCatalogRdbmsToSql, recursion, rdbms::DbCatalogRdbms, ctx)
    stmts = _flatten_statements(recursion, ctx, rdbms.databases)
    SimpleIoMap(p, rdbms, SqlStatementList(CellVector(stmts)))
end

map_reference_forward(::DbCatalogRdbmsToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogRdbmsToSql, iomap, ref) = nothing
projection_read(::DbCatalogRdbmsToSql, iomap, op) = nothing

# ── Compound convenience constructor ─────────────────────────────────────────────

function DbCatalogToSql()
    TypeDispatchingProjection(
        DbCatalogRdbms    => DbCatalogRdbmsToSql(),
        DbCatalogDatabase => DbCatalogDatabaseToSql(),
        DbCatalogSchema   => DbCatalogSchemaToSql(),
        DbCatalogTable    => DbCatalogTableToSql(),
        DbCatalogColumn   => DbCatalogColumnToSql(),
    )
end

end # module
