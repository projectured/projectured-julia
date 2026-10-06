# Fragment of `PivotModule`.
#
# The documents of a pivot: the table with its five zones of dimensions and
# measures, a dimension, a measure, and the kinds of the view of a cell. The
# zones are `CellVector`s, so a move of a dimension from one zone to another is
# a `MoveRangeOperation`, which keeps the cell of the dimension and has an
# inverse.

@domain Pivot

"""
    PivotDimension(column; order = :natural, descending = false, hidden_values = Any[])

A dimension of a pivot: the values of column `column` of the source cut the
rows into parts. `order` says how its values follow each other: `:natural`, the
order of `isless` with `missing` last, or `:first`, the order in which the
values first occur in the source. `descending` turns the order round.
`hidden_values` holds the values that the pivot leaves out, with their rows.
"""
@document struct PivotDimension <: PivotDocument
    column::String
    order::Symbol = :natural
    descending::Bool = false
    hidden_values::Vector{Any} = Any[]
end

PivotDimension(column::AbstractString; order::Symbol = :natural, descending::Bool = false,
               hidden_values::AbstractVector = Any[]) =
    PivotDimension(String(column), order, descending, Any[hidden_values...], nothing)

"""
    PivotMeasure(column, aggregate)

A measure of a pivot: what a cell computes from the values of column `column`
in its part. `aggregate` is one of `:count`, `:sum`, `:mean`, `:minimum`,
`:maximum` and `:distinct_count`. `:count` counts the rows of the part and
reads no column, so its `column` can be empty.
"""
@document struct PivotMeasure <: PivotDocument
    column::String = ""
    aggregate::Symbol = :count
end

PivotMeasure(column::AbstractString, aggregate::Symbol) = PivotMeasure(String(column), aggregate, nothing)

"""
    PivotCellView

The kind of the view of a cell of a pivot: what a cell shows of its part. Each
kind is a subtype, and the menu of the cell view lists the subtypes that are
loaded.
"""
abstract type PivotCellView <: PivotDocument end

"""
    PivotNumberView()

A cell shows the value of each measure of the pivot for its part, and the count
of its rows when the pivot has no measure.
"""
@document struct PivotNumberView <: PivotCellView
end

"""
    PivotTable

A table cut into parts by the values of its dimensions, and the view of each
part. `source` is any table of the table interface: a data frame, a vector of
named tuples, a named tuple of vectors. The five zones hold the dimensions and
the measures, in the order of the rows of the bar above the table:

- `unused_dimensions`, the field row: the dimensions that no zone uses;
- `column_dimensions`: their values make the column headers, one level each;
- `row_dimensions`: their values make the row headers, one level each;
- `cell_dimensions`: the dimensions that the view of a cell uses inside it;
- `measures`: the [`PivotMeasure`](@ref)s that a cell computes.

`cell_view` is the [`PivotCellView`](@ref) of each cell, or `nothing` for the
choice that follows from the cell dimensions. A program that changes the source
in place writes `source_version`, and every computation over the source reads it.

`cross_table` is the [`PivotCrossTable`](@ref) of the source, computed again when
a zone, a dimension or `source_version` changes. A path names a cell of the
pivot by its row and its column in that table: `cells[r][c]`, through the field
`cells`, which holds the [`PivotCells`](@ref) of the pivot. Make a pivot with
[`make_pivot_table`](@ref), which sets both.
"""
@document struct PivotTable <: PivotDocument
    source::Any
    unused_dimensions::CellVector
    column_dimensions::CellVector
    row_dimensions::CellVector
    cell_dimensions::CellVector
    measures::CellVector
    cell_view::Any
    source_version::Int
    cross_table::Any
    cells::Any
end

"""
    PivotCells(pivot)

The value of the field `cells` of a [`PivotTable`](@ref): what the path
`cells[r][c]` steps through. `[r]` gives row `r` of the cross table, a
[`PivotCellRow`](@ref), and `[r][c]` the document of the cell where row `r` and
column `c` meet. `rows` keeps the row of each number that a path reached, so a
path into a row meets the same row each time. `documents` keeps the document of
each cell by the keys of its row and its column and by the kind of its view, so a
change of the pivot that keeps both keys and the view keeps the document, and a
selection inside it. `cross` is a `Ref` of the cross table that `documents` was
last pruned for: a new cross table drops the documents of the keys that it does
not have. The three are caches, which no computation depends on.
"""
@document struct PivotCells <: PivotDocument
    pivot::Any
    rows::Any
    documents::Any
    cross::Any
end

PivotCells(pivot) = PivotCells(pivot, Dict{Int,Any}(), Dict{Any,Any}(), Ref{Any}(nothing), nothing)

"""
    PivotCellRow(pivot, row)

Row `row` of the cross table of `pivot`, what the path `cells[r]` names. `[c]`
gives the document of the cell in column `c`.
"""
@document struct PivotCellRow <: PivotDocument
    pivot::Any
    row::Int
end

function Base.getindex(cells::PivotCells, r::Integer)
    pivot = cells.pivot
    1 <= r <= get_pivot_row_count(pivot.cross_table) || throw(BoundsError(cells, r))
    get!(() -> PivotCellRow(pivot, Int(r), nothing), cells.rows, Int(r))
end

Base.length(row::PivotCellRow) = get_pivot_column_count(row.pivot.cross_table)

function Base.getindex(row::PivotCellRow, c::Integer)
    1 <= c <= length(row) || throw(BoundsError(row, c))
    get_pivot_cell_document(row.pivot, row.row, Int(c))
end

# Each holds the pivot, which holds it, so each prints by its kind alone.
Base.show(io::IO, ::PivotCells) = print(io, "PivotCells(…)")
Base.show(io::IO, row::PivotCellRow) = print(io, "PivotCellRow(…, ", row.row, ")")

# The computed fields of `pivot`: its cross table, and the cells that the paths
# step through.
function _set_pivot_fields!(pivot::PivotTable)
    set_cell_computation!(getfield(pivot, :cross_table), () -> compute_pivot_cross_table(pivot))
    getfield(pivot, :cells)[] = PivotCells(pivot)
    pivot
end

"""
    make_pivot_table(source; rows = String[], columns = String[], cells = String[],
                     measures = PivotMeasure[], cell_view = nothing) -> PivotTable

A pivot of `source` whose row, column and cell dimensions are the columns of the
source named in `rows`, `columns` and `cells`, in that order. Every other column
of the source is an unused dimension, in the order of the source.
"""
function make_pivot_table(source; rows = String[], columns = String[], cells = String[],
                          measures = PivotMeasure[], cell_view = nothing)
    is_table(source) || throw(ArgumentError("a pivot needs a table, not a $(typeof(source))"))
    names = get_table_column_names(source)
    used = Set{String}(vcat(rows, columns, cells))
    for name in used
        name in names || throw(ArgumentError("the source has no column \"$name\""))
    end
    make_dimensions(list) = CellVector(Any[PivotDimension(String(name)) for name in list])
    _set_pivot_fields!(PivotTable(source, make_dimensions(filter(name -> !(name in used), names)),
                                  make_dimensions(columns), make_dimensions(rows), make_dimensions(cells),
                                  CellVector(Any[measures...]), cell_view, 0, nothing, nothing, nothing))
end
