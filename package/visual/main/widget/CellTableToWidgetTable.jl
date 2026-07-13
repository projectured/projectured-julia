"""
    CellTableToWidgetTableModule

Projection: `CellTable` → `WidgetTable`.

Wraps a generic reactive `CellTable` (row 1 = column names, rows 2..n = data) in a
`WidgetTable` so it can be rendered through the `WidgetToGraphics` table renderer
(which delegates positioning to `GridLayout` and overlays decorations). Column
headers come from row 1 of the `CellTable`; the data rows become the table body
(row-major). Each value is wrapped in a base `Primitive` document
(`PrimitiveString` / `PrimitiveNumber` / `PrimitiveBool`) so the table's content
recursion (e.g. `Primitive*ToSyntaxLeaf → SyntaxToText → TextToGraphics`) renders
it — this keeps the projection domain-free (no Json), so it lives in `visual`
rather than a domain slice.

Read-only: no reference mapping or read support.
"""
module CellTableToWidgetTableModule

import ..CellModule: Cell
import ..CollectionModule: CellVector, CellTable
import ..WidgetModule: WidgetTable, Point2D
import ..PrimitiveModule: PrimitiveBool, PrimitiveNumber, PrimitiveString
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap

export CellTableToWidgetTable

# Wrap a raw cell value in a base Primitive document so the table content
# recursion renders it. `Bool` is matched before `Real` (Bool <: Real) so
# booleans stay booleans; there is no `PrimitiveNull`, so null/missing render as
# an empty string.
_to_doc(v::AbstractString) = PrimitiveString(String(v))
_to_doc(v::Bool)           = PrimitiveBool(v)
_to_doc(v::Real)           = PrimitiveNumber(v)
_to_doc(::Nothing)         = PrimitiveString("")
_to_doc(::Missing)         = PrimitiveString("")
_to_doc(v)                 = PrimitiveString(string(v))

struct CellTableToWidgetTable <: Projection end

function print_document(p::CellTableToWidgetTable, recursion, ct::CellTable, ctx)
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
    # Data rows, Primitive-wrapped, each a CellVector of document cells.
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
                        Cell(true), Cell(nothing))   # visible, hovered (selection defaults)
    SimpleIoMap(p, ct, table)
end

map_reference_forward(::CellTableToWidgetTable, iomap, ref) = nothing
map_reference_backward(::CellTableToWidgetTable, iomap, ref) = nothing
read_intent(::CellTableToWidgetTable, iomap, op) = nothing

end # module
