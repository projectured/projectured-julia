"""
    DbCatalogDocumentModule

Document hierarchy modelling the PostgreSQL catalog tree:
`DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`

No global state — constructors are plain wrappers with no side effects.
"""
module DbCatalogDocumentModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export DbCatalogDocument,
       DbCatalogRdbms, DbCatalogDatabase, DbCatalogSchema,
       DbCatalogTable, DbCatalogColumn

abstract type DbCatalogDocument <: Document end

@document struct DbCatalogRdbms <: DbCatalogDocument
    host::String
    port::Int
    databases::CellVector
    selection::Reference
end

@document struct DbCatalogDatabase <: DbCatalogDocument
    name::String
    schemas::CellVector
    selection::Reference
end

@document struct DbCatalogSchema <: DbCatalogDocument
    name::String
    tables::CellVector
    selection::Reference
end

@document struct DbCatalogTable <: DbCatalogDocument
    name::String
    columns::CellVector
    selection::Reference
end

@document struct DbCatalogColumn <: DbCatalogDocument
    name::String
    data_type::String
    selection::Reference
end

# Constructors
#
# The catalog is a pure data tree: each node owns its children as a CellVector
# (no adapter, no parent pointers). The `databases`/`schemas`/`tables`/`columns`
# child collections are populated lazily by the `DatabaseInstanceToDbCatalog`
# projection. The `@document` inner constructor auto-wraps raw values in Cells,
# so these convenience constructors just supply a default empty selection.
DbCatalogRdbms(host, port, databases) =
    DbCatalogRdbms(host, port, databases, Cell(nothing))
DbCatalogDatabase(name, schemas) =
    DbCatalogDatabase(name, schemas, Cell(nothing))
DbCatalogSchema(name, tables) =
    DbCatalogSchema(name, tables, Cell(nothing))
DbCatalogTable(name, columns) =
    DbCatalogTable(name, columns, Cell(nothing))
DbCatalogColumn(name, data_type) =
    DbCatalogColumn(name, data_type, Cell(nothing))

# ── Base.show ─────────────────────────────────────────────────────────────────

Base.show(io::IO, conn::DbCatalogRdbms) =
    print(io, "DbCatalogRdbms(", conn.host, ":", conn.port, ")")
Base.show(io::IO, db::DbCatalogDatabase) =
    print(io, "DbCatalogDatabase(", db.name, ")")
Base.show(io::IO, schema::DbCatalogSchema) =
    print(io, "DbCatalogSchema(", schema.name, ")")
Base.show(io::IO, table::DbCatalogTable) =
    print(io, "DbCatalogTable(", table.name, ")")
Base.show(io::IO, col::DbCatalogColumn) =
    print(io, "DbCatalogColumn(", col.name, "::", col.data_type, ")")

end # module
