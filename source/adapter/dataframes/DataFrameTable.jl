# Fragment of `DataFramesModule`.
#
# A data frame is a table of the table interface of the collection slice. A
# column is the vector of the frame, and a part of the rows is a `SubDataFrame`,
# so an edit in a part writes the frame. The document of a data frame is its
# view, with the other columns hidden.

is_table(::AbstractDataFrame) = true
get_table_row_count(frame::AbstractDataFrame) = nrow(frame)
get_table_column_names(frame::AbstractDataFrame) = names(frame)
get_table_column_type(frame::AbstractDataFrame, column::AbstractString) = eltype(frame[!, column])
get_table_value(frame::AbstractDataFrame, row::Integer, column::AbstractString) = frame[row, column]
find_table_column(frame::AbstractDataFrame, column::AbstractString) = frame[!, column]
make_table_part(frame::AbstractDataFrame, rows::AbstractVector{<:Integer}) = view(frame, rows, :)

function make_table_document(frame::AbstractDataFrame, columns::Vector{String})
    view = DataFrameView(frame)
    hidden = String[name for name in names(frame) if !(name in columns)]
    length(hidden) < ncol(frame) && (view.query.hidden_columns = hidden)
    view
end
