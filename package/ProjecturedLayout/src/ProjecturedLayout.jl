"""
    ProjecturedLayout

Spatial arrangement: the container documents, the constraint solver, the
renderer that draws a laid-out tree onto a canvas, and the bridge from a
collection into a container.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedLayout

using ProjecturedCollection
using ProjecturedFocus
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedProjection

const CellModule = ProjecturedKernel.CellModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const PointReferenceStepModule = ProjecturedGraphics.PointReferenceStepModule
const OperationModule = ProjecturedKernel.OperationModule
const FocusModule = ProjecturedFocus.FocusModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ProjectionModule = ProjecturedKernel.ProjectionModule

include("../../../source/layout/LayoutDocument.jl")
include("../../../source/layout/ConstraintSolver.jl")
include("../../../source/layout/LayoutToGraphics.jl")
include("../../../source/layout/CollectionToLayout.jl")

end # module ProjecturedLayout
