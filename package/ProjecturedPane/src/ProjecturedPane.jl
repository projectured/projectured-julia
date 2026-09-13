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
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DomainModule = ProjecturedDomain.DomainModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const DraggingModule = ProjecturedDragging.DraggingModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const EventModule = ProjecturedKernel.EventModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const WidgetModule = ProjecturedWidget.WidgetModule
const LayoutModule = ProjecturedLayout.LayoutModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule

include("../../../source/pane/PaneDocument.jl")

end # module ProjecturedPane
