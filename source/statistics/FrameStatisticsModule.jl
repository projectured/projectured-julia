"""
    FrameStatisticsModule

What the editor loop measures about itself, as documents a person opens like
any other. The kernel keeps the measurements of the recent frames in the
editor's `FrameMeasurementStore`. The [`FrameStatisticsFeed`](FrameStatisticsFeed.jl)
flushes them on its own deadline, and only while a view shows them, into two
documents of [`FrameStatisticsDocument.jl`](FrameStatisticsDocument.jl):
`FrameStatistics`, a table of one summary for each measurement, and
`FramePlot`, the frame times of the recent frames.
[`FrameStatisticsToSyntax`](FrameStatisticsToSyntax.jl) projects the table
onto the Syntax → Text → Graphics path, and [`FramePlotToChart`](FramePlotToChart.jl)
projects the plot onto a chart.
"""
module FrameStatisticsModule

using Printf: @sprintf

using ..CellModule
using ..ChartModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..FeedModule
using ..IoMapModule
using ..NaturalModule
using ..PerformanceModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments

export FrameStatisticsRow, FrameStatistics, get_session_frame_statistics,
       flush_frame_statistics!
export FramePlot, get_session_frame_plot, flush_frame_plot!
export FrameStatisticsFeed
export FrameStatisticsToSyntax, FramePlotToChart

include("FrameStatisticsDocument.jl")
include("FrameStatisticsFeed.jl")
include("FrameStatisticsToSyntax.jl")
include("FramePlotToChart.jl")

# The rows that let a tab draw the table and the plot. The factory forms, so
# every renderer builds its own projection instances.
function __init__()
    register_natural_syntax!(:statistics,
        () -> Pair{Type,Any}[FrameStatistics => FrameStatisticsToSyntax()])
    register_natural_graphics!(:frame_plot, (; measure) -> Pair{Type,Any}[
        FramePlot => ChainingProjection(FramePlotToChart(), ChartToChartPlot(),
                                        ChartPlotToGraphicsCanvas(measure = measure)),
    ])
    register_pred_type!(FrameStatistics)
    register_pred_type!(FramePlot)
end

end # module
