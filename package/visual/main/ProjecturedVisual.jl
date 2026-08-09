"""
    ProjecturedVisual

The rendering substrate — layered between `ProjecturedBase` and
`ProjecturedDomain` (kernel ← base ← visual ← domain). Owns everything about
*how documents become visible*: style atoms, the screen/window model, the
render-target documents (Graphics, Layout, Text, Widget, Syntax) with their
projections, and the dependency-free backends (Console, Pdf).

## Slice order

Each slice imports only slices to its left:

```
style → screen → graphics → layout → text → widget → pane → syntax →
clipboard/tooltip/inspector → backend
```

## Slice inventory

- **style/** — Color, Font, Geometry, Image, StyleText, StyleStroke: pure
  value types every visual thing shares.
- **screen/** — ScreenDocument (windows + window events/ops) + WindowManaging +
  ScreenToScreen: the window model.
- **graphics/** — Graphics + GraphicsCaching: the retained drawing target.
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

Kernel/base aliases below let files inside this package keep their relative
`..XxxModule` references unchanged.
"""
module ProjecturedVisual

using ProjecturedKernel
using ProjecturedBase

# ── Kernel + base submodule aliases ────────────────────────────────────────
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
const CollectionModule = ProjecturedBase.CollectionModule
const PrimitiveModule = ProjecturedBase.PrimitiveModule
const DocumentCoreModule = ProjecturedBase.DocumentCoreModule
const DomainModule = ProjecturedBase.DomainModule
const BoundedSyncModule = ProjecturedBase.BoundedSyncModule
const DocumentReflectionModule = ProjecturedBase.DocumentReflectionModule
const BinarySerializationModule = ProjecturedBase.BinarySerializationModule
# ScreenDocumentModule is local to this package (screen slice); no alias.
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
# MoveRangeOperation — the identity-preserving relocation of CellVector elements
# the pane slice moves a tab with.
const DraggingProjectionModule = ProjecturedBase.DraggingProjectionModule
const EventModule = ProjecturedKernel.EventModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
# The concrete generic + higher-order projections now live in ProjecturedBase.
const IdentityProjectionModule = ProjecturedBase.IdentityProjectionModule
const TypeDispatchingProjectionModule = ProjecturedBase.TypeDispatchingProjectionModule
const PredicateDispatchingProjectionModule = ProjecturedBase.PredicateDispatchingProjectionModule
const ReferenceDispatchingProjectionModule = ProjecturedBase.ReferenceDispatchingProjectionModule
const ChainingProjectionModule = ProjecturedBase.ChainingProjectionModule
const NestingProjectionModule = ProjecturedBase.NestingProjectionModule
const RecursiveProjectionModule = ProjecturedBase.RecursiveProjectionModule
const SwitchingProjectionModule = ProjecturedBase.SwitchingProjectionModule
const WindowInputUnwrappingProjectionModule = ProjecturedBase.WindowInputUnwrappingProjectionModule
const FocusingProjectionModule = ProjecturedBase.FocusingProjectionModule
const ReversingProjectionModule = ProjecturedBase.ReversingProjectionModule
const ConstantProjectionModule = ProjecturedBase.ConstantProjectionModule
const DeviceModule = ProjecturedKernel.DeviceModule
const PerformanceCounterModule = ProjecturedKernel.PerformanceCounterModule
const ClockModule = ProjecturedKernel.ClockModule
const LlmModule = ProjecturedKernel.LlmModule
const ToolModule = ProjecturedKernel.ToolModule
const AgentServerModule = ProjecturedKernel.AgentServerModule
const AgentModule = ProjecturedKernel.AgentModule
# Base's document-shaped projections used by visual bridges (Sorting is
# imported from CollectionToSyntax indirectly, but exposing it costs nothing).
const SortingProjectionModule = ProjecturedBase.SortingProjectionModule
const FilteringProjectionModule = ProjecturedBase.FilteringProjectionModule
const SearchingProjectionModule = ProjecturedBase.SearchingProjectionModule
# WindowManagingProjectionModule is local to this package (screen slice); no alias.

# ── Slice 1 — style (pure value types every visual thing shares) ─────────
# Load order: Color and Font first (no forward references); Geometry, Image,
# StyleStroke, StyleText follow. StyleText imports Font + Color; StyleStroke
# imports Color.
include("style/Color.jl")
include("style/Font.jl")
# TrueType parser + SDL-free measurer (truetype_measure_text). Needs FontModule
# (StyleFont, font_logical_size), so it follows Font.jl; the PDF/web backends and
# the projection examples all reach their text metrics through it.
include("style/TrueType.jl")
include("style/Geometry.jl")
include("style/Image.jl")
include("style/StyleStroke.jl")
include("style/StyleText.jl")

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
# bridges a base CellVector into a layout container. LayoutToGraphics is
# deferred to load after widget/ (see below).
include("layout/Layout.jl")
include("layout/ConstraintSolver.jl")
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
# LayoutToGraphics loads after widget/ because it imports WidgetModule's
# focus-path helpers (first_focusable_path, last_focusable_path,
# _next_focusable_in), so it precedes the widget files that import it
# (WidgetPopupResolver).
include("layout/LayoutToGraphics.jl")
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

# ── Slice — fileformat (natural text I/O + the document-file entry point) ───
# NaturalFormat renders a document to text via the domain's ToSyntax + the shared
# SyntaxToText → TextToString tail (so it lives here, not base); DocumentFile
# bridges it with base's binary serializer. Domains register the per-domain seams
# (natural_syntax_projection / natural_extension / parse_natural / new_document_seed).
include("fileformat/NaturalFormat.jl")
include("fileformat/DocumentFile.jl")

# ── Slice — naturalprojection (the render-anything dispatch tables) ─────────
# The two tables the natural renderer is built from. They hold no entry of
# their own: each domain registers its own row from a file it already has, so
# the renderer never names a domain. Depends on nothing, so it can sit anywhere
# a domain file can reach.
include("naturalprojection/NaturalRegistry.jl")

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
