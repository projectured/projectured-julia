"""
    TabularModule

Row-primary 2D document layer. Rows own their cells; columns are derived
views sharing the same reactive Cell objects. No headers — those belong
to higher-level domain models built on top of this foundation.

The domain includes:
- **TabularCell**: a single data slot holding any Document
- **TabularRow**: one row; owns its cells as a CellVector
- **TabularGrid**: the 2D grid; owns its rows as a CellVector plus a col_count
"""
module TabularModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector, cell_at
import ..ReferenceModule: Reference
export TabularDocument, TabularCell, TabularRow, TabularGrid,
       ITabularCell, ITabularRow, ITabularGrid,
       tabular_cell, tabular_column,
       insert_row!, delete_row!, insert_column!, delete_column!

# ── Abstract base ────────────────────────────────────────────────────────────

"""
    TabularDocument

Abstract base type for all tabular document types. Every concrete tabular
type subtypes `TabularDocument` and carries a `selection::Reference` field
as required by the `Document` contract.
"""
abstract type TabularDocument <: Document end

# ── TabularCell ──────────────────────────────────────────────────────────────

"""
    TabularCell

A single data slot in a tabular structure.

# Fields

- `content::Document` — the cell value; any `Document` type is accepted,
  including a nested `TabularGrid` (nesting is implicit via the type system).
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell).
"""
@document struct TabularCell <: TabularDocument
    content::Document
    selection::Reference
end

TabularCell() = TabularCell(Cell(nothing), Cell(nothing))
TabularCell(content) = TabularCell(Cell(content), Cell(nothing))

# ── TabularRow ───────────────────────────────────────────────────────────────

"""
    TabularRow

One row in a tabular grid. The row owns its cells as a reactive CellVector,
making row-level insert, delete, reorder, and lazy population cheap: only
the grid's outer CellVector changes, not the cell data of other rows.

# Fields

- `cells::CellVector` — the cells in this row; elements are `TabularCell`.
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell).
"""
@document struct TabularRow <: TabularDocument
    cells::CellVector
    selection::Reference
end

TabularRow() = TabularRow(CellVector(), Cell(nothing))
TabularRow(cells::CellVector) = TabularRow(cells, Cell(nothing))

# ── TabularGrid ──────────────────────────────────────────────────────────────

"""
    TabularGrid

A 2D grid of cells. Rows are the primary axis — each `TabularRow` owns its
cells. Column views are derived on demand by collecting one raw `Cell` from
each row; the shared `Cell` objects mean mutations propagate in both
directions without copying.

# Fields

- `rows::CellVector` — the rows of the grid; elements are `TabularRow`.
- `col_count::Int` — expected number of cells per row (cross-dimension size).
  Used for validation; avoids storing redundant column objects.
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell).

# Constructors

- `TabularGrid()` — empty grid (0 rows, col_count 0)
- `TabularGrid(rows, col_count)` — grid with given rows and column count
"""
@document struct TabularGrid <: TabularDocument
    rows::CellVector
    col_count::Int
    selection::Reference
end

TabularGrid() = TabularGrid(CellVector(), Cell(0), Cell(nothing))
TabularGrid(rows::CellVector, col_count::Integer) =
    TabularGrid(rows, Cell(col_count), Cell(nothing))

# ── TAB-delimited show ────────────────────────────────────────────────────────
# A spreadsheet-style rendering (overrides the generic `Document` show): a cell
# shows its content (a nested grid as a `<TabularGrid>` placeholder), a row
# TAB-joins its cells, and a grid newline-joins its rows.
function Base.show(io::IO, c::TabularCell)
    content = c.content
    content isa TabularGrid ? print(io, "<TabularGrid>") : show(io, content)
end
Base.show(io::IO, r::TabularRow) =
    join(io, (sprint(show, cell) for cell in r.cells), "\t")
Base.show(io::IO, g::TabularGrid) =
    join(io, (sprint(show, row) for row in g.rows), "\n")

# ── Accessors ───────────────────────────────────────────────────────────────

"""
    tabular_cell(g, r, c)

Return the content of the cell at row `r`, column `c` in `g`.
"""
tabular_cell(g::TabularGrid, r::Int, c::Int) = g.rows[r].cells[c]

"""
    tabular_column(g, c)

Derive a column view as a `CellVector` by collecting the raw `Cell` at
position `c` from each row. The returned vector shares the same `Cell`
objects as the rows — mutations via the column view or via `tabular_cell`
hit the same reactive `Cell` in the graph.
"""
function tabular_column(g::TabularGrid, c::Int)
    nrows = length(g.rows)
    shared = [cell_at(g.rows[r].cells, c) for r in 1:nrows]
    CellVector(shared)
end

# ── Mutation utilities ───────────────────────────────────────────────────────

"""
    insert_row!(g, r, row)

Insert `row` at position `r` in `g`. Only the outer `rows` CellVector
changes; cell data in other rows is unaffected.
"""
insert_row!(g::TabularGrid, r::Int, row::TabularRow) = insert!(g.rows, r, Cell(row))

"""
    delete_row!(g, r)

Delete the row at position `r` from `g`.
"""
delete_row!(g::TabularGrid, r::Int) = deleteat!(g.rows, r)

"""
    insert_column!(g, c, cells)

Insert one `TabularCell` per row at column position `c`. `cells` must have
the same length as `g.rows`. Increments `g.col_count` by 1.
"""
function insert_column!(g::TabularGrid, c::Int, cells::Vector)
    length(cells) == length(g.rows) || error("cell count must equal row count")
    for r in 1:length(g.rows)
        insert!(g.rows[r].cells, c, Cell(cells[r]))
    end
    g.col_count = g.col_count + 1
end

"""
    delete_column!(g, c)

Delete column `c` from every row in `g`. Decrements `g.col_count` by 1.
"""
function delete_column!(g::TabularGrid, c::Int)
    for r in 1:length(g.rows)
        deleteat!(g.rows[r].cells, c)
    end
    g.col_count = g.col_count - 1
end

end # module
