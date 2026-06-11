"""
    DbCatalogToJsonModule

DbCatalog → JsonDocument projection. Maps each DbCatalog document type to a
JsonObject containing only its data fields (excluding parent references and
selection fields). Read-only projection with no reference mapping or read support.
"""
module DbCatalogToJsonModule

import ..ReactiveModule: Cell
import ..DbCatalogDocumentModule: DbCatalogDocument, DbCatalogConnection, DbCatalogDatabase,
                                   DbCatalogSchema, DbCatalogTable, DbCatalogColumn
import ..JsonModule: JsonObject, JsonString, JsonNumber
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..TypeDispatchingModule: TypeDispatchingProjection

export DbCatalogConnectionToJson, DbCatalogDatabaseToJson, DbCatalogSchemaToJson,
       DbCatalogTableToJson, DbCatalogColumnToJson, DbCatalogToJson

# ── DbCatalogConnectionToJson ───────────────────────────────────────────────────

struct DbCatalogConnectionToJson <: Projection end

function projection_print(p::DbCatalogConnectionToJson, conn::DbCatalogConnection, recursion, ctx)
    obj = JsonObject(
        "host" => JsonString(conn.host),
        "port" => JsonNumber(conn.port)
    )
    SimpleIoMap(p, conn, obj)
end

map_reference_forward(::DbCatalogConnectionToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogConnectionToJson, iomap, ref) = nothing
projection_read(::DbCatalogConnectionToJson, iomap, op) = nothing

# ── DbCatalogDatabaseToJson ────────────────────────────────────────────────────

struct DbCatalogDatabaseToJson <: Projection end

function projection_print(p::DbCatalogDatabaseToJson, db::DbCatalogDatabase, recursion, ctx)
    obj = JsonObject(
        "name" => JsonString(db.name)
    )
    SimpleIoMap(p, db, obj)
end

map_reference_forward(::DbCatalogDatabaseToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogDatabaseToJson, iomap, ref) = nothing
projection_read(::DbCatalogDatabaseToJson, iomap, op) = nothing

# ── DbCatalogSchemaToJson ──────────────────────────────────────────────────────

struct DbCatalogSchemaToJson <: Projection end

function projection_print(p::DbCatalogSchemaToJson, schema::DbCatalogSchema, recursion, ctx)
    obj = JsonObject(
        "name" => JsonString(schema.name)
    )
    SimpleIoMap(p, schema, obj)
end

map_reference_forward(::DbCatalogSchemaToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogSchemaToJson, iomap, ref) = nothing
projection_read(::DbCatalogSchemaToJson, iomap, op) = nothing

# ── DbCatalogTableToJson ───────────────────────────────────────────────────────

struct DbCatalogTableToJson <: Projection end

function projection_print(p::DbCatalogTableToJson, table::DbCatalogTable, recursion, ctx)
    obj = JsonObject(
        "name" => JsonString(table.name)
    )
    SimpleIoMap(p, table, obj)
end

map_reference_forward(::DbCatalogTableToJson, iomap, ref) = nothing
map_reference_backward(::DbCatalogTableToJson, iomap, ref) = nothing
projection_read(::DbCatalogTableToJson, iomap, op) = nothing

# ── DbCatalogColumnToJson ──────────────────────────────────────────────────────

struct DbCatalogColumnToJson <: Projection end

function projection_print(p::DbCatalogColumnToJson, col::DbCatalogColumn, recursion, ctx)
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
        DbCatalogConnection => DbCatalogConnectionToJson(),
        DbCatalogDatabase => DbCatalogDatabaseToJson(),
        DbCatalogSchema => DbCatalogSchemaToJson(),
        DbCatalogTable => DbCatalogTableToJson(),
        DbCatalogColumn => DbCatalogColumnToJson(),
    )
end

end # module
