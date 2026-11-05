# Fragment of `DbCatalogModule` — the database-catalog document types: the
# abstract `DbCatalogDocument` and the server, database, table and column nodes
# a catalog tree holds.

"""
    DbCatalogDocument

The abstract supertype of the documents of a database catalog. Its main members are `DbCatalogRdbms`, `DbCatalogDatabase`, `DbCatalogSchema`, `DbCatalogTable`, `DbCatalogColumn`.

Use it to recognise the documents of a database catalog when you walk a document: a part is one of them when `part isa DbCatalogDocument`.

# Example

    parts_1 = search_documents(get_edited_document(find_pane("catalog")), part -> part isa DbCatalogDocument)
    found_1 = search_documents(get_edited_document(find_pane("catalog")), part -> part isa DbCatalogTable)

See also `search_documents`, `find_pane`, `describe_document` and `DbCatalogTable`.

For the assistant.
"""
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
