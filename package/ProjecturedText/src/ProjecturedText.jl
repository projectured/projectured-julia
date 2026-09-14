"""
    ProjecturedText

The styled-text domain, its three reference steps over the flat character
range, its render endpoints, its decorators, and the bridges from the
primitive and reference documents.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedText

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle

const CellModule = ProjecturedKernel.CellModule
const CellStructModule = ProjecturedKernel.CellStructModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const SelectionModule = ProjecturedKernel.SelectionModule
const CollectionModule = ProjecturedCollection.CollectionModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const OperationModule = ProjecturedKernel.OperationModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const StyleModule = ProjecturedStyle.StyleModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule

include("../../../source/text/TextSpanReferenceStep.jl")

end # module ProjecturedText
