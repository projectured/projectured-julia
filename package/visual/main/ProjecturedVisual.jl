"""
    ProjecturedVisual

The rendering substrate. It owns everything about
*how documents become visible*: style atoms, the screen/window model, the
render-target documents (Graphics, Layout, Text, Widget, Syntax) with their
projections, and the dependency-free backends (Console, Pdf).

## Slice order

Each slice imports only slices to its left:

```
style → screen → graphics → focus → layout → text → widget → pane → syntax →
clipboard/tooltip/inspector → backend
```

## Slice inventory

- **style/** — Color, Font, Geometry, Image, StyleText, StyleStroke: pure
  value types every visual thing shares.
- **screen/** — ScreenDocument (windows + window events/ops) + WindowManaging +
  ScreenToScreen: the window model.
- **graphics/** — Graphics + GraphicsCaching: the retained drawing target.
- **focus/** — the generic focus walk and its open trait
  `is_focusable_document`: which leaf a Tab press lands on.
- **layout/** — Layout + ConstraintSolver + LayoutToGraphics +
  CollectionToLayout: spatial arrangement.
- **text/** — Text + its projections/decorators + PrimitiveToText +
  ReferenceToText.
- **widget/** — Widget + its projections + ObjectToWidget + hover/config/popup
  decorators.
- **pane/** — the pane tree (PaneTree/PaneSplit/PaneGroup/PaneTab), its
  surgery, its geometry, and its projection onto split and tabbed panes:
  the generic way to organize documents on the screen.
- **syntax/** — Syntax + its bridges (ObjectToSyntax, CollectionToSyntax,
  PrimitiveToSyntax) + SyntaxToText + InsertionToSyntax +
  NaturalProjection.
- **clipboard/** — the ClipboardSlice/ClipboardCollection documents, the
  OsClipboard shell-out seam, and the Clipboard*ToAny projections (copy/cut/
  paste over any wrapped content, mirrored to the OS clipboard).
- **tooltip/** — the TooltipSource wrapper + TooltipDecoratorProjection
  (a show/hide state machine driving screen windows).
- **inspector/** — the ReferenceInspector document, ReferenceInspectorToText,
  and the HoverProbe decorator (a pointer-following reference-inspector window).
- **backend/** — Console.jl, Pdf.jl (the dependency-free concrete backends).

The aliases below let files inside this package keep their relative
`..XxxModule` references unchanged. Each concept folder becomes a package of
its own (see plan/pending/splice-base-and-visual-packages.md); while the
splice runs, this module re-aliases what has already left.
"""
module ProjecturedVisual

using ProjecturedKernel
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

# ── Slice — gesturehelp (what can I press here, and the command palette) ─
# Domain-neutral editor features: the gesture map document, the command palette,
# their syntax printers, and the two decorators that put them on the screen.
# They print to Syntax and open windows, so they follow syntax/ and screen/.
include("gesturehelp/GestureMap.jl")
include("gesturehelp/CommandPalette.jl")
include("gesturehelp/GestureMapToSyntax.jl")
include("gesturehelp/CommandPaletteToSyntax.jl")
include("gesturehelp/CommandPaletteDecorator.jl")
include("gesturehelp/GestureHelpDecorator.jl")

# ── Slice — gesturelog (what was pressed, as a panel over anything) ──────
# The log document, its syntax printer, the recorder that decorates an arbitrary
# projection, and the overlay that draws the panel.
include("gesturelog/GestureLog.jl")
include("gesturelog/GestureLogToSyntax.jl")
include("gesturelog/GestureLogRecorder.jl")
include("gesturelog/GestureLogOverlay.jl")

# ── Slice — fileformat (natural text I/O + the document-file entry point) ───
# NaturalFormat renders a document to text via the domain's ToSyntax + the shared
# SyntaxToText → TextToString tail (so it lives here, not base); DocumentFile
# bridges it with base's binary serializer. Domains register the per-domain seams
# (natural_syntax_projection / natural_extension / parse_natural / new_document_seed).
include("fileformat/NaturalFormat.jl")
include("fileformat/DocumentFile.jl")
# EmbedToSyntax makes a cross-file embed part of the shared to-syntax fabric, so
# a document spliced in by a marker renders as itself rather than as the marker's
# text. It is neutral about the host format and belongs beside the marker and the
# file document it prints.
include("fileformat/EmbedToSyntax.jl")

# ── Slice — naturalprojection (render anything, from a registry) ────────────
# NaturalRegistry holds the two tables the renderer is built from. They hold no
# entry of their own: each domain registers its own row from a file it already
# has, so the renderer never names a domain. NaturalProjection is the renderer
# itself, so it follows every stage it splices — widget, layout, text, syntax,
# and the embed rules above.
include("naturalprojection/NaturalRegistry.jl")
include("naturalprojection/NaturalProjection.jl")

# ── Slice 9 — backend (dependency-free concrete backends) ───────────────
# Console renders the Text domain to an ANSI terminal; Pdf exports the
# Graphics domain as a vector PDF (SDL-free).
include("backend/Console.jl")
include("backend/Pdf.jl")

end # module ProjecturedVisual
