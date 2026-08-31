"""
    ProjecturedGestureHelp

What can I press here: the gesture map document, the command palette, their
syntax printers, and the two decorators that put them on the screen.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedGestureHelp

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const IntentModule = ProjecturedKernel.IntentModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const WordWrappingModule = ProjecturedText.WordWrappingModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const ScreenDocumentModule = ProjecturedScreen.ScreenDocumentModule

include("../../../source/gesturehelp/GestureMap.jl")
include("../../../source/gesturehelp/CommandPalette.jl")
include("../../../source/gesturehelp/GestureMapToSyntax.jl")
include("../../../source/gesturehelp/CommandPaletteToSyntax.jl")
include("../../../source/gesturehelp/CommandPaletteDecorator.jl")
include("../../../source/gesturehelp/GestureHelpDecorator.jl")

end # module ProjecturedGestureHelp
