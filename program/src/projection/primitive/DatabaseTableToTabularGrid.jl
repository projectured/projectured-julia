"""
    DatabaseTableToTabularGridModule

Projection: `DatabaseTable` → `TabularGrid`.

Lazily queries a database table via the adapter stored in the input document,
builds a header row (column names) and data rows in a `TabularGrid`, and
captures `ctid` values in the returned `DatabaseTableIoMap` so the reader
can map cell edits back to `DatabaseUpdateOperation` without re-querying.

Depends on:
- `DatabaseModule`         — adapter type, `db_update!`, `db_insert!`
- `DatabaseDocumentModule` — `DatabaseTable`, `DatabaseUpdateOperation`, `DatabaseInsertOperation`
- `TabularModule`          — `TabularGrid`, `TabularRow`, `TabularCell`
"""
module DatabaseTableToTabularGridModule

import DBInterface
import Tables
import ..DatabaseModule: OdbcDatabaseAdapter, db_update!, db_insert!
import ..DatabaseDocumentModule: DatabaseTable,
                                  DatabaseUpdateOperation, DatabaseInsertOperation
import ..TabularModule: TabularGrid, TabularRow, TabularCell
import ..CollectionModule: CellVector
import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          FieldReference, RangeReference, is_element_reference
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..OperationApiModule: evaluate_operation
import ..ReferenceBuilderModule: var"@reference"

export DatabaseTableIoMap, DatabaseTableToTabularGrid

# ── DatabaseTableIoMap ────────────────────────────────────────────────────────

"""
    DatabaseTableIoMap

Custom IoMap for `DatabaseTableToTabularGrid`. Carries `column_names` and
`ctid_values` captured at query time so the reader can map a grid cell edit
to a SQL UPDATE without re-querying.
"""
struct DatabaseTableIoMap <: IoMap
    projection::Any     # DatabaseTableToTabularGrid
    input::Any          # DatabaseTable
    output::Any         # TabularGrid
    column_names::Cell  # Vector{String} — reactive, recomputed on re-query
    ctid_values::Cell   # Vector{Any}    — one ctid per data row (rows 2..n)
end

# ── DatabaseTableToTabularGrid ────────────────────────────────────────────────

"""
    DatabaseTableToTabularGrid

Projection: `DatabaseTable` → `TabularGrid`.

The printer lazily executes `SELECT ctid, * FROM <table> [WHERE ...] [LIMIT ...]`
inside a reactive Cell thunk. The query fires on first render and automatically
re-executes when any field of the `DatabaseTable` document changes.

Row 1 of the produced `TabularGrid` is a header containing column names as
`TabularCell` values. Rows 2..n are data rows. `ctid` is fetched but not
displayed — it is stored in `DatabaseTableIoMap.ctid_values` for the reader.
"""
struct DatabaseTableToTabularGrid <: Projection end

# ── Private helpers ───────────────────────────────────────────────────────────

function _query_with_ctid(adapter, table, columns, where_clause, limit)
    col_part = columns === nothing ? "*" :
        join(["\"$(c)\"" for c in columns], ", ")
    sql = "SELECT ctid, $(col_part) FROM \"$(table)\""
    where_clause !== nothing && (sql *= " WHERE $(where_clause)")
    limit        !== nothing && (sql *= " LIMIT $(limit)")
    ct = Tables.columntable(DBInterface.execute(adapter._conn, sql))
    all_cols = String[String(n) for n in propertynames(ct)]
    ctid_idx = findfirst(==("ctid"), all_cols)
    col_names   = String[c for (i, c) in enumerate(all_cols) if i != ctid_idx]
    nrows       = isempty(all_cols) ? 0 : length(ct[1])
    ctid_values = Any[]
    data_rows   = Vector{Vector{Any}}()
    for r in 1:nrows
        push!(ctid_values, ct[ctid_idx][r])
        push!(data_rows, Any[ct[i][r] for i in 1:length(all_cols) if i != ctid_idx])
    end
    col_names, ctid_values, data_rows
end

function _make_header_row(col_names::Vector{String})
    TabularRow(CellVector(Cell[Cell(TabularCell(name)) for name in col_names]))
end

function _make_data_row(vals::Vector{Any})
    TabularRow(CellVector(Cell[Cell(TabularCell(v)) for v in vals]))
end

