"""
    ProjecturedSyntax

The generic tree presentation target every source domain funnels through:
leaves, nodes, delimiters, indentation and collapsibles, the flattening to
styled text, the bridges from objects, collections and primitives, and the
shared insert-by-typing leaf.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedSyntax

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const TextModule = ProjecturedText.TextModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const SelectionModule = ProjecturedKernel.SelectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IntentModule = ProjecturedKernel.IntentModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const TextSpanReferenceStepModule = ProjecturedText.TextSpanReferenceStepModule
const TextRangeReferenceStepModule = ProjecturedText.TextRangeReferenceStepModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const TextToStringModule = ProjecturedText.TextToStringModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const DomainModule = ProjecturedDomain.DomainModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule

include("Syntax.jl")
include("SyntaxToText.jl")
include("ObjectToSyntax.jl")
include("CollectionToSyntax.jl")
include("PrimitiveToSyntax.jl")
include("InsertionToSyntax.jl")

end # module ProjecturedSyntax
