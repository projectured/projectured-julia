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
const EventModule = ProjecturedKernel.EventModule
const GestureModule = ProjecturedKernel.GestureModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule
const EventModule = ProjecturedKernel.EventModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const TextModule = ProjecturedText.TextModule
const TextModule = ProjecturedText.TextModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const ScreenModule = ProjecturedScreen.ScreenModule

include("../../../source/platform/gesturehelp/GestureHelpModule.jl")

end # module ProjecturedGestureHelp
