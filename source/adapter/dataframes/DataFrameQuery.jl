# Fragment of `DataFramesModule`.
#
# The query of a view: what the view keeps of its frame. It is a document, so a
# menu, a key and the assistant change it with the same edits, and a saved
# window keeps it.

"""
    DataFrameQuery(; hidden_columns = String[])

What a `DataFrameView` keeps of its frame: `hidden_columns` names the columns
that it does not show.
"""
@document struct DataFrameQuery <: Document
    hidden_columns::Vector{String} = String[]
end

# The names of the columns that `view` shows, in the order of its frame.
_get_shown_columns(view) =
    String[name for name in names(view.frame) if !(name in view.query.hidden_columns)]

# The operation that writes `hidden` as the hidden columns of the query of
# `view`.
_make_hidden_columns_operation(view, hidden::Vector{String}) =
    ReplaceReferencedValueOperation(view.query, "hidden_columns", hidden)

_make_hide_column_operation(view, name::String) =
    _make_hidden_columns_operation(view, unique(vcat(view.query.hidden_columns, name)))

_make_show_column_operation(view, name::String) =
    _make_hidden_columns_operation(view, filter(!=(name), view.query.hidden_columns))
