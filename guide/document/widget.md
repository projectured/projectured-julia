# Widget Domain

The widget domain is the UI layer that sits between domain-specific projections
and the graphics domain. Widgets describe what a user interface looks like —
labels, buttons, panes, scrollbars — in a backend-agnostic way. The
`WidgetToGraphics` projection (in
[projection/primitive/WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl))
turns a tree of widgets into a `GraphicsCanvas`.

The widget module is
[program/src/document/Widget.jl](../../program/src/document/Widget.jl).

## The widget hierarchy

All widgets subtype the abstract `WidgetDocument` (which subtypes `Document`).

**Leaf widgets:**

| Widget | Purpose |
|---|---|
| `WidgetLabel(position, content)` | Static text label |
| `WidgetText(position, content)` | Editable text |
| `WidgetCheckbox(position, checked, content)` | Boolean toggle |
| `WidgetButton(position, content)` | Clickable button |
| `WidgetTooltip(position, content)` | Tooltip popup |
| `WidgetMenuItem(content)` | Menu entry |

**Compound widgets:**

| Widget | Purpose |
|---|---|
| `WidgetComposite(children)` | Generic container |
| `WidgetShell(children)` | Top-level window contents |
| `WidgetTitlePane(title, content)` | Pane with a title bar |
| `WidgetSplitPane(orientation, panes, splitter)` | Resizable split |
| `WidgetTabbedPane(tabs, active_index)` | Tab switcher |
| `WidgetScrollPane(content, x_offset, y_offset)` | Scrollable viewport |
| `WidgetScrollBar(orientation, value, min, max, page)` | Scrollbar control |
| `WidgetToolbar(children)` | Horizontal toolbar |
| `WidgetMenu(items)` | Dropdown/menu |

## Shared visual fields

Every widget carries seven base styling fields:

- `visible::Bool` — show/hide
- `margin::Inset`, `margin_color::StyleColor` — outer margin
- `border::Inset`, `border_color::StyleColor` — border
- `padding::Inset`, `padding_color::StyleColor` — inner padding

These map to nested CSS-style boxes. `Inset` (defined in
[document/Geometry.jl](../../program/src/document/Geometry.jl)) holds four
sides; helpers `inset_size`, `inset_top_left`, etc. compute derived values.
The default value is `inset_default`.

## Widget operations

Defined alongside the widget types in
[document/Widget.jl](../../program/src/document/Widget.jl):

| Operation | Effect |
|---|---|
| `HideWidgetOperation(w)` / `ShowWidgetOperation(w)` | toggle visibility |
| `ScrollWidgetOperation(scroll_pane, dx, dy)` | adjust scroll offsets |
| `SelectTabOperation(tabbed_pane, index)` | activate a tab |
| `SetScrollBarValueOperation(bar, value)` | move the scroll-bar thumb |

The `WidgetToGraphics` reader produces these in response to
`MouseClick`/`MouseScroll`, routing each through the appropriate container
via hit-testing.

## Projection to graphics

`WidgetToGraphics()` is the convenience factory that returns

```julia
RecursiveProjection(TypeDispatchingProjection(
    WidgetLabel       => WidgetLabelToGraphicsCanvas(...),
    WidgetText        => WidgetTextToGraphicsCanvas(...),
    WidgetCheckbox    => WidgetCheckboxToGraphicsCanvas(...),
    WidgetButton      => WidgetButtonToGraphicsCanvas(...),
    WidgetTooltip     => WidgetTooltipToGraphicsCanvas(...),
    WidgetMenu        => WidgetMenuToGraphicsCanvas(...),
    WidgetMenuItem    => WidgetMenuItemToGraphicsCanvas(...),
    WidgetComposite   => WidgetCompositeToGraphicsCanvas(...),
    WidgetShell       => WidgetShellToGraphicsCanvas(...),
    WidgetTitlePane   => WidgetTitlePaneToGraphicsCanvas(...),
    WidgetSplitPane   => WidgetSplitPaneToGraphicsCanvas(...),
    WidgetTabbedPane  => WidgetTabbedPaneToGraphicsCanvas(...),
    WidgetScrollPane  => WidgetScrollPaneToGraphicsCanvas(...),
    WidgetToolbar     => WidgetToolbarToGraphicsCanvas(...),
    WidgetScrollBar   => WidgetScrollBarToGraphicsCanvas(...),
))
```

Each per-widget projection takes a `font`, a backend `measure` function,
and a default foreground colour. Containers project their children
recursively via the `recursion` argument and assemble the resulting
canvases.

`WidgetScrollPaneToGraphicsViewport` is a separate composable projection
that emits a `GraphicsViewport` instead of a flat canvas — useful when the
downstream backend can clip to a viewport efficiently.

## Selection

Widgets carry a `selection::Reference` field like every other Document.
Selection paths typically descend into `content` for leaf widgets, into
`children`/`tabs`/`panes` (collections) for containers, or to specific
fields like `x_offset`/`y_offset` of a scroll pane. The standard rules in
[editor/reference.md](../editor/reference.md) apply.

## When to use widgets vs. graphics

- Build user interfaces (workbenches, menus, dialogs, IDE layouts) at the
  widget level — the layer is meant for layout abstractions, not pixels.
- Custom drawing primitives (specialised visualisations, plot canvases)
  can go straight to `GraphicsCanvas`.
- A document being edited should generally not be a widget tree. Project
  through widgets only as a presentation layer; keep the source-of-truth
  document in its own semantic domain.

The Workbench domain (see [workbench.md](workbench.md)) is the largest
example of a widget consumer in ProjecturEd.
