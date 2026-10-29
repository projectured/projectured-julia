# Fragment of `DataFramesModule`.
#
# The rows that pass the filters of a query. The text of a filter is in the
# language of the platform (`parse_filter_text`), read once with the element type
# of its column into a condition, a callable struct, and the condition runs over
# the vector of the column, so a filter of ten million rows calls one compiled
# function for each row. A text that does not parse keeps every row.

# ── The rows that pass ───────────────────────────────────────────────────────

# The rows of `frame` that pass every filter of `query` and `expression`, the
# rows that its expression passes or `nothing`, in the order of the frame. A
# filter that names no column of the frame, or whose text does not parse, keeps
# every row.
function _compute_kept_rows(frame, query, expression = nothing)
    keep = expression === nothing ? trues(nrow(frame)) : copy(expression)
    columns = Set(names(frame))
    for filter in query.column_filters
        filter.column in columns || continue
        column = frame[!, filter.column]
        condition = parse_filter_text(filter.text, eltype(column))
        (condition === nothing || condition isa String) && continue
        _apply_filter_condition!(keep, column, condition)
    end
    _sort_kept_rows(frame, findall(keep), query.sort_keys)
end

# One condition over one column, compiled for both types.
function _apply_filter_condition!(keep::BitVector, column::AbstractVector, condition)
    for i in 1:length(column)
        keep[i] && (keep[i] = condition(column[i]))
    end
    keep
end
