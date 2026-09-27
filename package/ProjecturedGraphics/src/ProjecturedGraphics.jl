"""
    ProjecturedGraphics

The retained drawing target: text, rectangles, canvases, viewports, images
and fences, the pixel-coordinate reference step, and the identity-stable
cache over the whole tree.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedGraphics

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedStyle

const CellModule = ProjecturedKernel.CellModule
const CellStructModule = ProjecturedKernel.CellStructModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const StyleModule = ProjecturedStyle.StyleModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const IoMapModule = ProjecturedKernel.IoMapModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule

const GestureModule = ProjecturedKernel.GestureModule
include("../../../source/graphics/GraphicsModule.jl")

end # module ProjecturedGraphics
