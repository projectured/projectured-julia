"""
    ProjecturedGestureTracking

The gesture tracking projection and its state document: the click with its
count, the key chord and the mouse dwell, recognized from the events of the
devices.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedGestureTracking

using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule

include("../../../source/gesturetracking/GestureTrackingModule.jl")

end # module ProjecturedGestureTracking
