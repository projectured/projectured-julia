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
const ColorModule = ProjecturedStyle.ColorModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const GeometryModule = ProjecturedStyle.GeometryModule
const ClockModule = ProjecturedKernel.ClockModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IntentModule = ProjecturedKernel.IntentModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ImageModule = ProjecturedStyle.ImageModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const FontModule = ProjecturedStyle.FontModule
const StyleStrokeModule = ProjecturedStyle.StyleStrokeModule
const IoMapModule = ProjecturedKernel.IoMapModule
const EventModule = ProjecturedKernel.EventModule
const OperationModule = ProjecturedKernel.OperationModule
const ScreenDocumentModule = ProjecturedScreen.ScreenDocumentModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const PointReferenceStepModule = ProjecturedGraphics.PointReferenceStepModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const LayoutModule = ProjecturedLayout.LayoutModule
const LayoutToGraphicsModule = ProjecturedLayout.LayoutToGraphicsModule
const TextModule = ProjecturedText.TextModule

include("../../../source/widget/WidgetDocument.jl")
include("../../../source/widget/WidgetToGraphics.jl")
include("../../../source/widget/ObjectToWidget.jl")
include("../../../source/widget/ObjectFieldToWidget.jl")
include("../../../source/widget/CellTableToWidgetTable.jl")
include("../../../source/widget/WidgetHoverTracking.jl")
include("../../../source/widget/ProjectionConfiguring.jl")
include("../../../source/widget/WidgetPopupResolver.jl")

end # module ProjecturedWidget
