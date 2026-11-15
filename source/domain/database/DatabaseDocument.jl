# ── The database documents ────────────────────────────────────────────────────
#
# A table and the two edits a cell and a row accept.

# ── Abstract base ─────────────────────────────────────────────────────────────

"""
    DatabaseDocument

The abstract supertype of the documents of a database table. Its main members are `DatabaseTable`.

Use it to recognise the documents of a database table when you walk a document: a part is one of them when `part isa DatabaseDocument`.

# Example

    parts_1 = search_documents(get_edited_document(find_pane("table")), part -> part isa DatabaseDocument)
    found_1 = search_documents(get_edited_document(find_pane("table")), part -> part isa DatabaseTable)

See also `search_documents`, `find_pane`, `describe_document` and `DatabaseTable`.

For the assistant.
"""
abstract type DatabaseDocument <: Document end

# ── DatabaseTable ─────────────────────────────────────────────────────────────

"""
A database table query spec — adapter + table name + optional column list,
WHERE fragment, and row limit. No query results are cached here.
"""
@document struct DatabaseTable <: DatabaseDocument
    adapter::Any
    table::String
    columns::Any = nothing
    where_clause::Any = nothing
    limit::Any = nothing
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
Updates a single cell identified by `ctid` in `table`.
"""
struct UpdateDatabaseCellOperation <: Operation
    adapter::Any
    table::String
    ctid::Any          # e.g. "(0,1)"
    column::String
    new_value::Any
end

"""
Inserts a new row into `table`.
"""
struct InsertDatabaseRowOperation <: Operation
    adapter::Any
    table::String
    row::Dict{String,Any}
end
