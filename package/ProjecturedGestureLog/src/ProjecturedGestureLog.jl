"""
    ProjecturedGestureLog

What was pressed: the log document, its syntax printer, the recorder that
decorates an arbitrary projection, and the overlay that draws the panel.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedGestureLog

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedGraphics
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
const EventModule = ProjecturedKernel.EventModule
const EventModule = ProjecturedKernel.EventModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const IntentModule = ProjecturedKernel.IntentModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const NaturalModule = ProjecturedNatural.NaturalModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/gesturelog/GestureLogModule.jl")

end # module ProjecturedGestureLog
