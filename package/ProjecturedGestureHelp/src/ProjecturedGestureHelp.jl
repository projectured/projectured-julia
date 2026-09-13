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
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
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
const ScreenModule = ProjecturedScreen.ScreenModule

include("../../../source/gesturehelp/GestureMap.jl")

end # module ProjecturedGestureHelp
