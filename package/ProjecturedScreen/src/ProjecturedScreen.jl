"""
    ProjecturedScreen

The window model: the screen document with its windows, the projection that
lifts open, close, resize and defocus operations from below, and the identity
projection over the window tree.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedScreen

using ProjecturedCollection
# The trackers that `make_tracking_screen` puts around a screen.
using ProjecturedGestureTracking
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedMouseTargetTracking
using ProjecturedPrimitive
# Already in this package's closure through ProjecturedGraphics; named directly
# because `WindowScene.jl` uses its combinators.
using ProjecturedProjection

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const BackendModule = ProjecturedKernel.BackendModule
const EditorModule = ProjecturedKernel.EditorModule
const FaultModule = ProjecturedKernel.FaultModule
const FeedModule = ProjecturedKernel.FeedModule
const GestureTrackingModule = ProjecturedGestureTracking.GestureTrackingModule
const MouseTargetTrackingModule = ProjecturedMouseTargetTracking.MouseTargetTrackingModule

include("../../../source/platform/screen/ScreenModule.jl")
# One window on one document, for a program rather than for the gallery.

end # module ProjecturedScreen
