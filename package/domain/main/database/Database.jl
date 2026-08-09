"""
    DatabaseDocumentModule

Document layer for database access. `DatabaseTable` is pure query metadata
(no result cache); `DatabaseUpdateOperation` / `DatabaseInsertOperation` are
the mutations the projection reader produces.
"""
module DatabaseDocumentModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..OperationModule: Operation

export DatabaseDocument, DatabaseUpdateOperation, DatabaseInsertOperation

# ── Abstract base ─────────────────────────────────────────────────────────────

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
struct DatabaseUpdateOperation <: Operation
    adapter::Any
    table::String
    ctid::Any          # e.g. "(0,1)"
    column::String
    new_value::Any
end

"""
Inserts a new row into `table`.
"""
struct DatabaseInsertOperation <: Operation
    adapter::Any
    table::String
    row::Dict{String,Any}
end

end # module