function _decode_grid_cell(path::ReferencePath)
    path isa ConcreteReferencePath || return nothing, nothing
    path.head isa FieldReference && path.head.name == "rows" || return nothing, nothing
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    h = path.head
    h isa RangeReference && is_element_reference(h) || return nothing, nothing
    r = h.start + 1
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    path.head isa FieldReference && path.head.name == "cells" || return nothing, nothing
    path = path.tail

    path isa ConcreteReferencePath || return nothing, nothing
    h = path.head
    h isa RangeReference && is_element_reference(h) || return nothing, nothing
    c = h.start + 1

    r, c
end

function _cell_string_value(grid::TabularGrid, r::Int, c::Int)
    row = grid.rows[r]
    row isa TabularRow || return nothing
    length(row.cells) < c && return nothing
    cell = row.cells[c]
    cell isa TabularCell || return nothing
    string(cell.content)
end

function _apply_range_replacement(current::String, step::RangeReference, replacement::String)
    s = max(0, step.start)
    e = min(length(current), step.stop)
    current[1:s] * replacement * current[e+1:end]
end

function _compute_new_value(grid::TabularGrid, r::Int, c::Int,
                             ref::ReferencePath, replacement::String)
    current = _cell_string_value(grid, r, c)
    current === nothing && return replacement
    range_step = nothing
    path = ref
    while path isa ConcreteReferencePath
        h = path.head
        if h isa RangeReference && !(path.tail isa ConcreteReferencePath)
            range_step = h
        end
        path = path.tail
    end
    range_step === nothing && return replacement
    _apply_range_replacement(current, range_step, replacement)
end

# ── projection_print ──────────────────────────────────────────────────────────

function projection_print(p::DatabaseTableToTabularGrid,
                           recursion,
                           doc::DatabaseTable, ctx)
    raw = Cell(() -> _query_with_ctid(doc.adapter, doc.table,
                                      doc.columns, doc.where_clause, doc.limit))
    col_names_cell   = Cell(() -> raw[][1])
    ctid_values_cell = Cell(() -> raw[][2])
    rows = CellVector(() -> begin
        col_names, _, data_rows = raw[]
        header = _make_header_row(col_names)
        data   = [_make_data_row(r) for r in data_rows]
        vcat([header], data)
    end)
    col_count = Cell(() -> length(col_names_cell[]))
    grid = TabularGrid(rows, col_count, Cell(nothing))
    DatabaseTableIoMap(p, doc, grid, col_names_cell, ctid_values_cell)
end

# ── Reference mapping ─────────────────────────────────────────────────────────

function map_reference_forward(::DatabaseTableToTabularGrid, iomap, reference)
    reference isa EmptyReferencePath ? EmptyReferencePath() : nothing
end

function map_reference_backward(p::DatabaseTableToTabularGrid, iomap, reference)
    reference isa EmptyReferencePath && return EmptyReferencePath()
    @reference proj(p, ^(reference))
end

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(p::DatabaseTableToTabularGrid,
                          iomap::DatabaseTableIoMap,
                          op)
    if op isa ReplaceSelectionOperation
        ref = map_reference_backward(p, iomap, op.path)
        ref === nothing && return nothing
        return ReplaceSelectionOperation(ref, op.from_click)
    end

    ref_path    = nothing
    replacement = ""
    if op isa StringReplaceRangeOperation
        ref_path    = op.reference
        replacement = op.replacement
    elseif op isa NumberReplaceRangeOperation
        ref_path    = op.reference
        replacement = op.replacement
    else
        return nothing
    end

    r, c = _decode_grid_cell(ref_path)
    r === nothing && return nothing
    r == 1        && return nothing  # header row: read-only

    ctids = iomap.ctid_values[]
    (r - 1) > length(ctids) && return nothing
    ctid = ctids[r - 1]

    col_names = iomap.column_names[]
    c > length(col_names) && return nothing
    column = col_names[c]

    new_value = _compute_new_value(iomap.output, r, c, ref_path, replacement)
    DatabaseUpdateOperation(iomap.input.adapter, iomap.input.table,
                            ctid, column, new_value)
end

# ── Operation evaluators ──────────────────────────────────────────────────────

function evaluate_operation(editor, op::DatabaseUpdateOperation)
    where_clause = "ctid = '$(op.ctid)'::tid"
    db_update!(op.adapter, op.table,
               Dict{String,Any}(op.column => op.new_value),
               where_clause)
    nothing
end

function evaluate_operation(editor, op::DatabaseInsertOperation)
    db_insert!(op.adapter, op.table, op.row)
    nothing
end

end # module
