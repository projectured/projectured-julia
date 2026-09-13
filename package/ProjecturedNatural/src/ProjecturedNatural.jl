"""
    ProjecturedNatural

What a document's natural notation is, and what it looks like.

`NaturalNotation.jl` holds the API: a notation is a rung on the ladder
`domain → syntax → text → graphics`, a domain declares the rung it starts at, and
rungs compose. `NaturalProjection.jl` builds the renderer from what is declared.

The registry holds no entry of its own: each domain registers its own row from a
file it already has, so the renderer never names a domain.

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

const StyleModule = ProjecturedStyle.StyleModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const WidgetToGraphicsModule = ProjecturedWidget.WidgetToGraphicsModule
const LayoutModule = ProjecturedLayout.LayoutModule
const LayoutModule = ProjecturedLayout.LayoutModule
const CollectionModule = ProjecturedCollection.CollectionModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const WordWrappingModule = ProjecturedText.WordWrappingModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const DomainModule = ProjecturedDomain.DomainModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextToStringModule = ProjecturedText.TextToStringModule

include("../../../source/natural/NaturalNotation.jl")

# The two rungs this package can supply itself, because it names the text
# package. `syntax → text` belongs to whoever can supply it, and is registered
# from outside — see `NaturalModule`.
#
# Prose is registered here for the same reason. A `TextDocument` IS text, so its
# own rung is the identity, and it reaches a string and a canvas through the two
# rungs above. The renderer keeps a `TextDocument` row of its own all the same:
# that row carries the `wrap` option, which is a rendering choice and not part of
# what the document is.
function __init__()
    NaturalModule.register_natural_rung!(:text, :graphics,
        (; measure) -> ProjecturedText.TextToGraphicsModule.TextToGraphics(measure = measure))
    NaturalModule.register_natural_rung!(:text, :string,
        (; measure) -> ProjecturedText.TextToStringModule.TextToString())
    NaturalModule.register_natural_notation!(
        ProjecturedText.TextModule.TextDocument, :text,
        () -> ProjecturedProjection.IdentityProjectionModule.IdentityProjection())
    nothing
end

end # module ProjecturedNatural
