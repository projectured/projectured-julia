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

const NaturalModule = ProjecturedNatural.NaturalModule
const NaturalModule = ProjecturedNatural.NaturalModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const DocumentModule = ProjecturedKernel.DocumentModule
const OperationModule = ProjecturedKernel.OperationModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const TextToStringModule = ProjecturedText.TextToStringModule
const SerializationModule = ProjecturedSerialization.SerializationModule
const DomainModule = ProjecturedDomain.DomainModule
const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const LayoutModule = ProjecturedLayout.LayoutModule
const WidgetModule = ProjecturedWidget.WidgetModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const SerializationModule = ProjecturedSerialization.SerializationModule

include("../../../source/fileformat/NaturalFormat.jl")
include("../../../source/fileformat/NaturalRegistration.jl")


end # module ProjecturedFileFormat
