"""
    FrameStatisticsModule

What the editor loop measures about itself, as documents a person opens like
any other. The kernel keeps the measurements of the recent frames in the
editor's `FrameMeasurementStore`. The [`FrameStatisticsFeed`](FrameStatisticsFeed.jl)
flushes them on its own deadline, and only while a view shows them, into two
documents of [`FrameStatisticsDocument.jl`](FrameStatisticsDocument.jl):
`FrameStatistics`, a table of one summary for each measurement, and
`FrameTimeSeries`, the times of the recent frames.
[`FrameStatisticsToSyntax`](FrameStatisticsToSyntax.jl) projects the table
onto the Syntax → Text → Graphics path. The chart of the frame times is a
projection of the chart domain, `FrameTimeSeriesToChart`, so this module
depends on no domain.
"""
module FrameStatisticsModule

using Printf: @sprintf

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..FeedModule
using ..IoMapModule
using ..NaturalModule
using ..PerformanceModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..EditorModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments
import ..EditorModule: wrap_editor!, get_wrapper_layers

export FrameStatisticsRow, FrameStatistics, get_session_frame_statistics,
       flush_frame_statistics!
export FrameTimeSeries, get_session_frame_time_series, flush_frame_time_series!
export FrameStatisticsFeed
export FrameStatisticsTheme, ScaledFrameStatisticsTheme
export FrameStatisticsToSyntax, make_frame_statistics_projection

include("FrameStatisticsDocument.jl")
include("FrameStatisticsFeed.jl")
include("FrameStatisticsTheme.jl")
include("FrameStatisticsToSyntax.jl")

# The row that lets a tab draw the table; the chart domain registers the row of
# the frame times. The factory form, so every renderer builds its own
# projection instance.
function __init__()
    register_natural_syntax!(:statistics,
        (; appearance) -> Pair{Type,Any}[FrameStatistics => make_frame_statistics_projection(;
            theme = get_scaled_theme!(appearance, FrameStatisticsTheme))])
end

end # module
