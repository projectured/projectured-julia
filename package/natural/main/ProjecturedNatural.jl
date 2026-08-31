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
using ProjecturedDomain
using ProjecturedFileFormat
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
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
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const ObjectToSyntaxModule = ProjecturedSyntax.ObjectToSyntaxModule
const CollectionToSyntaxModule = ProjecturedSyntax.CollectionToSyntaxModule
const PrimitiveToSyntaxModule = ProjecturedSyntax.PrimitiveToSyntaxModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const TextModule = ProjecturedText.TextModule
const DocumentInsertionToSyntaxModule = ProjecturedSyntax.DocumentInsertionToSyntaxModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const EmbedToSyntaxModule = ProjecturedFileFormat.EmbedToSyntaxModule
const FileProjectModule = ProjecturedSerialization.FileProjectModule

include("NaturalRegistry.jl")
include("NaturalProjection.jl")

end # module ProjecturedNatural
