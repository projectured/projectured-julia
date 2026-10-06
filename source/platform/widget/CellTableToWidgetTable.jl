# Fragment of `WidgetModule`.
#
# Projection: `CellTable` → `WidgetTable`.
#
# Wraps a generic reactive `CellTable` (row 1 = column names, rows 2..n = data) in a
# `WidgetTable` so it can be rendered through the `WidgetToGraphics` table renderer
# (which delegates positioning to `GridLayout` and overlays decorations). Column
# headers come from row 1 of the `CellTable`; the data rows become the table body
# (row-major). Each value is wrapped in a base `Primitive` document
# (`PrimitiveString` / `PrimitiveNumber` / `PrimitiveBool`) so the table's content
# recursion (e.g. `Primitive*ToSyntaxLeaf → SyntaxToText → TextToGraphics`) renders
# it — this keeps the projection domain-free (no Json), so it lives in `visual`
# rather than a domain slice.
#
# Read-only: no reference mapping or read support.
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
    column_headers = CellVector(@computation begin
        nr2, nc2 = size(ct)
        nr2 == 0 ? Any[] : Any[_to_doc(ct[1, c]) for c in 1:nc2]
    end)
    # Data rows, Primitive-wrapped, each a CellVector of document cells.
    rows = CellVector(@computation begin
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
                        Cell(nothing),       # no corner
                        rows, Cell(@computation WidgetTableRows(length(rows))),
                        Cell(WidgetTableColumns(nc)),   # no data of the columns
                        Cell(1),             # border_width
                        Cell(Content), Cell(Content),      # every column and row is its content
                        Cell(:clip),                       # a cell is one line, cut at the edge
                        Cell(true),          # visible
                        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), # margin, border, padding, style
                        Cell(Point2D(0, 0)), # scroll_position
                        Cell(1),             # top_row
                        Cell(nothing),       # no drag of the edge of a column
                        Cell(nothing),       # no owner opens a cell
                        Cell(nothing))               # no tooltip (selection defaults)
    SimpleIoMap(p, ct, table)
end

# No caret goes into the table. The default backward mapping names a part of the
# widget table by an introduced reference, so a point names the cell under it, and
# only such a reference maps forward again.
map_reference_forward(p::CellTableToWidgetTable, iomap, reference) = find_introduced_path(p, reference)
read_intent(::CellTableToWidgetTable, iomap, op) = nothing
