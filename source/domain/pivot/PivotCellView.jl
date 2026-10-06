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
the view that follows from its cell dimensions:

- no cell dimension: the measures as numbers;
- one cell dimension of numbers: a line chart over its values;
- one cell dimension of eight values or fewer: a bar chart over its values;
- two cell dimensions: a bar chart with a series for each value of the second;
- any other: the rows of the part in the columns of the cell dimensions.

A pie chart is a view that a person chooses.
"""
function get_pivot_cell_view(pivot::PivotTable)
    view = pivot.cell_view
    view isa PivotCellView && return view
    dimensions = collect(pivot.cell_dimensions)
    isempty(dimensions) && return PivotNumberView()
    length(dimensions) == 2 && return PivotBarChartView()
    length(dimensions) > 2 && return PivotRowsView()
    type = nonmissingtype(get_table_column_type(pivot.source, dimensions[1].column))
    (type <: Real && !(type <: Bool)) && return PivotLineChartView()
    _count_pivot_categories(pivot, dimensions[1]) <= 8 ? PivotBarChartView() : PivotRowsView()
end

"""
    describe_pivot_cell_view(view::Type{<:PivotCellView}) -> String

The name of a kind of view of a cell for a person, as the menu of the cell view
and the Cells row of the bar show it.
"""
describe_pivot_cell_view(::Type{PivotNumberView}) = "numbers"
describe_pivot_cell_view(::Type{PivotRowsView}) = "rows"
describe_pivot_cell_view(type::Type{<:PivotCellView}) = string(nameof(type))

"""
    get_pivot_cell_view_lines(view::PivotCellView) -> Int

How many lines of text a row of the table gives to a cell that shows `view`.
"""
get_pivot_cell_view_lines(::PivotNumberView) = 1
get_pivot_cell_view_lines(::PivotRowsView) = 10
get_pivot_cell_view_lines(::PivotCellView) = 10

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
format_pivot_value(::PivotTotal) = "total"
format_pivot_value(bin::PivotBin) = string(format_pivot_value(bin.low), "–", format_pivot_value(bin.high))
format_pivot_value(month::PivotMonth) = string(month.year, "-", lpad(month.month, 2, '0'))
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
    row_key, column_key = cross.row_keys[row], cross.column_keys[column]
    key = (row_key, column_key, typeof(view), get_pivot_cell_key(pivot, view, row_key, column_key))
    get!(() -> make_pivot_cell_document(pivot, view, row_key, column_key), cells.documents, key)
end

"""
    get_pivot_cell_key(pivot, view::PivotCellView, row_key, column_key)

What the document of a cell depends on beside its keys and the kind of its view,
as a part of the key that keeps it. A number reads its part when it draws, so
it depends on nothing more; the rows of a part are fixed when its table is made,
so a table depends on the rows and on its columns.
"""
get_pivot_cell_key(::PivotTable, ::PivotCellView, ::Tuple, ::Tuple) = nothing

function get_pivot_cell_key(pivot::PivotTable, ::PivotRowsView, row_key::Tuple, column_key::Tuple)
    rows = find_pivot_part_rows(pivot.cross_table, row_key, column_key)
    (rows === nothing ? nothing : hash(rows), _get_pivot_cell_columns(pivot))
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

# The columns that a table of a part shows: the columns of the cell dimensions,
# or every column of the source.
function _get_pivot_cell_columns(pivot::PivotTable)
    columns = String[dimension.column for dimension in pivot.cell_dimensions]
    isempty(columns) ? get_table_column_names(pivot.source) : columns
end

# The rows view: the part as a table, which the package of the source makes when
# it has a document of its own, and a read-only `PivotPartTable` otherwise. A
# cell that no row reaches is empty.
function make_pivot_cell_document(pivot::PivotTable, ::PivotRowsView, row_key::Tuple, column_key::Tuple)
    rows = find_pivot_part_rows(pivot.cross_table, row_key, column_key)
    rows === nothing && return WidgetLabel("")
    part = make_table_part(pivot.source, collect(rows))
    columns = _get_pivot_cell_columns(pivot)
    document = make_table_document(part, columns)
    document === nothing ? PivotPartTable(part, columns) : document
end

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
