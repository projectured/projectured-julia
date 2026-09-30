"""
    ProjecturedMouseTargetTracking

The mouse target tracking projection and its state document: the part under the
pointer, and the crossings that its parts get by route.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedMouseTargetTracking

using ProjecturedGraphics
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule

include("../../../source/platform/mousetargettracking/MouseTargetTrackingModule.jl")

end # module ProjecturedMouseTargetTracking
