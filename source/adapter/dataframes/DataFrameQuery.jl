# Fragment of `DataFramesModule`.
#
# The query of a view: what the view keeps of its frame. It is a document, so a
# menu, a key and the assistant change it with the same edits, and a saved
# window keeps it.

"""
    DataFrameColumnFilter(; column, text = "")

The filter of the rows by one column: `text` is a condition in the language of
the filter row, which the element type of `column` reads. An empty text keeps
every row.
"""
@document struct DataFrameColumnFilter <: Document
    column::String
    text::String = ""
end

"""
    DataFrameSortKey(; column, descending = false)

One key of the order of the rows of a view: the rows are in the order of the
values of `column`, the smallest first, or the largest first when `descending`.
"""
@document struct DataFrameSortKey <: Document
    column::String
    descending::Bool = false
end

"""
    DataFrameQuery(; hidden_columns = String[], column_pattern = "", column_filters, expression = "",
                   sort_keys)

What a `DataFrameView` keeps of its frame. `hidden_columns` names the columns
that it does not show, and `column_pattern` keeps the columns whose names match
it: a text that a name contains, or `/re/`, a regular expression. A row passes
when it passes the `DataFrameColumnFilter` of every column in `column_filters`
and the Julia `expression` over the columns. The rows that pass are in the
order of the `DataFrameSortKey`s of `sort_keys`, the first key first, and in the
order of the frame where all keys are equal.
"""
@document struct DataFrameQuery <: Document
    hidden_columns::Vector{String} = String[]
    column_pattern::String = ""
    column_filters::CellVector = CellVector()
    expression::String = ""
    sort_keys::CellVector = CellVector()
end

# The query of a new view of `frame`: a filter for each column, with no text.
_make_frame_query(frame) =
    DataFrameQuery(; column_filters = CellVector(Cell[Cell(DataFrameColumnFilter(; column = String(name)))
                                                      for name in names(frame)]))

# The filter of column `name` in `query`, and its place in the filters of the
# query, or `nothing`.
function _find_column_filter(query, name::String)
    i = _find_filter_place(query, name)
    i === nothing ? nothing : query.column_filters[i]
end

function _find_filter_place(query, name::String)
    for (i, filter) in enumerate(query.column_filters)
        filter.column == name && return i
    end
    nothing
end

# The names of the columns that `view` shows, in the order of its frame: the
# columns that it does not hide, and whose names the pattern keeps. A
# computation that reads them follows a refresh of the frame too.
function _get_shown_columns(view)
    view.frame_version
    query = view.query
    keep = _parse_name_pattern(query.column_pattern)
    String[name for name in names(view.frame)
           if !(name in query.hidden_columns) && (keep isa String || keep(name))]
end

# `edit`, an edit of the query of `view`, and the view state that shows the
# result of the new query from its start.
function _make_query_edit_operation(view, edit)
    start(field, value) = ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, field, value))
    CompoundOperation(Any[edit, start("anchor", 1), start("column_anchor", 1),
                          start("scroll_position", Point2D(0, 0)), start("top_row", 1)])
end

# The operation that writes the text of the filter of `column` in `view` and
# shows the result of the new query from its start.
function _make_filter_write_operation(view, column::String, text::String)
    filter = _find_column_filter(view.query, column)
    _make_query_edit_operation(view, ReplaceReferencedValueOperation(filter, "text", text))
end

# The operation that writes `hidden` as the hidden columns of the query of
# `view`.
_make_hidden_columns_operation(view, hidden::Vector{String}) =
    ReplaceReferencedValueOperation(view.query, "hidden_columns", hidden)

_make_hide_column_operation(view, name::String) =
    _make_hidden_columns_operation(view, unique(vcat(view.query.hidden_columns, name)))

_make_show_column_operation(view, name::String) =
    _make_hidden_columns_operation(view, filter(!=(name), view.query.hidden_columns))
