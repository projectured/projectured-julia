"""
    ProjecturedDragging

The `DraggingState` reorder wrapper document and the press-drag-drop reader
over it. The reader emits a `MoveRangeOperation` that relocates raw cells
within a `CellVector` and keeps their identity.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedDragging

using ProjecturedCollection
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule

include("../../../source/dragging/Dragging.jl")
include("../../../source/dragging/DraggingProjection.jl")

end # module ProjecturedDragging
