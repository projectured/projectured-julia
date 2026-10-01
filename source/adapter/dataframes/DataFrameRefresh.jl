# Fragment of `DataFramesModule`.
#
# The refresh of a view after its frame changed in place: a program writes a
# value, pushes a row or adds a column, and the frame stays the same object, so
# no cell of the view sees the change. A refresh compares a snapshot of the
# frame with the last one, at three levels of cost:
#
# 1. the structure: the count of the rows, the names and the types of the
#    columns, and the identity of each column vector;
# 2. the values of the rows around the top row of the table, which the table
#    shows;
# 3. when the query reads columns, the whole content of those columns, because
#    a value that the table does not show can change which rows pass and their
#    order.
#
# When the snapshot differs, the view moves `frame_version`, which every
# computation that reads the data of the frame reads too, so the view computes
# its rows again and builds what the table shows again. A refresh with no change
# moves nothing.

# How many rows from the top row, and how many shown columns from the head
# column, the second level reads.
const _REFRESH_WINDOW_ROWS = 100
const _REFRESH_WINDOW_COLUMNS = 64

# The hash of every value of `column`, in order. `hash` of an array reads only a
# few of its elements, so it misses a write in the middle.
function _hash_column_content(column::AbstractVector, h::UInt)
    for value in column
        h = hash(value, h)
    end
    h
end

# The names of the columns that the query of `view` reads: those of a filter
# with a text, of a sort key, and of the expression.
function _find_query_columns(view)
    query = view.query
    read = Set{String}(filter.column for filter in query.column_filters if !isempty(strip(filter.text)))
    union!(read, (key.column for key in query.sort_keys))
    if !isempty(strip(query.expression))
        compiled = _compile_expression(query.expression, names(view.frame))
        compiled isa String || union!(read, last(compiled))
    end
    sort!([name for name in read if name in names(view.frame)])
end

# The snapshot of the frame of `view` at the three levels.
function _take_frame_snapshot(view)
    frame = view.frame
    columns = names(frame)
    kept = view.kept_rows
    top = clamp(view.anchor + view.top_row - 1, 1, max(1, length(kept)))
    window = kept[top:min(length(kept), top + _REFRESH_WINDOW_ROWS - 1)]
    shown = _get_shown_columns(view)
    first_shown = clamp(view.column_anchor, 1, max(1, length(shown)))
    shown = shown[first_shown:min(length(shown), first_shown + _REFRESH_WINDOW_COLUMNS - 1)]
    cells = zero(UInt)
    for row in window, name in shown
        cells = hash(frame[row, name], cells)
    end
    content = zero(UInt)
    for name in _find_query_columns(view)
        content = _hash_column_content(frame[!, name], hash(name, content))
    end
    (rows = nrow(frame), names = columns, types = Any[eltype(frame[!, name]) for name in columns],
     columns = UInt[objectid(frame[!, name]) for name in columns], cells, content)
end

# A filter for each column of the frame of `view` that the query has no filter
# for, so the field of a new column can hold a text.
function _add_missing_column_filters!(view)
    filters = view.query.column_filters
    for name in names(view.frame)
        _find_column_filter(view.query, name) === nothing &&
            push!(filters, DataFrameColumnFilter(; column = String(name)))
    end
    nothing
end

# Move `frame_version` of `view` when its frame changed since the last refresh,
# or always when `force` or at the first refresh, which has no snapshot to
# compare with, and keep the new snapshot. A value of a type that a package
# loaded later hashes in the newest world.
function _refresh_data_frame_view!(view; force::Bool = false)
    snapshot = Base.invokelatest(_take_frame_snapshot, view)
    (force || snapshot != view.frame_snapshot) || return false
    _add_missing_column_filters!(view)
    view.frame_snapshot = snapshot
    view.frame_version += 1
    true
end

refresh_document!(view::DataFrameView) = (_refresh_data_frame_view!(view); nothing)

"""
    RefreshDataFrameViewOperation(view)

The operation that reads the frame of `view` again at every level, whether its
snapshot changed or not: the key F5 of the view.
"""
struct RefreshDataFrameViewOperation <: Operation
    view::DataFrameView
end

evaluate_operation(editor, operation::RefreshDataFrameViewOperation) =
    (_refresh_data_frame_view!(operation.view; force = true); nothing)
