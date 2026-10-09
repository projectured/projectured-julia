"""
    DataFramesModule

Opt-in package: views and edits of the native structures of DataFrames.jl —
`DataFrame`, `SubDataFrame`, `DataFrameRow`, `GroupedDataFrame` — in the
editor. The data stays in the data frame; the view reads the visible rows.

A [`DataFrameView`](@ref) holds the frame and the state of the view, and
[`DataFrameViewToWidget`](@ref) draws it as a table that scrolls its own parts.
The rows of the table are a list anchored at any row of the frame, and the
columns of a wide frame a list anchored at any column, so a jump to any row
costs the rows that the table shows.
"""
module DataFramesModule

using DataFrames

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, copy_document, has_document_duplicate
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..OperationModule: evaluate_operation, make_inverse_operation,
                          is_self_contained_operation
import ..DomainModule: compute_context_menu
import ..NavigatorModule: is_navigator_stop, find_navigator_choices
import ..WidgetModule: make_value_document, make_graphics_projection, refresh_document!
import ..CollectionModule: is_table, get_table_row_count, get_table_column_names, get_table_column_type,
                           get_table_value, find_table_column, make_table_part, make_table_document

export DataFrameColumnFilter, DataFrameSortKey, DataFrameQuery
export DataFrameView, DataFrameCellEdit, DataFrameViewRows, DataFrameViewRow,
       DataFrameViewColumns, jump_to_row, make_data_frame_cell
export DataFrameColumn
export SetDataFrameValueOperation, OpenDataFrameCellOperation, CloseDataFrameCellOperation
export InsertDataFrameRowOperation, DeleteDataFrameRowOperation
export InsertDataFrameColumnOperation, DeleteDataFrameColumnOperation,
       MoveDataFrameColumnOperation
export RefreshDataFrameViewOperation
export DataFrameTheme, ScaledDataFrameTheme
export DataFrameViewToWidget, make_data_frame_view_projection
export DataFrameViewRowToWidget, make_data_frame_row_projection

include("DataFrameTable.jl")
include("DataFrameQuery.jl")
include("DataFrameFilter.jl")
include("DataFrameExpression.jl")
include("DataFrameSort.jl")
include("DataFrameView.jl")
include("DataFrameColumn.jl")
include("DataFrameEdit.jl")
include("DataFrameRowEdit.jl")
include("DataFrameColumnEdit.jl")
include("DataFrameFind.jl")
include("DataFrameRefresh.jl")
include("DataFrameTheme.jl")
include("DataFrameFilterRow.jl")
include("DataFrameValueList.jl")
include("DataFrameViewToWidget.jl")
include("DataFrameViewRowToWidget.jl")

# A data frame shows as a `DataFrameView`: in the display of a value, and inside
# any document that the natural renderer draws.
make_value_document(frame::AbstractDataFrame) = DataFrameView(frame)
make_graphics_projection(::Type{DataFrameView}; measure, appearance) =
    make_data_frame_view_projection(; measure, appearance)

# A row shows as its page, a form of its columns, where a navigator opens it.
make_graphics_projection(::Type{DataFrameViewRow}; measure, appearance) =
    ChainingProjection(make_data_frame_row_projection(; widget_theme = get_scaled_theme!(appearance, WidgetTheme)),
                       GridLayoutToGraphicsCanvas())

end # module DataFramesModule
