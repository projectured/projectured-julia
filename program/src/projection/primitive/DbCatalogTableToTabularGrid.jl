"""
    DbCatalogTableToTabularGridModule

Projection: `DbCatalogTable` → `TabularGrid`.

Lazily queries the table identified by the input document using a
schema-qualified `SELECT ctid, * FROM "schema"."table"`. The adapter is
resolved by walking up the parent chain: `doc.schema.database.connection.adapter`.
`ctid` values are captured in `DbCatalogTableIoMap` so the reader can map
cell edits back to `DbCatalogUpdateOperation` without re-querying.

Also defines `DbCatalogUpdateOperation` and its evaluator — the schema-aware
counterpart of `DatabaseUpdateOperation`.
"""
module DbCatalogTableToTabularGridModule

import LibPQ
import ..DbCatalogDocumentModule: DbCatalogTable
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
import ..OperationApiModule: evaluate_operation, Operation
import ..ReferenceBuilderModule: var"@reference"

export DbCatalogTableIoMap, DbCatalogTableToTabularGrid, DbCatalogUpdateOperation

# ── DbCatalogUpdateOperation ──────────────────────────────────────────────────

"""
    DbCatalogUpdateOperation(adapter, schema, table, ctid, column, new_value)

Updates a single cell identified by `ctid` in `"schema"."table"`. Produced by
`DbCatalogTableToTabularGrid.projection_read` when a data-row cell is edited.
"""
struct DbCatalogUpdateOperation <: Operation
    adapter::Any
    schema::String
    table::String
    ctid::Any
    column::String
    new_value::Any
end

# ── DbCatalogTableIoMap ───────────────────────────────────────────────────────

"""
    DbCatalogTableIoMap

Custom IoMap for `DbCatalogTableToTabularGrid`. Carries `column_names` and
`ctid_values` captured at query time so the reader can map a grid cell edit
to a SQL UPDATE without re-querying.
"""
struct DbCatalogTableIoMap <: IoMap
    projection::Any     # DbCatalogTableToTabularGrid
    input::Any          # DbCatalogTable
    output::Any         # TabularGrid
    column_names::Cell  # Vector{String} — reactive, recomputed on re-query
    ctid_values::Cell   # Vector{Any}    — one ctid per data row (rows 2..n)
end

# ── DbCatalogTableToTabularGrid ───────────────────────────────────────────────

"""
    DbCatalogTableToTabularGrid

Projection: `DbCatalogTable` → `TabularGrid`.

The printer lazily executes `SELECT ctid, * FROM "schema"."table"` inside a
reactive Cell thunk. Schema and table name are read from the input document;
the adapter is resolved by walking up the parent chain. The query re-fires
automatically when any dependent cell changes.

Row 1 of the produced `TabularGrid` is a header containing column names as
`TabularCell` values. Rows 2..n are data rows. `ctid` is fetched but not
displayed — it is stored in `DbCatalogTableIoMap.ctid_values` for the reader.
"""
struct DbCatalogTableToTabularGrid <: Projection end

# ── Private helpers ───────────────────────────────────────────────────────────

function _query_with_ctid(adapter, schema, table)
    sql = "SELECT ctid, * FROM \"$(schema)\".\"$(table)\""
    result   = LibPQ.execute(adapter._conn, sql)
    all_cols = String[String(n) for n in LibPQ.column_names(result)]
    ctid_idx = findfirst(==("ctid"), all_cols)
    col_names   = String[c for (i, c) in enumerate(all_cols) if i != ctid_idx]
    ctid_values = Any[]
    data_rows   = Vector{Vector{Any}}()
    for row in result
        push!(ctid_values, row[ctid_idx])
        push!(data_rows, Any[row[i] for i in 1:length(all_cols) if i != ctid_idx])
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

function projection_print(p::DbCatalogTableToTabularGrid,
                           doc::DbCatalogTable,
                           recursion, ctx)
    adapter     = doc.schema.database.connection.adapter
    schema_name = doc.schema.name
    table_name  = doc.name
    raw = Cell(() -> _query_with_ctid(adapter, schema_name, table_name))
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
    DbCatalogTableIoMap(p, doc, grid, col_names_cell, ctid_values_cell)
end

# ── Reference mapping ─────────────────────────────────────────────────────────

function map_reference_forward(::DbCatalogTableToTabularGrid, iomap, reference)
    reference isa EmptyReferencePath ? EmptyReferencePath() : nothing
end

function map_reference_backward(p::DbCatalogTableToTabularGrid, iomap, reference)
    reference isa EmptyReferencePath && return EmptyReferencePath()
    @reference proj(p, ^(reference))
end

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(p::DbCatalogTableToTabularGrid,
                          iomap::DbCatalogTableIoMap,
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
    DbCatalogUpdateOperation(iomap.input.schema.database.connection.adapter,
                             iomap.input.schema.name,
                             iomap.input.name,
                             ctid, column, new_value)
end

# ── Operation evaluator ───────────────────────────────────────────────────────

function evaluate_operation(editor, op::DbCatalogUpdateOperation)
    sql = "UPDATE \"$(op.schema)\".\"$(op.table)\" " *
          "SET \"$(op.column)\" = \$1 " *
          "WHERE ctid = '$(op.ctid)'::tid"
    LibPQ.execute(op.adapter._conn, sql, Any[op.new_value])
    nothing
end

end # module
