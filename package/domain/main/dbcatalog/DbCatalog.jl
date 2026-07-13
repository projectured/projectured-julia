"""
    DbCatalogDocumentModule

Document hierarchy modelling the PostgreSQL catalog tree:
`DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`

No global state — constructors are plain wrappers with no side effects.
"""
module DbCatalogDocumentModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export DbCatalogDocument

abstract type DbCatalogDocument <: Document end

@document struct DbCatalogRdbms <: DbCatalogDocument
    host::String
    port::Int
    databases::CellVector
end

@document struct DbCatalogDatabase <: DbCatalogDocument
    name::String
    schemas::CellVector
end

@document struct DbCatalogSchema <: DbCatalogDocument
    name::String
    tables::CellVector
end

@document struct DbCatalogTable <: DbCatalogDocument
    name::String
    columns::CellVector
end

@document struct DbCatalogColumn <: DbCatalogDocument
    name::String
    data_type::String
end

# Concise `show` for the five catalog document types. The @document macro's
# default lists every field (host / port / CellVector spew) which is unusable
# in the REPL and useless in stack traces. These variants render only the
# identifying scalar(s), matching the T5 expectations.
Base.show(io::IO, r::DbCatalogRdbms)    = print(io, "DbCatalogRdbms(", r.host, ":", r.port, ")")
Base.show(io::IO, d::DbCatalogDatabase) = print(io, "DbCatalogDatabase(", d.name, ")")
Base.show(io::IO, s::DbCatalogSchema)   = print(io, "DbCatalogSchema(", s.name, ")")
Base.show(io::IO, t::DbCatalogTable)    = print(io, "DbCatalogTable(", t.name, ")")
Base.show(io::IO, c::DbCatalogColumn)   = print(io, "DbCatalogColumn(", c.name, "::", c.data_type, ")")

end # module
