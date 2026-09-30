"""
    ProjecturedInspector

The reference inspector document, its text rendering, and the hover probe
that follows the pointer with an inspector window.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedInspector

using ProjecturedDomain
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedProjection
using ProjecturedScreen
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DomainModule = ProjecturedDomain.DomainModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const IoMapModule = ProjecturedKernel.IoMapModule
const SelectionModule = ProjecturedKernel.SelectionModule
const IntentModule = ProjecturedKernel.IntentModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const OperationModule = ProjecturedKernel.OperationModule
const ScreenModule = ProjecturedScreen.ScreenModule
const NaturalModule = ProjecturedNatural.NaturalModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/platform/inspector/InspectorModule.jl")

end # module ProjecturedInspector
