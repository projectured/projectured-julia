# Fragment of `PivotModule`.
#
# The view of a cell: which kind of view a cell of a pivot shows, the document
# that each kind makes from the part of the cell, and the text of a value and of
# a measure. A cell document is kept by the keys of its row and its column, and
# it reads its part by those keys, so it shows the right part when the cross
# table changes.

"""
    get_pivot_cell_view(pivot::PivotTable) -> PivotCellView

The view of each cell of `pivot`: its `cell_view`, or, when that is `nothing`,
the view that follows from its cell dimensions. With no cell dimension, a cell
shows its measures as numbers.
"""
function get_pivot_cell_view(pivot::PivotTable)
    view = pivot.cell_view
    view isa PivotCellView && return view
    PivotNumberView()
end

"""
    get_pivot_measures(pivot::PivotTable) -> Vector

The measures of `pivot`, or the count of the rows when it has none.
"""
function get_pivot_measures(pivot::PivotTable)
    measures = collect(pivot.measures)
    isempty(measures) ? Any[PivotMeasure("", :count)] : measures
end

"""
    describe_pivot_measure(measure::PivotMeasure) -> String

The name of a measure for a person: `count`, or the aggregate and its column,
such as `sum(amount)`.
"""
describe_pivot_measure(measure) =
    measure.aggregate === :count ? "count" : string(measure.aggregate, "(", measure.column, ")")

"""
    format_pivot_value(value) -> String

The text of a value in a header or a cell: a whole number with no fraction, any
other number with at most two decimal places, `missing` as the word, and any
other value as `string` prints it.
"""
format_pivot_value(value::AbstractString) = String(value)
format_pivot_value(value::Integer) = string(value)
format_pivot_value(value::AbstractFloat) =
    isfinite(value) && isinteger(value) && abs(value) < 1e15 ? string(Int(value)) :
        string(round(value; digits = 2))
format_pivot_value(::Missing) = "missing"
format_pivot_value(value) = string(value)

"""
    get_pivot_cell_document(pivot::PivotTable, row::Int, column::Int)

The document of the cell in row `row` and column `column` of the cross table of
`pivot`, made by the view of the pivot when a path or the table first reaches
it, and kept by the keys of the row and the column and by the kind of the view.
"""
function get_pivot_cell_document(pivot::PivotTable, row::Int, column::Int)
    cross = pivot.cross_table
    cells = pivot.cells
    pruned = cells.cross
    if pruned[] !== cross
        _prune_pivot_cell_documents!(cells, cross)
        pruned[] = cross
    end
    view = get_pivot_cell_view(pivot)
    key = (cross.row_keys[row], cross.column_keys[column], typeof(view))
    get!(() -> make_pivot_cell_document(pivot, view, key[1], key[2]), cells.documents, key)
end

# Drop the documents of the keys that `cross` does not have.
function _prune_pivot_cell_documents!(cells::PivotCells, cross::PivotCrossTable)
    documents = cells.documents
    for key in collect(keys(documents))
        (haskey(cross.row_index, key[1]) && haskey(cross.column_index, key[2])) || delete!(documents, key)
    end
    cells
end

"""
    make_pivot_cell_document(pivot, view::PivotCellView, row_key, column_key)

The document that `view` makes for the cell with the keys `row_key` and
`column_key`. The document reads its part by the keys, so it follows the source
and the measures of `pivot`.
"""
function make_pivot_cell_document end

# The number view: the value of each measure over the part, beside each other.
# A cell that no row reaches is empty.
function make_pivot_cell_document(pivot::PivotTable, ::PivotNumberView, row_key::Tuple, column_key::Tuple)
    WidgetLabel(() -> begin
        rows = find_pivot_part_rows(pivot.cross_table, row_key, column_key)
        rows === nothing && return ""
        join((format_pivot_value(compute_pivot_measure(pivot.source, rows, measure))
              for measure in get_pivot_measures(pivot)), "  ")
    end)
end
