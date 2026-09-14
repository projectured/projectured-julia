"""
    ProjecturedWidget

The user-interface widget system: the widget documents, the canvas
renderer, the reflection-driven form, and the decorators that transform a
widget tree.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedWidget

using ProjecturedCollection
using ProjecturedFocus
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedText

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const SelectionModule = ProjecturedKernel.SelectionModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const FocusModule = ProjecturedFocus.FocusModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const StyleModule = ProjecturedStyle.StyleModule
const ClockModule = ProjecturedKernel.ClockModule
const IntentModule = ProjecturedKernel.IntentModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const StyleModule = ProjecturedStyle.StyleModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const StyleModule = ProjecturedStyle.StyleModule
const StyleModule = ProjecturedStyle.StyleModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const OperationModule = ProjecturedKernel.OperationModule
const ScreenModule = ProjecturedScreen.ScreenModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const ProjectionAlgebraModule = ProjecturedProjection.ProjectionAlgebraModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const LayoutModule = ProjecturedLayout.LayoutModule
const LayoutModule = ProjecturedLayout.LayoutModule
const TextModule = ProjecturedText.TextModule

include("../../../source/widget/WidgetDocument.jl")

end # module ProjecturedWidget
