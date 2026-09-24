"""
    ProjecturedStatistics

What the editor loop measures about itself: the frame statistics table and
the frame plot, the feed that flushes the editor's frame measurement store into
them, the syntax printer of the table and the chart projection of the plot.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedStatistics

using ProjecturedChart
using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedProjection
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
const NaturalModule = ProjecturedNatural.NaturalModule
const SerializationModule = ProjecturedSerialization.SerializationModule
const FeedModule = ProjecturedKernel.FeedModule
const PerformanceModule = ProjecturedKernel.PerformanceModule
const ChartModule = ProjecturedChart.ChartModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule

include("../../../source/statistics/FrameStatisticsModule.jl")

end # module ProjecturedStatistics
