"""
    CellTableToWidgetTableModule

Projection: `CellTable` → `WidgetTable`.

Wraps a generic reactive `CellTable` (row 1 = column names, rows 2..n = data) in a
`WidgetTable` so it can be rendered through the `WidgetToGraphics` table renderer
(which delegates positioning to `GridLayout` and overlays decorations). Column
headers come from row 1 of the `CellTable`; the data rows become the table body
(row-major). Each value is wrapped in a JSON document (`JsonString` /
`JsonNumber` / `JsonBool` / `JsonNull`) so the table's content recursion (e.g.
`JsonToSyntax → SyntaxToText → TextToGraphics`) renders it.

Read-only: no reference mapping or read support.
"""
module CellTableToTableModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector, CellTable
import ..WidgetModule: WidgetTable, Point2D
import ..JsonModule: JsonString, JsonNumber, JsonBool, JsonNull
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap

export CellTableToWidgetTable, CellTableToTable

# Wrap a raw cell value in a JSON document so the table content recursion renders it.
_to_doc(v::AbstractString) = JsonString(String(v))
_to_doc(v::Bool)           = JsonBool(v)
_to_doc(v::Real)           = JsonNumber(v)
_to_doc(::Nothing)         = JsonNull()
_to_doc(::Missing)         = JsonNull()
_to_doc(v)                 = JsonString(string(v))

struct CellTableToWidgetTable <: Projection end

# Backwards-compatible alias (the projection was renamed from CellTableToTable).
const CellTableToTable = CellTableToWidgetTable

function projection_print(p::CellTableToWidgetTable, recursion, ct::CellTable, ctx)
    nr, nc = size(ct)
    # The lazy `CellVector(f)` constructor wraps each item `f()` returns in its
    # own slot Cell, so the thunks return *raw* values (Documents / inner
    # CellVectors), never pre-wrapped Cells — pre-wrapping would double-wrap and
    # make `rows[r]` a `Cell` instead of the row `CellVector`.
    # Column headers = the first row of the CellTable (column names).
    column_headers = CellVector(() -> begin
        nr2, nc2 = size(ct)
        nr2 == 0 ? Any[] : Any[_to_doc(ct[1, c]) for c in 1:nc2]
    end)
    # Data rows, JSON-wrapped, each a CellVector of document cells.
    rows = CellVector(() -> begin
        nr2, nc2 = size(ct)
        out = Any[]
        for r in 2:nr2
            push!(out, CellVector(Cell[Cell(_to_doc(ct[r, c])) for c in 1:nc2]))
        end
        out
    end)
    table = WidgetTable(Cell(Point2D(0, 0)),
                        column_headers,
                        CellVector(),        # no row headers
                        rows,
                        Cell(nc),
                        Cell(8), Cell(1),    # padding, border_width
                        Cell(true), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, ct, table)
end

map_reference_forward(::CellTableToWidgetTable, iomap, ref) = nothing
map_reference_backward(::CellTableToWidgetTable, iomap, ref) = nothing
projection_read(::CellTableToWidgetTable, iomap, op) = nothing

end # module
