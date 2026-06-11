"""
    DbCatalogToChildrenModule

Four primitive projections that expand each level of the PostgreSQL catalog
hierarchy by querying the database via the adapter stored in the parent chain.

| Projection                    | Input                | Output (CellVector)       |
|-------------------------------|----------------------|---------------------------|
| DbCatalogConnectionToChildren | DbCatalogConnection  | DbCatalogDatabase items   |
| DbCatalogDatabaseToChildren   | DbCatalogDatabase    | DbCatalogSchema items     |
| DbCatalogSchemaToChildren     | DbCatalogSchema      | DbCatalogTable items      |
| DbCatalogTableToChildren      | DbCatalogTable       | DbCatalogColumn items     |

Each printer wraps the catalog call in a reactive `CellVector` thunk so the
result is lazily evaluated and invalidated when any cell it depends on changes.
"""
module DbCatalogToChildrenModule

import ..DbCatalogDocumentModule: DbCatalogConnection, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..DatabaseModule: db_catalog_databases, db_catalog_schemas,
                         db_catalog_tables, db_catalog_columns
import ..CollectionModule: CellVector
import ..IoMapModule: SimpleIoMap
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection

export DbCatalogConnectionToChildren, DbCatalogDatabaseToChildren,
       DbCatalogSchemaToChildren, DbCatalogTableToChildren

# ── DbCatalogConnectionToChildren ─────────────────────────────────────────────

struct DbCatalogConnectionToChildren <: Projection end

function projection_print(p::DbCatalogConnectionToChildren,
                           conn::DbCatalogConnection, recursion, ctx)
    children = CellVector(() -> begin
        names = db_catalog_databases(conn.adapter)
        [DbCatalogDatabase(conn, n) for n in names]
    end)
    SimpleIoMap(p, conn, children)
end

map_reference_forward(::DbCatalogConnectionToChildren, iomap, ref) = nothing
map_reference_backward(::DbCatalogConnectionToChildren, iomap, ref) = nothing
projection_read(::DbCatalogConnectionToChildren, iomap, op) = nothing

# ── DbCatalogDatabaseToChildren ───────────────────────────────────────────────

struct DbCatalogDatabaseToChildren <: Projection end

function projection_print(p::DbCatalogDatabaseToChildren,
                           db::DbCatalogDatabase, recursion, ctx)
    children = CellVector(() -> begin
        adapter = db.connection.adapter
        names = db_catalog_schemas(adapter, db.name)
        [DbCatalogSchema(db, n) for n in names]
    end)
    SimpleIoMap(p, db, children)
end

map_reference_forward(::DbCatalogDatabaseToChildren, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToChildren, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToChildren, iomap, op) = nothing

# ── DbCatalogSchemaToChildren ─────────────────────────────────────────────────

struct DbCatalogSchemaToChildren <: Projection end

function projection_print(p::DbCatalogSchemaToChildren,
                           schema::DbCatalogSchema, recursion, ctx)
    children = CellVector(() -> begin
        adapter = schema.database.connection.adapter
        names = db_catalog_tables(adapter, schema.name)
        [DbCatalogTable(schema, n) for n in names]
    end)
    SimpleIoMap(p, schema, children)
end

map_reference_forward(::DbCatalogSchemaToChildren, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToChildren, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToChildren, iomap, op) = nothing

# ── DbCatalogTableToChildren ──────────────────────────────────────────────────

struct DbCatalogTableToChildren <: Projection end

function projection_print(p::DbCatalogTableToChildren,
                           table::DbCatalogTable, recursion, ctx)
    children = CellVector(() -> begin
        adapter = table.schema.database.connection.adapter
        schema_name = table.schema.name
        cols = db_catalog_columns(adapter, schema_name, table.name)
        [DbCatalogColumn(table, c.name, c.data_type) for c in cols]
    end)
    SimpleIoMap(p, table, children)
end

map_reference_forward(::DbCatalogTableToChildren, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToChildren, iomap, ref) = nothing
projection_read(::DbCatalogTableToChildren, iomap, op) = nothing

end # module
