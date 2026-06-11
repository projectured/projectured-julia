"""
    DbCatalogDocumentModule

Document hierarchy modelling the PostgreSQL catalog tree:
`DbCatalogConnection → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`

No global state — constructors are plain wrappers with no side effects.
"""
module DbCatalogDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference

export DbCatalogDocument,
       DbCatalogConnection, DbCatalogDatabase, DbCatalogSchema,
       DbCatalogTable, DbCatalogColumn

abstract type DbCatalogDocument <: Document end

@document struct DbCatalogConnection <: DbCatalogDocument
    adapter::Any
    host::String
    port::Int
    selection::Reference
end

@document struct DbCatalogDatabase <: DbCatalogDocument
    connection::DbCatalogConnection
    name::String
    selection::Reference
end

@document struct DbCatalogSchema <: DbCatalogDocument
    database::DbCatalogDatabase
    name::String
    selection::Reference
end

@document struct DbCatalogTable <: DbCatalogDocument
    schema::DbCatalogSchema
    name::String
    selection::Reference
end

@document struct DbCatalogColumn <: DbCatalogDocument
    table::DbCatalogTable
    name::String
    data_type::String
    selection::Reference
end

# Constructors
DbCatalogConnection(adapter; host="localhost", port=5432) =
    DbCatalogConnection(Cell(adapter), Cell(host), Cell(port), Cell(nothing))
DbCatalogDatabase(connection, name) =
    DbCatalogDatabase(Cell(connection), Cell(name), Cell(nothing))
DbCatalogSchema(database, name) =
    DbCatalogSchema(Cell(database), Cell(name), Cell(nothing))
DbCatalogTable(schema, name) =
    DbCatalogTable(Cell(schema), Cell(name), Cell(nothing))
DbCatalogColumn(table, name, data_type) =
    DbCatalogColumn(Cell(table), Cell(name), Cell(data_type), Cell(nothing))

# ── Base.show ─────────────────────────────────────────────────────────────────

Base.show(io::IO, conn::DbCatalogConnection) =
    print(io, "DbCatalogConnection(", conn.host, ":", conn.port, ")")
Base.show(io::IO, db::DbCatalogDatabase) =
    print(io, "DbCatalogDatabase(", db.name, ")")
Base.show(io::IO, schema::DbCatalogSchema) =
    print(io, "DbCatalogSchema(", schema.name, ")")
Base.show(io::IO, table::DbCatalogTable) =
    print(io, "DbCatalogTable(", table.name, ")")
Base.show(io::IO, col::DbCatalogColumn) =
    print(io, "DbCatalogColumn(", col.name, "::", col.data_type, ")")

end # module
