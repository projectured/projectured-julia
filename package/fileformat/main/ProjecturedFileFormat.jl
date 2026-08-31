"""
    ProjecturedFileFormat

Natural text input and output: the format renderer, the document file entry
point, and the embed rules that splice one file's document into another.
Each domain registers its own seams.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedFileFormat

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedNatural
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget

const NaturalRegistryModule = ProjecturedNatural.NaturalRegistryModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const DocumentModule = ProjecturedKernel.DocumentModule
const OperationModule = ProjecturedKernel.OperationModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const TextToStringModule = ProjecturedText.TextToStringModule
const BinarySerializationModule = ProjecturedSerialization.BinarySerializationModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const GeometryModule = ProjecturedStyle.GeometryModule
const LayoutModule = ProjecturedLayout.LayoutModule
const WidgetModule = ProjecturedWidget.WidgetModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const FileProjectModule = ProjecturedSerialization.FileProjectModule

include("NaturalFormat.jl")
include("DocumentFile.jl")
include("EmbedToSyntax.jl")

# An embed draws as what it embeds, and the two rows that say so are this
# package's rather than the renderer's: a stub and a file document are its
# documents. Registered on load, from here, because Julia calls `__init__` on a
# package's top-level module only.
#
# The bare rows go to the to-syntax table, which the fabric consumes. The card
# rows go to the to-graphics table, because a card is a widget and belongs in a
# to-graphics row — and only there: the save path goes through the bare ones and
# stays by-marker.
function __init__()
    NaturalRegistryModule.register_natural_syntax!(
        FileProjectModule.ReferenceStub => EmbedToSyntaxModule.ReferenceStubToSyntax(),
        FileProjectModule.FileDocument  => EmbedToSyntaxModule.FileDocumentToSyntax())
    NaturalRegistryModule.register_natural_graphics!(:fileformat, (; measure) -> Pair{Type,Any}[
        FileProjectModule.ReferenceStub =>
            EmbedToSyntaxModule.ReferenceStubToSyntax(unforced = :prose, wrap = :card),
        FileProjectModule.FileDocument =>
            EmbedToSyntaxModule.FileDocumentToSyntax(unforced = :prose, wrap = :card)])
    nothing
end

end # module ProjecturedFileFormat
