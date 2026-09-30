"""
    ProjecturedFocus

The generic focus walk and its open trait `is_focusable_document`: which
leaf a Tab press lands on. The walk names no widget type.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedFocus

using ProjecturedCollection
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const OperationModule = ProjecturedKernel.OperationModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("../../../source/platform/focus/FocusModule.jl")

end # module ProjecturedFocus
