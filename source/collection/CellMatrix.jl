# ── CellMatrix ────────────────────────────────────────────────────────────
# Structural mutations (insert/delete row/column) reallocate the underlying
# Matrix{Cell}, but Cell references remain stable.

"""
    CellMatrix(rows, columns)

A rectangle of values, each in a cell of its own.

Use it for a grid whose shape is fixed and whose slots are read and written one
at a time: a spreadsheet, a board, a bitmap of values. A write to one slot tells
only what read that slot. Rows and columns can be inserted and deleted, and a
cell a caller kept stays the same cell.

# Example

    grid = CellMatrix(3, 3)
    grid[2, 2] = "x"
    insert_row!(grid, 1, Cell[Cell(nothing) for _ in 1:3])

See also `CellTable`, whose rows are vectors and which grows a row at a time,
and `CellVector`.
"""
@document struct CellMatrix
    elements::Matrix{Cell} = Matrix{Cell}(undef, 0, 0)
end

# `CellMatrix()` is the macro's keyword constructor (empty elements, no selection).

CellMatrix(cells::Matrix{Cell}) =
    CellMatrix(Cell(copy(cells)), Cell(nothing))

CellMatrix(nrows::Integer, ncols::Integer) =
    CellMatrix(Cell([Cell(nothing) for _ in 1:nrows, _ in 1:ncols]), Cell(nothing))

CellMatrix(items::AbstractMatrix) =
    CellMatrix(Cell([Cell(items[r, c]) for r in 1:size(items, 1), c in 1:size(items, 2)]), Cell(nothing))

function CellMatrix(f::Function)
    cm = CellMatrix(Cell(Matrix{Cell}(undef, 0, 0)), Cell(nothing))
    set_cell_function!(getfield(cm, :elements), () -> [Cell(x) for x in f()])
    cm
end

_elems(cm::CellMatrix) = cm.elements::Matrix{Cell}

Base.size(cm::CellMatrix)                        = size(_elems(cm))
Base.size(cm::CellMatrix, d::Integer)            = size(_elems(cm), d)
Base.length(cm::CellMatrix)                      = length(_elems(cm))
Base.isempty(cm::CellMatrix)                     = isempty(_elems(cm))
Base.eachindex(cm::CellMatrix)                   = CartesianIndices(_elems(cm))

function Base.iterate(cm::CellMatrix, s...)
    r = iterate(_elems(cm), s...)
    r === nothing && return nothing
    (cell, state) = r
    (cell[], state)
end

Base.getindex(cm::CellMatrix, r::Integer, c::Integer) = _elems(cm)[r, c][]
get_cell_at(cm::CellMatrix, r::Integer, c::Integer)       = _elems(cm)[r, c]

function Base.setindex!(cm::CellMatrix, val, r::Integer, c::Integer)
    _elems(cm)[r, c][] = val
    return val
end

function Base.setindex!(cm::CellMatrix, cell::Cell, r::Integer, c::Integer)
    elems = _elems(cm)
    elems[r, c] = cell
    cm.elements = elems
    return cell
end

"""
    insert_row!(collection, index, row)

Put a row into a grid, at a place.

Use it to add a record to a table, a line to a board, a row to a sheet. The rows
below move down, and every cell that was there stays the cell it was.

# Example

    insert_row!(table, 1, ["name", "value"])

See also `delete_row!`, `insert_column!`, `CellTable` and `CellMatrix`.
"""
function insert_row!(cm::CellMatrix, r::Integer, cells::Vector{Cell})
    elems = _elems(cm)
    nrows, ncols = size(elems)
    length(cells) == ncols || throw(DimensionMismatch("expected $ncols cells, got $(length(cells))"))
    new_elems = Matrix{Cell}(undef, nrows + 1, ncols)
    new_elems[1:r-1, :]   = @view elems[1:r-1, :]
    new_elems[r, :]        = cells
    new_elems[r+1:end, :]  = @view elems[r:end, :]
    cm.elements = new_elems
    return cm
end

"""
    insert_column!(matrix, index, column)

Put a column into a grid, at a place.

Use it to add a field to every record at once. The columns to the right move
over, and every cell that was there stays the cell it was.

# Example

    insert_column!(grid, 2, [Cell("") for _ in 1:3])

See also `delete_column!`, `insert_row!` and `CellMatrix`.
"""
function insert_column!(cm::CellMatrix, c::Integer, cells::Vector{Cell})
    elems = _elems(cm)
    nrows, ncols = size(elems)
    length(cells) == nrows || throw(DimensionMismatch("expected $nrows cells, got $(length(cells))"))
    new_elems = Matrix{Cell}(undef, nrows, ncols + 1)
    new_elems[:, 1:c-1]   = @view elems[:, 1:c-1]
    new_elems[:, c]        = cells
    new_elems[:, c+1:end]  = @view elems[:, c:end]
    cm.elements = new_elems
    return cm
end

"""
    delete_row!(collection, index)

Take a row out of a grid.

Use it to drop a record from a table. The rows below move up.

# Example

    delete_row!(table, 3)

See also `insert_row!` and `delete_column!`.
"""
function delete_row!(cm::CellMatrix, r::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows - 1, ncols)
    new_elems[1:r-1, :]  = @view elems[1:r-1, :]
    new_elems[r:end, :]   = @view elems[r+1:end, :]
    cm.elements = new_elems
    return cm
end

"""
    delete_column!(matrix, index)

Take a column out of a grid.

Use it to drop a field from every record at once. The columns to the right move
over.

# Example

    delete_column!(grid, 2)

See also `insert_column!` and `delete_row!`.
"""
function delete_column!(cm::CellMatrix, c::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows, ncols - 1)
    new_elems[:, 1:c-1]  = @view elems[:, 1:c-1]
    new_elems[:, c:end]   = @view elems[:, c+1:end]
    cm.elements = new_elems
    return cm
end
