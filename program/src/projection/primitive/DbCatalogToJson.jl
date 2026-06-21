"""
    DbCatalogToJsonModule

DbCatalog → JsonDocument projection. Maps each DbCatalog document type to a
JsonObject of its own data fields plus a nested array of its recursively-projected
children, so the whole `databases → schemas → tables → columns` hierarchy renders
as one nested JSON tree:

    DbCatalogRdbms    → {"host", "port", "databases": [ … ]}
    DbCatalogDatabase → {"name", "schemas": [ … ]}
    DbCatalogSchema   → {"name", "tables": [ … ]}
    DbCatalogTable    → {"name", "columns": [ … ]}
    DbCatalogColumn   → {"name", "data_type"}

Parent-reference and selection fields are excluded. Each non-leaf level recurses
through `projection_printer_recurse`, so wrapping this in a `RecursiveProjection`
**fully walks** the catalog — every per-table column query is forced — exactly
like the generic `ObjectToJson` / `ObjectToSyntax` paths.

Read-only: no reference mapping or read support.
"""
module DbCatalogToJsonModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..DbCatalogDocumentModule: DbCatalogDocument, DbCatalogRdbms, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..JsonModule: JsonObject, JsonArray, JsonString, JsonNumber
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceModule: ElementReference
import ..PrinterContextModule: child_context

export DbCatalogRdbmsToJson, DbCatalogDatabaseToJson, DbCatalogSchemaToJson,
       DbCatalogTableToJson, DbCatalogColumnToJson, DbCatalogToJson

# Build a JsonArray of the recursively-projected children. Iterating the (lazy)
# child `CellVector` forces its query, and recursing each element through
# `recursion` re-enters the full pipeline — so the catalog is fully walked.
function _children_array(recursion, ctx, children)
    elements = Cell[
        Cell(projection_printer_recurse(recursion, child,
                 child_context(ctx, ElementReference(i))).output)
        for (i, child) in enumerate(children)
    ]
    JsonArray(CellVector(elements), Cell(false), Cell(nothing))
end

# ── DbCatalogRdbmsToJson ────────────────────────────────────────────────────────

struct DbCatalogRdbmsToJson <: Projection end

function projection_print(p::DbCatalogRdbmsToJson, recursion, rdbms::DbCatalogRdbms, ctx)
    obj = JsonObject(
        "host" => JsonString(rdbms.host),
        "port" => JsonNumber(rdbms.port),
        "databases" => _children_array(recursion, ctx, rdbms.databases)
    )
    SimpleIoMap(p, rdbms, obj)
end

map_reference_forward(::DbCatalogRdbmsToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogRdbmsToJson, iomap, ref) = nothing
projection_read(::DbCatalogRdbmsToJson, iomap, op) = nothing

# ── DbCatalogDatabaseToJson ────────────────────────────────────────────────────

struct DbCatalogDatabaseToJson <: Projection end

function projection_print(p::DbCatalogDatabaseToJson, recursion, db::DbCatalogDatabase, ctx)
    obj = JsonObject(
        "name" => JsonString(db.name),
        "schemas" => _children_array(recursion, ctx, db.schemas)
    )
    SimpleIoMap(p, db, obj)
end

map_reference_forward(::DbCatalogDatabaseToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToJson, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToJson, iomap, op) = nothing

# ── DbCatalogSchemaToJson ──────────────────────────────────────────────────────

struct DbCatalogSchemaToJson <: Projection end

function projection_print(p::DbCatalogSchemaToJson, recursion, schema::DbCatalogSchema, ctx)
    obj = JsonObject(
        "name" => JsonString(schema.name),
        "tables" => _children_array(recursion, ctx, schema.tables)
    )
    SimpleIoMap(p, schema, obj)
end

map_reference_forward(::DbCatalogSchemaToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToJson, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToJson, iomap, op) = nothing

# ── DbCatalogTableToJson ───────────────────────────────────────────────────────

struct DbCatalogTableToJson <: Projection end

function projection_print(p::DbCatalogTableToJson, recursion, table::DbCatalogTable, ctx)
    obj = JsonObject(
        "name" => JsonString(table.name),
        "columns" => _children_array(recursion, ctx, table.columns)
    )
    SimpleIoMap(p, table, obj)
end

map_reference_forward(::DbCatalogTableToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToJson, iomap, ref) = nothing
projection_read(::DbCatalogTableToJson, iomap, op) = nothing

# ── DbCatalogColumnToJson ──────────────────────────────────────────────────────

struct DbCatalogColumnToJson <: Projection end

function projection_print(p::DbCatalogColumnToJson, recursion, col::DbCatalogColumn, ctx)
    obj = JsonObject(
        "name" => JsonString(col.name),
        "data_type" => JsonString(col.data_type)
    )
    SimpleIoMap(p, col, obj)
end

map_reference_forward(::DbCatalogColumnToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogColumnToJson, iomap, ref) = nothing
projection_read(::DbCatalogColumnToJson, iomap, op) = nothing

# ── Compound convenience constructor ────────────────────────────────────────────

function DbCatalogToJson()
    TypeDispatchingProjection(
        DbCatalogRdbms => DbCatalogRdbmsToJson(),
        DbCatalogDatabase => DbCatalogDatabaseToJson(),
        DbCatalogSchema => DbCatalogSchemaToJson(),
        DbCatalogTable => DbCatalogTableToJson(),
        DbCatalogColumn => DbCatalogColumnToJson(),
    )
end

end # module
