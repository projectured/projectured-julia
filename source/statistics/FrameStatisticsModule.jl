"""
    FrameStatisticsModule

What the editor loop measures about itself, as a document a person opens
like any other. The kernel folds one sample per frame into the editor's
`FrameSampleStore`; the [`FrameStatisticsFeed`](FrameStatisticsFeed.jl)
flushes the summaries into a [`FrameStatistics`](FrameStatisticsDocument.jl)
document on its own deadline, and only while a view shows it.
[`FrameStatisticsToSyntax`](FrameStatisticsToSyntax.jl) projects the table
onto the Syntax → Text → Graphics path.
"""
module FrameStatisticsModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..FeedModule
using ..PerformanceModule
using ..IoMapModule
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

export FrameMeasurement, FrameStatistics, get_session_frame_statistics,
       flush_frame_statistics!
export FrameStatisticsFeed
export FrameStatisticsToSyntax

include("FrameStatisticsDocument.jl")
include("FrameStatisticsFeed.jl")
include("FrameStatisticsToSyntax.jl")

end # module
