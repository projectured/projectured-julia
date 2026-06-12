# Widget Domain

![Widget example](../../image/example/widget.png)

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

**Extension widgets** (printer-only for now — their readers are no-ops). Colors,
radius and spacing come entirely from the theme (see below), so they carry only
the fields they need plus `visible`/`selection`:

| Widget | Purpose |
|---|---|
| `WidgetBadge(position, content; variant)` | Pill label (`:default`/`:secondary`/`:destructive`/`:outline`) |
| `WidgetSeparator(position; orientation, length)` | Hairline divider |
| `WidgetCard(position; title, description, content, footer)` | Bordered surface with header/body/footer |
| `WidgetSwitch(position, checked)` | On/off switch (track + knob) |
| `WidgetProgress(position, value)` | Progress bar (`value ∈ [0,1]`) |
| `WidgetSlider(position, value)` | Slider (track + knob) |
| `WidgetRadioGroup(position, options; selected)` | Vertical radio options |
| `WidgetAvatar(position, initials; size)` | Circular initials avatar |
| `WidgetAlert(position, title, description; variant)` | Callout (`:default`/`:destructive`) |
| `WidgetSkeleton(position; width, height)` | Loading placeholder |
| `WidgetToggle(position, content; pressed)` | Two-state toggle button |
| `WidgetToggleGroup(position, options; selected)` | Segmented control |
| `WidgetSelect(position, value; width)` | Closed select / combobox |
| `WidgetTextarea(position, content; width, rows)` | Multi-line text surface |
| `WidgetAccordion(position, items; expanded)` | Expandable sections |
| `WidgetTable(position, headers, rows)` | Data table with hairline rows |
| `WidgetTree(position, roots)` | Indented outline / tree view |

Each has a minimal isolated example — e.g. `run_example(widget_table_example)`,
`write_image_example(widget_tree_example, "tree.png")`.

## Gallery

Every widget has a minimal isolated example, rendered below.

### Core widgets

| | | |
|---|---|---|
| **Label**<br>![](../../image/example/widget-label.png) | **Text (input)**<br>![](../../image/example/widget-text.png) | **Checkbox**<br>![](../../image/example/widget-checkbox.png) |
| **Button**<br>![](../../image/example/widget-button.png) | **Tooltip**<br>![](../../image/example/widget-tooltip.png) | **Menu item**<br>![](../../image/example/widget-menu-item.png) |
| **Menu**<br>![](../../image/example/widget-menu.png) | **Toolbar**<br>![](../../image/example/widget-toolbar.png) | **Composite**<br>![](../../image/example/widget-composite.png) |
| **Title pane**<br>![](../../image/example/widget-title-pane.png) | **Split pane**<br>![](../../image/example/widget-split-pane.png) | **Scroll bar**<br>![](../../image/example/widget-scroll-bar.png) |
| **Scroll pane**<br>![](../../image/example/widget-scroll-pane.png) | **Shell**<br>![](../../image/example/widget-shell.png) | **Tabbed pane**<br>![](../../image/example/widget-tabbed-pane.png) |

### Extension widgets

| | | |
|---|---|---|
| **Badge**<br>![](../../image/example/widget-badge.png) | **Separator**<br>![](../../image/example/widget-separator.png) | **Card**<br>![](../../image/example/widget-card.png) |
| **Switch**<br>![](../../image/example/widget-switch.png) | **Progress**<br>![](../../image/example/widget-progress.png) | **Slider**<br>![](../../image/example/widget-slider.png) |
| **Radio group**<br>![](../../image/example/widget-radio-group.png) | **Avatar**<br>![](../../image/example/widget-avatar.png) | **Alert**<br>![](../../image/example/widget-alert.png) |
| **Skeleton**<br>![](../../image/example/widget-skeleton.png) | **Toggle**<br>![](../../image/example/widget-toggle.png) | **Toggle group**<br>![](../../image/example/widget-toggle-group.png) |
| **Select**<br>![](../../image/example/widget-select.png) | **Textarea**<br>![](../../image/example/widget-textarea.png) | **Accordion**<br>![](../../image/example/widget-accordion.png) |
| **Table**<br>![](../../image/example/widget-table.png) | **Tree**<br>![](../../image/example/widget-tree.png) | |

## Theme

Widget look & feel is driven by a single `WidgetTheme` token object (a neutral
zinc palette: `background`, `foreground`, `card`, `muted`, `primary`,
`destructive`, `border`, `input`, `ring`, `radius`, …). It is the source of
truth — individual widgets should not carry their own colors. Two presets ship:
`widget_theme_light()` (the default) and `widget_theme_dark()`. Pass one to the
projection factory:

```julia
WidgetToGraphics(font; measure=sdl_measure_text, theme=widget_theme_dark())
```

The renderer leans on graphics primitives that anti-alias cleanly: `GraphicsRect`
(per-corner radius + optional `border_width`/`border_color`), `GraphicsLine`, and
`GraphicsCircle`. Offscreen `write_image` supersamples (2×) for smooth output.

## Shared visual fields

The original widgets carry seven base styling fields:

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
[the reference guide](../editor/reference.md) apply.

## When to use widgets vs. graphics

- Build user interfaces (workbenches, menus, dialogs, IDE layouts) at the
  widget level — the layer is meant for layout abstractions, not pixels.
- Custom drawing primitives (specialised visualisations, plot canvases)
  can go straight to `GraphicsCanvas`.
- A document being edited should generally not be a widget tree. Project
  through widgets only as a presentation layer; keep the source-of-truth
  document in its own semantic domain.

The Workbench domain (see [the workbench guide](workbench.md)) is the largest
example of a widget consumer in ProjecturEd.
