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
using ProjecturedNatural
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const NaturalModule = ProjecturedNatural.NaturalModule
const NaturalModule = ProjecturedNatural.NaturalModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const TextModule = ProjecturedText.TextModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const SelectionModule = ProjecturedKernel.SelectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IntentModule = ProjecturedKernel.IntentModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const TextSpanReferenceStepModule = ProjecturedText.TextSpanReferenceStepModule
const TextRangeReferenceStepModule = ProjecturedText.TextRangeReferenceStepModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const StyleModule = ProjecturedStyle.StyleModule
const TextToStringModule = ProjecturedText.TextToStringModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const DomainModule = ProjecturedDomain.DomainModule
const DomainModule = ProjecturedDomain.DomainModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule

include("../../../source/syntax/SyntaxDocument.jl")

# The reflection tail this package can draw with, offered to the natural
# renderer. Runtime state, so it is registered on load rather than baked into an
# image — and from here, because Julia calls `__init__` on a package's top-level
# module only.
__init__() = SyntaxModule.register_syntax_fallback!()

end # module ProjecturedSyntax
