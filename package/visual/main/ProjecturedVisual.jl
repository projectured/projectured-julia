"""
    ProjecturedVisual

The rendering substrate. The package owns no source file any more: each of its
slices is now a package of its own, and this module is a transitional
aggregator that binds them under the names its consumers still use. It
disappears at step 5 of
[the splice plan](plan/pending/splice-base-and-visual-packages.md).

The twenty packages it aggregates: Style, Component, Focus, Plot, Graphics,
Screen, Layout, Text, Widget, Syntax, Pane, Clipboard, Tooltip, Inspector,
GestureHelp, GestureLog, FileFormat, NaturalProjection, Console and Pdf.

It also re-aliases the substrate that came out of base, and the kernel, under
the names its consumers use. Those aliases stay until the consumers name each
package directly.
"""
module ProjecturedVisual

using ProjecturedKernel
using ProjecturedConsole
using ProjecturedPdf
using ProjecturedCollection
using ProjecturedDomain
using ProjecturedDragging
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedReflection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedComponent
using ProjecturedFocus
using ProjecturedPlot
using ProjecturedGraphics
using ProjecturedScreen
using ProjecturedLayout
using ProjecturedText
using ProjecturedWidget
using ProjecturedSyntax
using ProjecturedPane
using ProjecturedClipboard
using ProjecturedTooltip
using ProjecturedInspector
using ProjecturedGestureHelp
using ProjecturedGestureLog
using ProjecturedFileFormat
using ProjecturedNaturalProjection

