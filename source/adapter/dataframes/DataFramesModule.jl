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
import ..ProjectionModule: print_document, read_intent
import ..WidgetModule: make_value_document, make_graphics_projection

export DataFrameView, jump_to_row, make_data_frame_cell
export DataFrameViewToWidget, make_data_frame_view_projection

include("DataFrameView.jl")
include("DataFrameViewToWidget.jl")

# A data frame shows as a `DataFrameView`: in the display of a value, and inside
# any document that the natural renderer draws.
make_value_document(frame::AbstractDataFrame) = DataFrameView(frame)
make_graphics_projection(::Type{DataFrameView}; measure) =
    make_data_frame_view_projection(; measure)

end # module DataFramesModule
