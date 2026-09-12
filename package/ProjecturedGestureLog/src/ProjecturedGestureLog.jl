"""
    ProjecturedGestureLog

What was pressed: the log document, its syntax printer, the recorder that
decorates an arbitrary projection, and the overlay that draws the panel.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedGestureLog

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const CollectionModule = ProjecturedCollection.CollectionModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const OperationModule = ProjecturedKernel.OperationModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const IoMapModule = ProjecturedKernel.IoMapModule
const TextModule = ProjecturedText.TextModule
const FontModule = ProjecturedStyle.FontModule
const ColorModule = ProjecturedStyle.ColorModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const IntentModule = ProjecturedKernel.IntentModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const TrueTypeModule = ProjecturedStyle.TrueTypeModule

include("../../../source/gesturelog/GestureLogDocument.jl")
include("../../../source/gesturelog/GestureLogToSyntax.jl")
include("../../../source/gesturelog/GestureLogRecording.jl")
include("../../../source/gesturelog/GestureLogOverlay.jl")

end # module ProjecturedGestureLog
