# ── CellTable ─────────────────────────────────────────────────────────────
# A table stored as a CellVector of CellVector rows. Row insert/delete is
# O(nrows) — the same cost as CellVector.insert! — without copying every
# cell in the matrix. Column access requires iterating rows.

@document struct CellTable
    rows::CellVector = CellVector()
end

# `CellTable()` is the macro's keyword constructor (empty rows, no selection).

CellTable(nrows::Integer, ncols::Integer) =
    CellTable(Cell(CellVector(Cell[Cell(CellVector(undef, ncols)) for _ in 1:nrows])), Cell(nothing))

function CellTable(items::AbstractMatrix)
    nr, nc = size(items)
    rows = CellVector(Cell[Cell(CellVector([items[r, c] for c in 1:nc])) for r in 1:nr])
    CellTable(Cell(rows), Cell(nothing))
end

Base.size(ct::CellTable) = (length(ct.rows), isempty(ct.rows) ? 0 : length(ct.rows[1]::CellVector))
Base.size(ct::CellTable, d::Integer) = size(ct)[d]
Base.length(ct::CellTable) = length(ct.rows)
Base.isempty(ct::CellTable) = isempty(ct.rows)

Base.getindex(ct::CellTable, r::Integer, c::Integer) = (ct.rows[r]::CellVector)[c]
get_cell_at(ct::CellTable, r::Integer, c::Integer) = get_cell_at(ct.rows[r]::CellVector, c)

function Base.setindex!(ct::CellTable, val, r::Integer, c::Integer)
    (ct.rows[r]::CellVector)[c] = val
    return val
end

function insert_row!(ct::CellTable, r::Integer, row::CellVector)
    insert!(ct.rows, r, Cell(row))
    return ct
end

function insert_row!(ct::CellTable, r::Integer, items::AbstractVector)
    insert!(ct.rows, r, Cell(CellVector(items)))
    return ct
end

function delete_row!(ct::CellTable, r::Integer)
    deleteat!(ct.rows, r)
    return ct
end

function Base.iterate(ct::CellTable, s...)
    r = iterate(ct.rows, s...)
    r === nothing && return nothing
    (row, state) = r
    (row::CellVector, state)
end
