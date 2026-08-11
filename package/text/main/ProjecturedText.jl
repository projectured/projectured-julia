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
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const SelectionModule = ProjecturedKernel.SelectionModule
const CollectionModule = ProjecturedCollection.CollectionModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const GeometryModule = ProjecturedStyle.GeometryModule
const OperationModule = ProjecturedKernel.OperationModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const ImageModule = ProjecturedStyle.ImageModule
const PointReferenceStepModule = ProjecturedGraphics.PointReferenceStepModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const OperationApiModule = ProjecturedKernel.OperationModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule

include("TextSpanReferenceStep.jl")
include("TextColumnReferenceStep.jl")
include("TextRangeReferenceStep.jl")
include("Text.jl")
include("TextToGraphics.jl")
include("TextToString.jl")
include("LineNumbering.jl")
include("WordWrapping.jl")
include("TextFiltering.jl")
include("TextFirstLine.jl")
include("TextHighlighting.jl")
include("SelectionInverting.jl")
include("PrimitiveToText.jl")
include("ReferenceToText.jl")

end # module ProjecturedText
