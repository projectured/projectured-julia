"""
    ProjecturedStatistics

What the editor loop measures about itself: the frame statistics document,
the feed that flushes the editor's frame sample store into it, and its
syntax printer.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedStatistics

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const SerializationModule = ProjecturedSerialization.SerializationModule
const FeedModule = ProjecturedKernel.FeedModule
const FrameSampleModule = ProjecturedKernel.FrameSampleModule

include("../../../source/statistics/FrameStatisticsModule.jl")

end # module ProjecturedStatistics
