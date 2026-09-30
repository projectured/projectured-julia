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
using ProjecturedSdl: SdlBackend

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PaneModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..StyleModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent

export DataFrameView, jump_to_row, make_data_frame_cell
export DataFrameViewToWidget, make_data_frame_view_projection
export ProjecturedDisplay, display_in_editor, close_data_frame_editor!

include("DataFrameView.jl")
include("DataFrameViewToWidget.jl")
include("DataFrameDisplay.jl")

function __init__()
    register_natural_graphics!(:dataframes,
        (; measure) -> Pair{Type,Any}[DataFrameView => make_data_frame_view_projection(; measure)])
end

end # module DataFramesModule
