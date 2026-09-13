# ── CellMatrix ────────────────────────────────────────────────────────────
# A dense rectangular matrix where each slot is a reactive Cell.
# Structural mutations (insert/delete row/column) reallocate the underlying
# Matrix{Cell}, but Cell references remain stable.

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

function delete_row!(cm::CellMatrix, r::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows - 1, ncols)
    new_elems[1:r-1, :]  = @view elems[1:r-1, :]
    new_elems[r:end, :]   = @view elems[r+1:end, :]
    cm.elements = new_elems
    return cm
end

function delete_column!(cm::CellMatrix, c::Integer)
    elems = _elems(cm)
    nrows, ncols = size(elems)
    new_elems = Matrix{Cell}(undef, nrows, ncols - 1)
    new_elems[:, 1:c-1]  = @view elems[:, 1:c-1]
    new_elems[:, c:end]   = @view elems[:, c+1:end]
    cm.elements = new_elems
    return cm
end
