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
const DocumentApiModule = ProjecturedKernel.DocumentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const GeometryModule = ProjecturedStyle.GeometryModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const CopyingProjectionModule = ProjecturedProjection.CopyingProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PredicateDispatchingProjectionModule = ProjecturedProjection.PredicateDispatchingProjectionModule
const IdentityProjectionModule = ProjecturedProjection.IdentityProjectionModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule

include("../../../source/graphics/PointReferenceStep.jl")
include("../../../source/graphics/GraphicsDocument.jl")
include("../../../source/graphics/GraphicsCaching.jl")

end # module ProjecturedGraphics
