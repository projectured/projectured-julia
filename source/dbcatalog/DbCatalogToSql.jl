# ──────────────────────────────────────────────────────────────────────────
# Folded in from DbCatalogToSql.jl.
# Property key under which the enclosing schema name is threaded down the context.
const SCHEMA_PROPERTY = :sql_schema_name

# Recurse a single catalog child through the dispatcher, returning its built Sql
# document. Iterating a (lazy) child `CellVector` forces its query.
_recurse(recursion, ctx, child, i) =
    print_child(recursion, child, make_child_context(ctx, ElementReferenceStep(i))).output

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

function print_document(p::DbCatalogColumnToSql, recursion, col::DbCatalogColumn, ctx)
    SimpleIoMap(p, col, SqlColumnDefinition(SqlColumnName(col.name), col.data_type))
end

map_reference_forward(::DbCatalogColumnToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogColumnToSql, iomap, ref) = nothing
read_intent(::DbCatalogColumnToSql, iomap, op) = nothing

# ── DbCatalogTableToSql ──────────────────────────────────────────────────────────

struct DbCatalogTableToSql <: Projection end

function print_document(p::DbCatalogTableToSql, recursion, table::DbCatalogTable, ctx)
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
read_intent(::DbCatalogTableToSql, iomap, op) = nothing

# ── DbCatalogSchemaToSql ─────────────────────────────────────────────────────────

struct DbCatalogSchemaToSql <: Projection end

function print_document(p::DbCatalogSchemaToSql, recursion, schema::DbCatalogSchema, ctx)
    # Thread the schema name down so each table can schema-qualify its name.
    table_ctx = with_property(ctx, SCHEMA_PROPERTY, schema.name)
    stmts = Any[SqlCreateSchemaStatement(schema.name)]
    for (i, table) in enumerate(schema.tables)
        push!(stmts, _recurse(recursion, table_ctx, table, i))
    end
    SimpleIoMap(p, schema, SqlStatementList(stmts))
end

map_reference_forward(::DbCatalogSchemaToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToSql, iomap, ref) = nothing
read_intent(::DbCatalogSchemaToSql, iomap, op) = nothing

# ── DbCatalogDatabaseToSql ───────────────────────────────────────────────────────

struct DbCatalogDatabaseToSql <: Projection end

function print_document(p::DbCatalogDatabaseToSql, recursion, db::DbCatalogDatabase, ctx)
    stmts = _flatten_statements(recursion, ctx, db.schemas)
    SimpleIoMap(p, db, SqlStatementList(stmts))
end

map_reference_forward(::DbCatalogDatabaseToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToSql, iomap, ref) = nothing
read_intent(::DbCatalogDatabaseToSql, iomap, op) = nothing

# ── DbCatalogRdbmsToSql ──────────────────────────────────────────────────────────

struct DbCatalogRdbmsToSql <: Projection end

function print_document(p::DbCatalogRdbmsToSql, recursion, rdbms::DbCatalogRdbms, ctx)
    stmts = _flatten_statements(recursion, ctx, rdbms.databases)
    SimpleIoMap(p, rdbms, SqlStatementList(stmts))
end

map_reference_forward(::DbCatalogRdbmsToSql, iomap, ref) = nothing
map_reference_backward(::DbCatalogRdbmsToSql, iomap, ref) = nothing
read_intent(::DbCatalogRdbmsToSql, iomap, op) = nothing

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
