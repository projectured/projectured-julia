# Fragment of `DataFramesModule`.
#
# The order of the rows of a view. The glyph of the header of a column that sets
# it is `make_sort_glyph` of the platform; a click on it writes the keys that
# `compute_clicked_sort_keys` gives.

# The keys of `query` as `(column, descending)` pairs.
_get_sort_keys(query) = Tuple{String,Bool}[(key.column, key.descending) for key in query.sort_keys]

# The operation of a click on the glyph of column `name` in `view`: the new keys
# of its query, and the result from its start.
function _make_sort_operation(view, name::String, adding::Bool)
    keys = compute_clicked_sort_keys(_get_sort_keys(view.query), name, adding)
    value = CellVector(Cell[Cell(DataFrameSortKey(; column, descending)) for (column, descending) in keys])
    _make_query_edit_operation(view, ReplaceReferencedValueOperation(view.query, "sort_keys", value))
end

# The `kept` rows of `frame` in the order of `keys`; a key that names no column
# of the frame is left out. Values of types that have no order between them
# keep the order of the frame.
function _sort_kept_rows(frame, kept::Vector{Int}, keys)
    columns = Tuple{String,Bool}[(key.column, key.descending) for key in keys if key.column in names(frame)]
    isempty(columns) && return kept
    # Through `invokelatest`: the sort runs code of DataFrames that a package
    # loaded later can invalidate, and a view that sorts nothing does not depend
    # on it.
    Base.invokelatest(_sort_rows_by_columns, frame, kept, columns)
end

# The `kept` rows of `frame` in the order of `columns`, each a name and whether it
# descends.
function _sort_rows_by_columns(frame, kept::Vector{Int}, columns::Vector{Tuple{String,Bool}})
    rows = Base.view(frame, kept, first.(columns))
    try
        kept[sortperm(rows, first.(columns); rev = last.(columns))]
    catch exception
        exception isa MethodError || rethrow()
        kept
    end
end
