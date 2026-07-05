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
    selection::Reference = nothing
end

@document struct DbCatalogDatabase <: DbCatalogDocument
    name::String
    schemas::CellVector
    selection::Reference = nothing
end

@document struct DbCatalogSchema <: DbCatalogDocument
    name::String
    tables::CellVector
    selection::Reference = nothing
end

@document struct DbCatalogTable <: DbCatalogDocument
    name::String
    columns::CellVector
    selection::Reference = nothing
end

@document struct DbCatalogColumn <: DbCatalogDocument
    name::String
    data_type::String
    selection::Reference = nothing
end


end # module
