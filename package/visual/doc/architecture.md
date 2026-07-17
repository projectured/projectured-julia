# ProjecturedVisual — architecture

Contributor-facing guide to the internal structure of the
`ProjecturedVisual` package. `ProjecturedVisual` is the **rendering
substrate** — everything about how documents *become visible*: style
atoms, the screen/window model, the render-target documents (Graphics,
Layout, Text, Widget, Syntax) with their projections, and the two
dependency-free backends (Console, Pdf).

Sits between base and domain in the dependency chain
(`kernel ← base ← visual ← domain`). Its membership test: *"is this
about presenting/arranging/drawing?"* — anything screen-, window-,
graphics-, layout-, text-, widget-, or syntax-related lives here. The one
deliberate exception: the Screen *device* and display-size seam stay in
the kernel (`device/Screen.jl` + `backend/Display.jl`) because
they are the interface the editor writes to, not the graphics themselves.

## The 11 slices and their include order

The slices form an acyclic dependency DAG; the include list below is a
topological order of it — each slice imports only slices listed before it:

```
style → screen → graphics → layout → text → widget → syntax →
clipboard → tooltip → inspector → backend
```

`LayoutToGraphics`'s Widget focus-path helpers are slated to move down into
`layout/` as open generics, with widget/ adding methods beside its types.
Until that lands, LayoutToGraphics + WidgetToGraphics are reordered in the
include list (loaded after Widget); this is order-only, not a semantic
change.

## Per-slice guides

Four of the render-target slices have their own deep-dive guides, sitting
alongside this document in `package/visual/doc/`:

- [Text domain](text.md) — styled text spans and character-offset selection.
- [Syntax domain](syntax.md) — the generic tree presentation target.
- [Graphics domain](graphics.md) — backend-agnostic drawing primitives.
- [Widget domain](widget.md) — the UI widget system and its themes.

## Slice inventory

### style/ — the pure value types

`Color.jl`, `Font.jl`, `Geometry.jl`, `Image.jl`, `StyleStroke.jl`,
`StyleText.jl`. Every visual thing shares these — a `Color` value, a
`Font` descriptor, a 2D `Geometry.Point`/`Size`/`Rect`. Kernel-only
imports (Cell + Document + Reference); no visual dependencies within
the slice.

### screen/ — the window model

`ScreenDocument.jl` (multi-window document holding `WindowDocument`s +
window operations — `OpenWindowOperation`, `OpenPopupOperation`,
`CloseWindowOperation`, `ResizeWindowOperation`), `WindowManaging.jl` (the
higher-order projection that wraps a projection over ScreenDocument input to
lift open/close/resize/defocus operations up from below). The couple travels
together: WindowManaging references ScreenDocument's types.

The window *events* (`WindowClose`, `WindowResize`, `WindowDefocus`,
`WindowQuit`) do **not** live here — they live with the rest of the input
vocabulary in the kernel's `EventModule`, alongside `WindowInput` (which
wraps every event with a window id): both are protocol types consumed by the
editor loop and gesture recognizer, not document concepts.

### graphics/ — the retained drawing target

`Graphics.jl` (the drawing domain: text/rect/canvas/viewport/image/
fence), `GraphicsCaching.jl` (an identity-stable caching wrapper).

### layout/ — spatial arrangement

`Layout.jl` (the container domain), `ConstraintSolver.jl` (the layout
algebra), `LayoutToGraphics.jl` (renders a laid-out tree onto a canvas
via the solver), `CollectionToLayout.jl` (bridges a base CellVector
into a layout container).

### text/ — styled text and its renderings

`Text.jl` (the styled-text domain: TextBlock/TextString/TextNewline/…),
`TextToGraphics.jl`, `TextToString.jl` (render endpoints), the
decorators (`LineNumbering`, `WordWrapping`, `TextFiltering`,
`TextFirstLine`, `TextHighlighting`, `SelectionInverting`), and the
bridges (`PrimitiveToText`, `ReferenceToText`).

### widget/ — the UI widget system

`Widget.jl` (the widget domain: labels/buttons/panes/menus/dropdowns/…),
`WidgetToGraphics.jl` (the big canvas renderer), `ObjectToWidget.jl`
(reflection-driven form),
`WidgetHoverTracking.jl`, `ProjectionConfiguring.jl`,
`WidgetPopupResolver.jl` (decorators).

### syntax/ — the tree presentation target of every source domain

`Syntax.jl` (the tree domain: leaves/nodes/delimiters/indentation/
collapsibles), `SyntaxToText.jl` (flattens to styled text — the shared
step every domain funnels through), and the reflection bridges
(`ObjectToSyntax`, `CollectionToSyntax`,
`PrimitiveToSyntax`).

### clipboard/ — copy/cut/paste over any content

`Clipboard.jl` (the `ClipboardSlice` / `ClipboardCollection` documents),
`OsClipboard.jl` (a stubbable shell-out seam to the host clipboard —
`xclip`/`xsel`/`wl-*`/`pb*`, degrading gracefully when absent), and
`ClipboardToAny.jl` (the `ClipboardSliceToAnyProjection` /
`ClipboardCollectionToAnyProjection` copy/cut/note/paste projections,
delegating non-clipboard gestures into the wrapped content). Domain-free:
they wrap arbitrary `content`, so nothing here is domain-specific. Imports
base `Primitive` + kernel gesture bindings + visual `Text` (for text-range
copy/paste) + base `DocumentCore` (the `DocumentNothing` cut writes).
Moved down from the domain package.

### tooltip/ — hover tooltips as screen windows

`Tooltip.jl` (the transparent `TooltipSource` wrapper) and
`TooltipDecorator.jl` (`TooltipDecoratorProjection`, whose reader runs a
show/hide state machine emitting `OpenWindowOperation` /
`CloseWindowOperation` up to `WindowManagingProjection`). Depends on the
`screen/` slice. Moved down from the domain package.

### inspector/ — the pointer-following reference inspector

`ReferenceInspector.jl` (a display document pairing a `reference` with the
`target` it points into), `ReferenceInspectorToText.jl` (renders both the
compact and human-readable forms via `ReferenceToText`), and `HoverProbe.jl`
(`HoverProbeProjection`, which on idle mouse motion reverse-projects the
pointer and drives a follower reference-inspector window). Depends on
`screen/` + `text/` + `style/`. Moved down from the domain package.

### backend/ — the dependency-free concrete backends

`Console.jl` (ANSI terminal backend rendering the Text domain — construct
`ConsoleBackend()` directly), `Pdf.jl` (SDL-free vector-PDF export of the
Graphics domain, via `write_pdf`). `TrueType.jl` holds the SDL-free
`truetype_measure_text` those and the web backend share.

## Alias preamble

Files under this package's slice folders reference kernel/base modules
via relative `..XxxModule` imports. Those resolve through the
`const XxxModule = ProjecturedKernel.XxxModule` (or
`ProjecturedBase.XxxModule`) declarations at the top of
`ProjecturedVisual.jl`. The visual guard's `alias_names(top_file)`
collector recognises them as valid dep targets even though they aren't
defined by any visual file.

## Consumers

The opt-in `Sdl`, `Web`, and `Video` packages depend on `Domain` but
primarily consume this package's Color/Font/Geometry/Graphics/Image
types plus `Pdf`/`Sdl` backend factory registrations. `Odbc` depends on
domain but reaches through to visual for `SyntaxToText`/`TextToString`
(the SQL-rendering tail).
