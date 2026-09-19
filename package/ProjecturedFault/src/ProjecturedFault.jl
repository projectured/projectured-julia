"""
    ProjecturedFault

What failed: the fault documents, the barrier projection that catches, the
renderers and the log panel.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedFault

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const FaultModule = ProjecturedKernel.FaultModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const WidgetModule = ProjecturedWidget.WidgetModule
const NaturalModule = ProjecturedNatural.NaturalModule

include("../../../source/fault/FaultViewModule.jl")

end # module ProjecturedFault
