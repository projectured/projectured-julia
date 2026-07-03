"""
    DatabaseDocumentModule

Document layer for database access. `DatabaseTable` holds only the query
metadata needed to drive the projection — adapter reference, table name,
and optional filter parameters. No query results are cached here.

Also defines the mutation operations produced by the projection reader:
`DatabaseUpdateOperation` and `DatabaseInsertOperation`. Their evaluators
live in the bridge module (`DatabaseTabular.jl`) to keep the document layer
free of any backend dependency.
"""
module DatabaseDocumentModule

import ..ReactiveModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..OperationApiModule: Operation

export DatabaseDocument, DatabaseTable, IDatabaseTable,
       DatabaseUpdateOperation, DatabaseInsertOperation

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type DatabaseDocument <: Document end

# ── DatabaseTable ─────────────────────────────────────────────────────────────

"""
    DatabaseTable

Document representing a database table query specification. Holds only the
metadata needed to drive the projection — never the query result.

# Fields

- `adapter::Any`       — `DatabaseAdapter` reference (stable connection handle)
- `table::String`      — table name
- `columns::Any`       — `Vector{String}` of column names to fetch, or `nothing` (all)
- `where_clause::Any`  — raw SQL WHERE fragment, or `nothing`
- `limit::Any`         — maximum row count (`Int`), or `nothing`
- `selection::Reference`
"""
@document struct DatabaseTable <: DatabaseDocument
    adapter::Any
    table::String
    columns::Any
    where_clause::Any
    limit::Any
    selection::Reference
end

DatabaseTable(adapter, table;
              columns=nothing,
              where_clause=nothing,
              limit=nothing) =
    DatabaseTable(Cell(adapter), Cell(table), Cell(columns),
                  Cell(where_clause), Cell(limit), Cell(nothing))

# ── Operations ────────────────────────────────────────────────────────────────

"""
    DatabaseUpdateOperation(adapter, table, ctid, column, new_value)

Updates a single cell identified by `ctid` in `table`. Produced by
`DatabaseTableToTabularGrid.projection_read` when a data-row cell is edited.
Evaluated by `evaluate_operation` in `DatabaseTabularModule`.
"""
struct DatabaseUpdateOperation <: Operation
    adapter::Any       # DatabaseAdapter
    table::String
    ctid::Any          # ctid string captured at query time, e.g. "(0,1)"
    column::String     # column name to update
    new_value::Any
end

"""
    DatabaseInsertOperation(adapter, table, row)

Inserts a new row into `table`. Produced by the projection reader when the
user edits the blank insertion row appended below the last data row.
Evaluated by `evaluate_operation` in `DatabaseTabularModule`.
"""
struct DatabaseInsertOperation <: Operation
    adapter::Any
    table::String
    row::Dict{String,Any}
end

end # module
