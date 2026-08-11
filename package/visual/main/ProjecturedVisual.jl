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

# ── Slice 2 — screen (the window model + its management) ────────────────
# ScreenDocument holds a list of WindowDocument (windows + their events/ops).
# WindowManagingProjection wraps a projection that consumes ScreenDocument
# input, applying open/close/resize/defocus operations lifted from below.
# Window things are visual per the architecture rules (only the Display device
# and display-size seam stay in the kernel, as the interface the editor writes
# to). The couple travels together: WindowManaging references ScreenDocument's
# types.
include("screen/ScreenDocument.jl")
include("screen/WindowManaging.jl")
# PointReferenceStep is the graphics-domain reference step (pixel coordinates
# relative to an element); it registers its own `.point(x, y)` DSL entries
# with the kernel's reference DSL. Loaded here — before ScreenToScreen — so
# that ScreenToScreen can `import ..PointReferenceStepModule: PointReferenceStep`.
# (PointReferenceStep depends only on DocumentModule + ReferenceModule, both
# kernel constants already in scope; no graphics types are needed.)
include("graphics/PointReferenceStep.jl")
# ScreenToScreen: an identity projection over the window tree; imports only
# visual (screen) + kernel/base.
include("screen/ScreenToScreen.jl")

# ── Slice 3 — graphics (retained drawing target) ─────────────────────────
# Graphics is the drawing domain (text/rect/canvas/viewport/image/fence).
# GraphicsCaching wraps it with a caching layer for identity-stable output.
include("graphics/Graphics.jl")
include("graphics/GraphicsCaching.jl")

# ── Slice 4 — layout (spatial arrangement) ───────────────────────────────
# Layout is the container domain; ConstraintSolver is the layout algebra;
# LayoutToGraphics renders a laid-out tree onto a canvas; CollectionToLayout
# bridges a base CellVector into a layout container.
include("layout/Layout.jl")
include("layout/ConstraintSolver.jl")
include("layout/LayoutToGraphics.jl")
include("layout/CollectionToLayout.jl")

# ── Slice 5 — text (styled text + its renderings) ────────────────────────
# Text is the styled-text domain (TextBlock/TextString/TextNewline…);
# TextToGraphics/TextToString are the render endpoints; the decorators
# (LineNumbering, WordWrapping, TextFiltering, TextFirstLine,
# TextHighlighting, SelectionInverting) are Text→Text transforms;
# PrimitiveToText and ReferenceToText are the base→text and reference→text
# bridges.
# TextSpanReferenceStep / TextColumnReferenceStep / TextRangeReferenceStep — the three
# text-domain selection reference steps over the same flat character range:
# a bounding box, a column box (reserved / deferred), and the character
# cursor/selection stream, respectively. Included first in the text slice so
# every text file below can import them via `..Text<Variant>ReferenceModule`.
include("text/TextSpanReferenceStep.jl")
include("text/TextColumnReferenceStep.jl")
include("text/TextRangeReferenceStep.jl")
include("text/Text.jl")
include("text/TextToGraphics.jl")
include("text/TextToString.jl")
include("text/LineNumbering.jl")
include("text/WordWrapping.jl")
include("text/TextFiltering.jl")
include("text/TextFirstLine.jl")
include("text/TextHighlighting.jl")
include("text/SelectionInverting.jl")
include("text/PrimitiveToText.jl")
include("text/ReferenceToText.jl")

# ── Slice 6 — widget (UI widget system) ──────────────────────────────────
# Widget is the widget domain (labels, buttons, panes, menus, dropdowns…).
# WidgetToGraphics is the big canvas renderer; ObjectToWidget is the
# reflection-driven form for
# Cell-field structs. The decorators (WidgetHoverTracking,
# ProjectionConfiguring, WidgetPopupResolver) transform a widget tree.
include("widget/Widget.jl")
include("widget/WidgetToGraphics.jl")
include("widget/ObjectToWidget.jl")
# ReflectionToWidget — a bounded reflected-object shadow as a WidgetTree, where a
# chevron drives the sync (requests a marker) rather than merely hiding a row.
include("widget/ReflectionToWidget.jl")
include("widget/CellTableToWidgetTable.jl")
include("widget/WidgetHoverTracking.jl")
include("widget/ProjectionConfiguring.jl")
include("widget/WidgetPopupResolver.jl")

# ── Slice 7 — pane (tab groups and splits: the screen layout) ────────────
# Pane is the layout document (PaneTree/PaneSplit/PaneGroup/PaneTab); PaneSurgery
# holds the tree edits, each of which builds a generic operation. The slice sits
# above widget/ because it projects onto WidgetSplitPane / WidgetTabbedPane.
include("pane/Pane.jl")
include("pane/PaneSurgery.jl")
include("pane/PaneGeometry.jl")
include("pane/PaneGestures.jl")
include("pane/PaneToWidget.jl")

# ── Slice 7 — syntax (tree presentation, target of every source domain) ─
# Syntax is the leaves/nodes/delimiters/indentation/collapsibles domain.
# SyntaxToText flattens a syntax tree to styled text. The bridges (ObjectToSyntax,
# CollectionToSyntax, PrimitiveToSyntax) are what every source domain
# eventually funnels through.
include("syntax/Syntax.jl")
include("syntax/SyntaxToText.jl")
include("syntax/ObjectToSyntax.jl")
include("syntax/CollectionToSyntax.jl")
include("syntax/PrimitiveToSyntax.jl")
# InsertionToSyntax is the shared insert-by-typing leaf: a typed-name buffer with
# live green/red completion, and the `*Nothing` placeholder leaf beside it. Every
# domain's insertion goes through it and it names no domain, so it belongs here
# rather than in any one of them. It needs Syntax + Text + the style vocabulary,
# and base's `@domain` reflection for the candidate names.
include("syntax/InsertionToSyntax.jl")

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

# ── Slice 8 — interaction decorators (clipboard / tooltip / inspector) ───
# Domain-independent higher-order projections that decorate an arbitrary
# wrapped content: clipboard copy/cut/paste (mirrored to the OS clipboard),
# hover tooltips (driving screen windows), and the hover reference inspector.
# Moved down from the domain package — none is domain-specific: they need only
# the base document vocabulary plus visual's Text / Screen / ReferenceToText.
# Each slice depends on text/ (and screen/ for tooltip + inspector), both
# already loaded above.
#
# clipboard/: OsClipboard (host-clipboard shell-out seam), the ClipboardSlice/
# ClipboardCollection documents, and the Clipboard*ToAny projections.
include("clipboard/OsClipboard.jl")
include("clipboard/Clipboard.jl")
include("clipboard/ClipboardToAny.jl")
# tooltip/: the TooltipSource wrapper + its decorator projection (opens/closes
# screen windows via WindowManagingProjection).
include("tooltip/Tooltip.jl")
include("tooltip/TooltipDecorator.jl")
# inspector/: the ReferenceInspector document, its text rendering, and the
# HoverProbe decorator that follows the pointer with a reference-inspector
# window.
include("inspector/ReferenceInspector.jl")
include("inspector/ReferenceInspectorToText.jl")
include("inspector/HoverProbe.jl")

# ── Slice 9 — backend (dependency-free concrete backends) ───────────────
# Console renders the Text domain to an ANSI terminal; Pdf exports the
# Graphics domain as a vector PDF (SDL-free).
include("backend/Console.jl")
include("backend/Pdf.jl")

end # module ProjecturedVisual