# ── Aliases of the packages this one builds on, and of the packages it was
# ── spliced into ──────────────────────────────────────────────────────────
# Some aliases carry a second, deprecated name (e.g. DocumentApiModule,
# BackendApiModule) so files that still use it keep resolving to the canonical
# module.
const CellModule = ProjecturedKernel.CellModule
const CellStructModule = ProjecturedKernel.CellStructModule
const DocumentModule = ProjecturedKernel.DocumentModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const ReferenceApiModule = ProjecturedKernel.ReferenceModule
const SelectionModule = ProjecturedKernel.SelectionModule
const SelectionApiModule = ProjecturedKernel.SelectionModule
const ProjectionReferenceStepModule = ProjecturedKernel.ProjectionReferenceStepModule
const ProjectionReferenceStepApiModule = ProjecturedKernel.ProjectionReferenceStepModule
# PointReferenceStepModule is defined locally by this package's graphics slice
# (`include("graphics/PointReferenceStep.jl")` below).
const OperationModule = ProjecturedKernel.OperationModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const BackendModule = ProjecturedKernel.BackendModule
const BackendApiModule = ProjecturedKernel.BackendModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const CollectionModule = ProjecturedCollection.CollectionModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const DocumentCoreModule = ProjecturedDomain.DocumentCoreModule
const DomainModule = ProjecturedDomain.DomainModule
const BoundedSyncModule = ProjecturedReflection.BoundedSyncModule
const DocumentReflectionModule = ProjecturedReflection.DocumentReflectionModule
const BinarySerializationModule = ProjecturedSerialization.BinarySerializationModule
const FileProjectModule = ProjecturedSerialization.FileProjectModule
# ScreenDocumentModule is local to this package (screen slice); no alias.
const CopyingProjectionModule = ProjecturedProjection.CopyingProjectionModule
# MoveRangeOperation — the identity-preserving relocation of CellVector elements
# the pane slice moves a tab with.
const DraggingProjectionModule = ProjecturedDragging.DraggingProjectionModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
# The concrete generic + higher-order projections live in ProjecturedProjection.
const IdentityProjectionModule = ProjecturedProjection.IdentityProjectionModule
const TypeDispatchingProjectionModule = ProjecturedProjection.TypeDispatchingProjectionModule
const PredicateDispatchingProjectionModule = ProjecturedProjection.PredicateDispatchingProjectionModule
const ReferenceDispatchingProjectionModule = ProjecturedProjection.ReferenceDispatchingProjectionModule
const ChainingProjectionModule = ProjecturedProjection.ChainingProjectionModule
const NestingProjectionModule = ProjecturedProjection.NestingProjectionModule
const RecursiveProjectionModule = ProjecturedProjection.RecursiveProjectionModule
const SwitchingProjectionModule = ProjecturedProjection.SwitchingProjectionModule
const WindowInputUnwrappingProjectionModule = ProjecturedProjection.WindowInputUnwrappingProjectionModule
const FocusingProjectionModule = ProjecturedProjection.FocusingProjectionModule
const ReversingProjectionModule = ProjecturedProjection.ReversingProjectionModule
const ConstantProjectionModule = ProjecturedProjection.ConstantProjectionModule
const DeviceModule = ProjecturedKernel.DeviceModule
const PerformanceCounterModule = ProjecturedKernel.PerformanceCounterModule
const ClockModule = ProjecturedKernel.ClockModule
const LlmModule = ProjecturedKernel.LlmModule
const ToolModule = ProjecturedKernel.ToolModule
const AgentServerModule = ProjecturedKernel.AgentServerModule
const AgentModule = ProjecturedKernel.AgentModule
# The document-shaped projections the visual bridges use (Sorting is imported
# from CollectionToSyntax indirectly, but exposing it costs nothing).
const SortingProjectionModule = ProjecturedProjection.SortingProjectionModule
const FilteringProjectionModule = ProjecturedProjection.FilteringProjectionModule
const SearchingProjectionModule = ProjecturedProjection.SearchingProjectionModule
# WindowManagingProjectionModule is local to this package (screen slice); no alias.
# The aliases of the packages this one was spliced into follow.
const ConsoleBackendModule = ProjecturedConsole.ConsoleBackendModule
const PdfBackendModule = ProjecturedPdf.PdfBackendModule
const NaturalProjectionModule = ProjecturedNaturalProjection.NaturalProjectionModule
const NaturalRegistryModule = ProjecturedNaturalProjection.NaturalRegistryModule
const DocumentFileModule = ProjecturedFileFormat.DocumentFileModule
const EmbedToSyntaxModule = ProjecturedFileFormat.EmbedToSyntaxModule
const NaturalFormatModule = ProjecturedFileFormat.NaturalFormatModule
const GestureLogModule = ProjecturedGestureLog.GestureLogModule
const GestureLogOverlayProjectionModule = ProjecturedGestureLog.GestureLogOverlayProjectionModule
const GestureLogRecordingProjectionModule = ProjecturedGestureLog.GestureLogRecordingProjectionModule
const GestureLogToSyntaxModule = ProjecturedGestureLog.GestureLogToSyntaxModule
const CommandPaletteModule = ProjecturedGestureHelp.CommandPaletteModule
const CommandPaletteDecoratorProjectionModule = ProjecturedGestureHelp.CommandPaletteDecoratorProjectionModule
const CommandPaletteToSyntaxModule = ProjecturedGestureHelp.CommandPaletteToSyntaxModule
const GestureHelpDecoratorProjectionModule = ProjecturedGestureHelp.GestureHelpDecoratorProjectionModule
const GestureMapModule = ProjecturedGestureHelp.GestureMapModule
const GestureMapToSyntaxModule = ProjecturedGestureHelp.GestureMapToSyntaxModule
const HoverProbeProjectionModule = ProjecturedInspector.HoverProbeProjectionModule
const ReferenceInspectorDocumentModule = ProjecturedInspector.ReferenceInspectorDocumentModule
const ReferenceInspectorToTextModule = ProjecturedInspector.ReferenceInspectorToTextModule
const TooltipDocumentModule = ProjecturedTooltip.TooltipDocumentModule
const TooltipDecoratorProjectionModule = ProjecturedTooltip.TooltipDecoratorProjectionModule
const ClipboardModule = ProjecturedClipboard.ClipboardModule
const ClipboardToAnyProjectionModule = ProjecturedClipboard.ClipboardToAnyProjectionModule
const OsClipboardModule = ProjecturedClipboard.OsClipboardModule
const PaneModule = ProjecturedPane.PaneModule
const PaneGeometryModule = ProjecturedPane.PaneGeometryModule
const PaneGesturesModule = ProjecturedPane.PaneGesturesModule
const PaneSurgeryModule = ProjecturedPane.PaneSurgeryModule
const PaneToWidgetModule = ProjecturedPane.PaneToWidgetModule
const CollectionToSyntaxModule = ProjecturedSyntax.CollectionToSyntaxModule
const DocumentInsertionToSyntaxModule = ProjecturedSyntax.DocumentInsertionToSyntaxModule
const ObjectToSyntaxModule = ProjecturedSyntax.ObjectToSyntaxModule
const PrimitiveToSyntaxModule = ProjecturedSyntax.PrimitiveToSyntaxModule
const SyntaxModule = ProjecturedSyntax.SyntaxModule
const SyntaxToTextModule = ProjecturedSyntax.SyntaxToTextModule
const CellTableToWidgetTableModule = ProjecturedWidget.CellTableToWidgetTableModule
const ObjectToWidgetModule = ProjecturedWidget.ObjectToWidgetModule
const ProjectionConfiguringProjectionModule = ProjecturedWidget.ProjectionConfiguringProjectionModule
const ReflectionToWidgetModule = ProjecturedWidget.ReflectionToWidgetModule
const WidgetModule = ProjecturedWidget.WidgetModule
const WidgetHoverTrackingProjectionModule = ProjecturedWidget.WidgetHoverTrackingProjectionModule
const WidgetPopupResolverProjectionModule = ProjecturedWidget.WidgetPopupResolverProjectionModule
const WidgetToGraphicsModule = ProjecturedWidget.WidgetToGraphicsModule
const TextLineNumberingModule = ProjecturedText.TextLineNumberingModule
const PrimitiveToTextModule = ProjecturedText.PrimitiveToTextModule
const ReferenceToTextModule = ProjecturedText.ReferenceToTextModule
const SelectionInvertingModule = ProjecturedText.SelectionInvertingModule
const TextModule = ProjecturedText.TextModule
const TextColumnReferenceStepModule = ProjecturedText.TextColumnReferenceStepModule
const TextFilteringModule = ProjecturedText.TextFilteringModule
const TextFirstLineModule = ProjecturedText.TextFirstLineModule
const TextHighlightingModule = ProjecturedText.TextHighlightingModule
const TextRangeReferenceStepModule = ProjecturedText.TextRangeReferenceStepModule
const TextSpanReferenceStepModule = ProjecturedText.TextSpanReferenceStepModule
const TextToGraphicsModule = ProjecturedText.TextToGraphicsModule
const TextToStringModule = ProjecturedText.TextToStringModule
const WordWrappingModule = ProjecturedText.WordWrappingModule
const CollectionToLayoutModule = ProjecturedLayout.CollectionToLayoutModule
const ConstraintSolverModule = ProjecturedLayout.ConstraintSolverModule
const LayoutModule = ProjecturedLayout.LayoutModule
const LayoutToGraphicsModule = ProjecturedLayout.LayoutToGraphicsModule
const ScreenDocumentModule = ProjecturedScreen.ScreenDocumentModule
const ScreenToScreenModule = ProjecturedScreen.ScreenToScreenModule
const WindowManagingProjectionModule = ProjecturedScreen.WindowManagingProjectionModule
const GraphicsModule = ProjecturedGraphics.GraphicsModule
const GraphicsCachingModule = ProjecturedGraphics.GraphicsCachingModule
const PointReferenceStepModule = ProjecturedGraphics.PointReferenceStepModule
const PlotGeometryModule = ProjecturedPlot.PlotGeometryModule
const PlotStyleModule = ProjecturedPlot.PlotStyleModule
const FocusModule = ProjecturedFocus.FocusModule
const ComponentModule = ProjecturedComponent.ComponentModule
const ColorModule = ProjecturedStyle.ColorModule
const FontModule = ProjecturedStyle.FontModule
const GeometryModule = ProjecturedStyle.GeometryModule
const ImageModule = ProjecturedStyle.ImageModule
const StyleStrokeModule = ProjecturedStyle.StyleStrokeModule
const StyleTextModule = ProjecturedStyle.StyleTextModule
const TrueTypeModule = ProjecturedStyle.TrueTypeModule

end # module ProjecturedVisual
