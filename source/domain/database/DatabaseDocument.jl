# ── The database documents ────────────────────────────────────────────────────
#
# A table and the two edits a cell and a row accept.

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
