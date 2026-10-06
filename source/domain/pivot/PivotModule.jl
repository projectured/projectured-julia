"""
    PivotModule

The pivot domain: a table cut into parts by the values of its dimensions, and a
view of each part. The source is any table of the table interface of the
collection slice, so a data frame, a vector of named tuples and a named tuple of
vectors pivot alike, and a part of a data frame is a `SubDataFrame`.

A [`PivotTable`](@ref) holds the source and five zones: the unused dimensions,
the column, the row and the cell dimensions, and the measures. The row and the
column dimensions cut the rows of the source into the cells of a
[`PivotCrossTable`](@ref); the keys that occur make the headers, and the part of
each cell is an index vector into the source.
"""
module PivotModule

using ..KernelModule
using ..PlatformModule

export PivotDimension, PivotMeasure, PivotCellView, PivotNumberView, PivotTable, make_pivot_table
export PivotCrossTable, get_pivot_row_count, get_pivot_column_count, find_pivot_part_rows,
       compute_pivot_cross_table, compute_pivot_measure

include("PivotDocument.jl")
include("PivotCrossTable.jl")

end # module PivotModule
