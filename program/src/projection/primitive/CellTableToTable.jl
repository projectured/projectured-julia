"""
    CellTableToTableModule

Projection: `CellTable` → `TableTable`.

Wraps a generic reactive `CellTable` (row 1 = column names, rows 2..n = data) in
a `TableTable` so it can be rendered through the existing `TableToGraphics`
pipeline. Column headers come from row 1 of the `CellTable`; the data rows
become the table cells (row-major). Each value is wrapped in a JSON document
(`JsonString` / `JsonNumber` / `JsonBool` / `JsonNull`) so the table's content
recursion (e.g. `JsonToSyntax → SyntaxToText → TextToGraphics`) renders it.

Read-only: no reference mapping or read support.
"""
module CellTableToTableModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector, CellTable
import ..TableModule: TableTable, TableRow, TableColumn, TableCell
import ..JsonModule: JsonString, JsonNumber, JsonBool, JsonNull
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap

export CellTableToTable

# Wrap a raw cell value in a JSON document so the table content recursion renders it.
_to_doc(v::AbstractString) = JsonString(String(v))
_to_doc(v::Bool)           = JsonBool(v)
_to_doc(v::Real)           = JsonNumber(v)
_to_doc(::Nothing)         = JsonNull()
_to_doc(::Missing)         = JsonNull()
_to_doc(v)                 = JsonString(string(v))

struct CellTableToTable <: Projection end

function projection_print(p::CellTableToTable, recursion, ct::CellTable, ctx)
    # Column headers = the first row of the CellTable (column names).
    columns = CellVector(() -> begin
        nr, nc = size(ct)
        nr == 0 ? TableColumn[] :
            TableColumn[TableColumn(_to_doc(ct[1, c])) for c in 1:nc]
    end)

    # One TableRow header per data row (rows 2..n of the CellTable).
    rows = CellVector(() -> begin
        nr, _ = size(ct)
        ndata = max(0, nr - 1)
        TableRow[TableRow(_to_doc(string(i))) for i in 1:ndata]
    end)

    # Data cells, row-major over rows 2..n.
    cells = CellVector(() -> begin
        nr, nc = size(ct)
        out = TableCell[]
        for r in 2:nr, c in 1:nc
            push!(out, TableCell(_to_doc(ct[r, c])))
        end
        out
    end)

    SimpleIoMap(p, ct, TableTable(rows, columns, cells, Cell(nothing)))
end

map_reference_forward(::CellTableToTable, iomap, ref) = nothing
map_reference_backward(::CellTableToTable, iomap, ref) = nothing
projection_read(::CellTableToTable, iomap, op) = nothing

end # module
