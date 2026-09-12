"""
    ProjecturedPane

The pane tree, its surgery, its geometry, its gestures, and its projection
onto split and tabbed panes: the generic way to organize documents on the
screen.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedPane

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedDragging
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedWidget

const CellModule = ProjecturedKernel.CellModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const DraggingProjectionModule = ProjecturedDragging.DraggingProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const EventModule = ProjecturedKernel.EventModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const WidgetModule = ProjecturedWidget.WidgetModule
const LayoutModule = ProjecturedLayout.LayoutModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule

include("../../../source/pane/PaneDocument.jl")
include("../../../source/pane/PaneSurgery.jl")
include("../../../source/pane/PaneGeometry.jl")
include("../../../source/pane/PaneProgram.jl")
include("../../../source/pane/PaneGestures.jl")
include("../../../source/pane/PaneToWidget.jl")

end # module ProjecturedPane
