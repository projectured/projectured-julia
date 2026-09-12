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
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule

include("../../../source/text/TextSpanReferenceStep.jl")
include("../../../source/text/TextColumnReferenceStep.jl")
include("../../../source/text/TextRangeReferenceStep.jl")
include("../../../source/text/TextDocument.jl")
include("../../../source/text/TextToGraphics.jl")
include("../../../source/text/TextToString.jl")
include("../../../source/text/LineNumbering.jl")
include("../../../source/text/WordWrapping.jl")
include("../../../source/text/TextFiltering.jl")
include("../../../source/text/TextFirstLine.jl")
include("../../../source/text/TextHighlighting.jl")
include("../../../source/text/SelectionInverting.jl")
include("../../../source/text/PrimitiveToText.jl")
include("../../../source/text/ReferenceToText.jl")

end # module ProjecturedText
