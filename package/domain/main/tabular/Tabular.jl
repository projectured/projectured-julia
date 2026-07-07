"""
    TabularModule

Row-primary 2D document layer. Rows own their cells; column views are derived
by collecting one raw `Cell` from each row (so mutations propagate both ways).
No headers — higher-level models add them.
"""
module TabularModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, get_cell_at
import ..ReferenceModule: Reference
export TabularDocument, tabular_cell, tabular_column, insert_row!, delete_row!, insert_column!,
       delete_column!

# ── Abstract base ────────────────────────────────────────────────────────────

abstract type TabularDocument <: Document end

"""
A single data slot; `content` is any `Document` (including a nested `TabularGrid`).
"""
@document struct TabularCell <: TabularDocument
    content::Document
    selection::Reference = nothing
end

"""
One row; owns its cells as a `CellVector` so per-row insert/delete/reorder
touch only that row's cell data.
"""
@document struct TabularRow <: TabularDocument
    cells::CellVector = CellVector()
    selection::Reference = nothing
end

# ── TabularGrid ──────────────────────────────────────────────────────────────

"""
A 2D grid: rows own their cells (primary axis); column views share `Cell`s
across rows so mutations propagate both directions. `col_count` bounds a
row's width.
"""
@document struct TabularGrid <: TabularDocument
    rows::CellVector = CellVector()
    col_count::Int = 0
    selection::Reference = nothing
end

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
    shared = [get_cell_at(g.rows[r].cells, c) for r in 1:nrows]
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
