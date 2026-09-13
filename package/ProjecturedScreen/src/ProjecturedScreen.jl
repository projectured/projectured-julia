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
# Already in this package's closure through ProjecturedGraphics; named directly
# because `WindowScene.jl` uses its combinators.
using ProjecturedProjection

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const BackendModule = ProjecturedKernel.BackendModule
const EditorModule = ProjecturedKernel.EditorModule

include("../../../source/screen/ScreenDocument.jl")
include("../../../source/screen/WindowManaging.jl")
include("../../../source/screen/ScreenToScreen.jl")
# One window on one document, for a program rather than for the gallery.
include("../../../source/screen/WindowScene.jl")

end # module ProjecturedScreen
