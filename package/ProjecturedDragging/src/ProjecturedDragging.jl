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
# Named for the wrapper helpers below; it is in every window binary already.
using ProjecturedProjection

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule

const GestureModule = ProjecturedKernel.GestureModule
include("../../../source/dragging/DraggingModule.jl")

end # module ProjecturedDragging
