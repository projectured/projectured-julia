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
each cell is an index vector into the source. [`PivotTableToWidget`](@ref) draws
the zones as a bar above a table whose headers have one level for each
dimension, and each cell shows the document that the view of the pivot makes.
"""
module PivotModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..WidgetModule: make_graphics_projection

export PivotDimension, PivotMeasure, PivotCellView, PivotNumberView, PivotTable, PivotCells, PivotCellRow,
       make_pivot_table
export PivotCrossTable, get_pivot_row_count, get_pivot_column_count, find_pivot_part_rows,
       compute_pivot_cross_table, compute_pivot_measure
export get_pivot_cell_view, get_pivot_measures, describe_pivot_measure, format_pivot_value,
       get_pivot_cell_document, make_pivot_cell_document
export PivotTableToWidget, PivotTableToWidgetIoMap, make_pivot_table_projection

include("PivotDocument.jl")
include("PivotCrossTable.jl")
include("PivotCellView.jl")
include("PivotTableToWidget.jl")

# A pivot draws as its bar and its table in a tab, and inside any document that
# the natural renderer draws.
make_graphics_projection(::Type{PivotTable}; measure, appearance) =
    make_pivot_table_projection(; measure, appearance)

end # module PivotModule
