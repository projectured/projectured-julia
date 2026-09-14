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
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const OperationModule = ProjecturedKernel.OperationModule
const FocusModule = ProjecturedFocus.FocusModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionModule = ProjecturedKernel.ProjectionModule

include("../../../source/layout/LayoutDocument.jl")

end # module ProjecturedLayout
