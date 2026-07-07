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
style → screen → graphics → layout → text → widget → syntax → backend
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
- **syntax/** — Syntax + its bridges (ObjectToSyntax, CollectionToSyntax,
  PrimitiveToSyntax) + SyntaxToText + InsertionToSyntax +
  NaturalProjection.
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
const DocumentModule = ProjecturedKernel.DocumentModule
const DocumentApiModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const GestureModule = ProjecturedKernel.GestureModule
const BackendModule = ProjecturedKernel.BackendModule
const BackendApiModule = ProjecturedKernel.BackendModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IoMapApiModule = ProjecturedKernel.IoMapApiModule
const IntentModule = ProjecturedKernel.IntentModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const CollectionModule = ProjecturedBase.CollectionModule
const PrimitiveModule = ProjecturedBase.PrimitiveModule
# ScreenDocumentModule is local to this package (screen slice); no alias.
const CopyingProjectionModule = ProjecturedBase.CopyingProjectionModule
const KeyboardModule = ProjecturedKernel.KeyboardModule
const MouseModule = ProjecturedKernel.MouseModule
const ModifiersModule = ProjecturedKernel.ModifiersModule
const EventCaseModule = ProjecturedKernel.GestureModule
const GestureBindingModule = ProjecturedKernel.GestureModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const OperationApiModule = ProjecturedKernel.OperationModule
const OperationRerootingModule = ProjecturedKernel.OperationModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule
const ReferenceBuilderModule = ProjecturedKernel.ReferenceModule
const IdentityProjectionModule = ProjecturedKernel.IdentityProjectionModule
const TypeDispatchingProjectionModule = ProjecturedKernel.TypeDispatchingProjectionModule
const PredicateDispatchingProjectionModule = ProjecturedKernel.PredicateDispatchingProjectionModule
const ReferenceDispatchingProjectionModule = ProjecturedKernel.ReferenceDispatchingProjectionModule
const ChainingProjectionModule = ProjecturedKernel.ChainingProjectionModule
const NestingProjectionModule = ProjecturedKernel.NestingProjectionModule
const RecursiveProjectionModule = ProjecturedKernel.RecursiveProjectionModule
const SwitchingProjectionModule = ProjecturedKernel.SwitchingProjectionModule
const EnvelopeUnwrappingProjectionModule = ProjecturedKernel.EnvelopeUnwrappingProjectionModule
const FocusingProjectionModule = ProjecturedKernel.FocusingProjectionModule
const ReversingProjectionModule = ProjecturedKernel.ReversingProjectionModule
const ConstantProjectionModule = ProjecturedKernel.ConstantProjectionModule
const ScreenDeviceModule = ProjecturedKernel.ScreenDeviceModule
const DisplayModule = ProjecturedKernel.DisplayModule
const DeviceApiModule = ProjecturedKernel.DeviceModule
const DeviceModule = ProjecturedKernel.DeviceModule
const PerformanceCounterModule = ProjecturedKernel.PerformanceCounterModule
const TimeModule = ProjecturedKernel.TimeModule
const LlmModule = ProjecturedKernel.LlmModule
const McpModule = ProjecturedKernel.McpModule
const ToolRegistryModule = ProjecturedKernel.ToolRegistryModule
const AgentApiModule = ProjecturedKernel.AgentModule
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
include("style/Geometry.jl")
include("style/Image.jl")
include("style/StyleStroke.jl")
include("style/StyleText.jl")

# ── Slice 2 — screen (the window model + its management) ────────────────
# ScreenDocument holds a list of WindowDocument (windows + their events/ops).
# WindowManagingProjection wraps a projection that consumes ScreenDocument
# input, applying open/close/resize/defocus operations lifted from below.
# Window things are visual per the architecture rules (only the Screen device
# and display-size seam stay in the kernel, as the interface the editor writes
# to). The couple travels together: WindowManaging references ScreenDocument's
# types.
include("screen/ScreenDocument.jl")
include("screen/WindowManaging.jl")
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
# Text is the styled-text domain (TextText/TextString/TextNewline…);
# TextToGraphics/TextToString are the render endpoints; the decorators
# (LineNumbering, WordWrapping, TextFiltering, TextFirstLine,
# TextHighlighting, SelectionInverting) are Text→Text transforms;
# PrimitiveToText and ReferenceToText are the base→text and reference→text
# bridges.
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
include("widget/WidgetHoverTracking.jl")
include("widget/ProjectionConfiguring.jl")
include("widget/WidgetPopupResolver.jl")

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

# ── Slice 8 — backend (dependency-free concrete backends) ───────────────
# Console renders the Text domain to an ANSI terminal; Pdf exports the
# Graphics domain as a vector PDF (SDL-free).
include("backend/Console.jl")
include("backend/Pdf.jl")

end # module ProjecturedVisual
