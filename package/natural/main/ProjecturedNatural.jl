"""
    ProjecturedNatural

Render any document, from a registry. The registry holds no entry of its
own: each domain registers its own row from a file it already has, so the
renderer never names a domain.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedNatural

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedDomain
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedText
using ProjecturedWidget

const FontModule = ProjecturedStyle.FontModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const WidgetToGraphicsModule = ProjecturedWidget.WidgetToGraphicsModule
const LayoutToGraphicsModule = ProjecturedLayout.LayoutToGraphicsModule
const CollectionToLayoutModule = ProjecturedLayout.CollectionToLayoutModule
const CollectionModule = ProjecturedCollection.CollectionModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const WordWrappingModule = ProjecturedText.WordWrappingModule
const TextModule = ProjecturedText.TextModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const ColorModule = ProjecturedStyle.ColorModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule

include("../../../source/natural/NaturalRegistry.jl")
include("../../../source/natural/NaturalProjection.jl")

end # module ProjecturedNatural
