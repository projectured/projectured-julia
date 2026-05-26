"""
    TableModule

The table document domain provides reactive representations of tabular data structures.
Every table element is a Document with all mutable fields wrapped in reactive Cells,
enabling automatic dependency tracking and incremental updates.

The domain includes:
- **TableCell**: a single cell with content
- **TableRow**: a row in the table
- **TableColumn**: a column in the table
- **TableTable**: the table itself with rows, columns, and cells
"""
module TableModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export TableDocument, TableCell, TableRow, TableColumn, TableTable,
       ITableCell, ITableRow, ITableColumn, ITableTable

"""
    TableDocument

Abstract base type for all table document types. Every concrete table type
subtypes `TableDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type TableDocument <: Document end

# ── Cell ────────────────────────────────────────────────────────────────

"""
    TableCell

Represents a single cell in a table.

# Fields

- `content::Cell` — holds the cell content (any `Document` type)
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct TableCell <: TableDocument
    content::Document
    selection::Reference
end

TableCell() = TableCell(Cell(nothing), Cell(nothing))
TableCell(content::Document) = TableCell(Cell(content), Cell(nothing))

# ── Row ─────────────────────────────────────────────────────────────────

"""
    TableRow

Represents a row in a table.

# Fields

- `content::Document` — optional row header (e.g. "1", "2", "3")
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct TableRow <: TableDocument
    content::Document
    selection::Reference
end

TableRow() = TableRow(Cell(nothing), Cell(nothing))
TableRow(content::Document) = TableRow(Cell(content), Cell(nothing))

# ── Column ──────────────────────────────────────────────────────────────

"""
    TableColumn

Represents a column in a table.

# Fields

- `content::Document` — optional column header (e.g. "A", "B", "C")
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct TableColumn <: TableDocument
    content::Document
    selection::Reference
end

TableColumn() = TableColumn(Cell(nothing), Cell(nothing))
TableColumn(content::Document) = TableColumn(Cell(content), Cell(nothing))

# ── Table ───────────────────────────────────────────────────────────────

"""
    TableTable

Represents a table with rows, columns, and cells.

# Fields

- `rows::CellVector` — holds the table rows
- `columns::CellVector` — holds the table columns
- `cells::CellVector` — holds the table cells
- `padding::Int` — inner padding (pixels) between cell border and content
- `selection::Reference` — holds the ReferencePath for cursor position

# Constructors

- `TableTable()` — empty table
"""
@document struct TableTable <: TableDocument
    rows::CellVector
    columns::CellVector
    cells::CellVector
    padding::Int
    selection::Reference
end

TableTable() = TableTable(CellVector(), CellVector(), CellVector(), Cell(2), Cell(nothing))
TableTable(rows, columns, cells, selection) = TableTable(rows, columns, cells, Cell(2), selection)
TableTable(rows::CellVector, columns::CellVector, cells::CellVector; padding=2) = TableTable(rows, columns, cells, Cell(padding), Cell(nothing))

end # module
