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
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedPrimitive

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const PointReferenceStepModule = ProjecturedGraphics.PointReferenceStepModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule

include("ScreenDocument.jl")
include("WindowManaging.jl")
include("ScreenToScreen.jl")

end # module ProjecturedScreen
