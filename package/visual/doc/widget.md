# Widget Domain

<img width="1024" alt="Widget example" src="../../../asset/image/example/widget.png">

The widget domain is the UI layer that sits between domain-specific projections
and the graphics domain. Widgets describe what a user interface looks like —
labels, buttons, panes, scrollbars — in a backend-agnostic way. The
`WidgetToGraphics` projection (in
[projection/primitive/WidgetToGraphics.jl](../../../package/visual/main/widget/WidgetToGraphics.jl))
turns a tree of widgets into a `GraphicsCanvas`.

The widget module is
[package/visual/main/widget/Widget.jl](../../../package/visual/main/widget/Widget.jl).

## The widget hierarchy

All widgets subtype the abstract `WidgetDocument` (which subtypes `Document`).

**Leaf widgets:**

| Widget | Purpose |
|---|---|
| `WidgetLabel(position, content)` | Static text label |
| `WidgetText(position, content)` | Editable text |
| `WidgetCheckbox(position, content)` | Boolean toggle (the `content` holds the checked state/label) |
| `WidgetButton(position, size, content; action)` | Clickable button — reacts to hover/press and invokes `action` on click |
| `WidgetTooltip(position, size, content)` | Tooltip popup |
| `WidgetMenuItem(content)` | Menu entry |

**Compound widgets:**

| Widget | Purpose |
|---|---|
| `WidgetComposite(position, elements)` | Generic container |
| `WidgetShell(children)` | Top-level window contents |
| `WidgetTitlePane(title, content)` | Pane with a title bar |
| `WidgetSplitPane(orientation, elements; sizes)` | Split with drag-resizable splitters (fields `elements`/`sizes`) |
| `WidgetTabbedPane(selector_element_pairs; closable, new_tab, draggable)` | Tab switcher; a wheel over the strip scrolls it horizontally (`tab_scroll`) when the tabs overflow the pane width. The three flags add a close button per tab, a new-tab button after the last, and a grab on a button down — see [Strip reports](#strip-reports) |
| `WidgetScrollPane(content; position, size, scroll_position)` | Scrollable viewport (offset is `scroll_position`) |
| `WidgetTransformPane(content; position, size, transform)` | Zoom/pan viewport — content under an affine `transform` (Ctrl+wheel zooms, plain wheel pans) |
| `WidgetScrollBar(orientation; value, thumb_size)` | Scrollbar control (fields `value`/`thumb_size`) |
| `WidgetToolbar(elements)` | Horizontal toolbar |
| `WidgetMenu(elements)` | Dropdown/menu |

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
| `WidgetTree(position, roots)` | Indented outline / tree view; nodes carry a `WidgetTreeNode(icon, label, children)` (icon + text), or a bare `String` / `(label, children)` for icon-less trees |

Each has a minimal isolated example — e.g. `run_example(widget_table_example)`,
`write_example_image(widget_tree_example, "tree.png")`.

## Gallery

Every widget has a minimal isolated example, rendered below.

### Core widgets

| | | |
|---|---|---|
| **Label**<br><img width="122" alt="" src="../../../asset/image/example/widget-label.png"> | **Text (input)**<br><img width="110" alt="" src="../../../asset/image/example/widget-text.png"> | **Checkbox**<br><img width="18" alt="" src="../../../asset/image/example/widget-checkbox.png"> |
| **Button**<br><img width="180" alt="" src="../../../asset/image/example/widget-button.png"> | **Tooltip**<br><img width="214" alt="" src="../../../asset/image/example/widget-tooltip.png"> | **Menu item**<br><img width="47" alt="" src="../../../asset/image/example/widget-menu-item.png"> |
| **Menu**<br><img width="54" alt="" src="../../../asset/image/example/widget-menu.png"> | **Toolbar**<br><img width="304" alt="" src="../../../asset/image/example/widget-toolbar.png"> | **Composite**<br><img width="79" alt="" src="../../../asset/image/example/widget-composite.png"> |
| **Title pane**<br><img width="116" alt="" src="../../../asset/image/example/widget-title-pane.png"> | **Split pane**<br><img width="457" alt="" src="../../../asset/image/example/widget-split-pane.png"> | **Scroll bar**<br><img width="20" alt="" src="../../../asset/image/example/widget-scroll-bar.png"> |
| **Scroll pane**<br><img width="401" alt="" src="../../../asset/image/example/widget-scroll-pane.png"> | **Shell**<br><img width="600" alt="" src="../../../asset/image/example/widget-shell.png"> | **Tabbed pane**<br><img width="600" alt="" src="../../../asset/image/example/widget-tabbed-pane.png"> |

### Extension widgets

| | | |
|---|---|---|
| **Badge**<br><img width="114" alt="" src="../../../asset/image/example/widget-badge.png"> | **Separator**<br><img width="261" alt="" src="../../../asset/image/example/widget-separator.png"> | **Card**<br><img width="362" alt="" src="../../../asset/image/example/widget-card.png"> |
| **Switch**<br><img width="44" alt="" src="../../../asset/image/example/widget-switch.png"> | **Progress**<br><img width="260" alt="" src="../../../asset/image/example/widget-progress.png"> | **Slider**<br><img width="260" alt="" src="../../../asset/image/example/widget-slider.png"> |
| **Radio group**<br><img width="166" alt="" src="../../../asset/image/example/widget-radio-group.png"> | **Avatar**<br><img width="64" alt="" src="../../../asset/image/example/widget-avatar.png"> | **Alert**<br><img width="442" alt="" src="../../../asset/image/example/widget-alert.png"> |
| **Skeleton**<br><img width="260" alt="" src="../../../asset/image/example/widget-skeleton.png"> | **Toggle**<br><img width="80" alt="" src="../../../asset/image/example/widget-toggle.png"> | **Toggle group**<br><img width="260" alt="" src="../../../asset/image/example/widget-toggle-group.png"> |
| **Select**<br><img width="220" alt="" src="../../../asset/image/example/widget-select.png"> | **Textarea**<br><img width="340" alt="" src="../../../asset/image/example/widget-textarea.png"> | **Accordion**<br><img width="411" alt="" src="../../../asset/image/example/widget-accordion.png"> |
| **Table**<br><img width="505" alt="" src="../../../asset/image/example/widget-table.png"> | **Tree**<br><img width="174" alt="" src="../../../asset/image/example/widget-tree.png"> | |

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
[document/Geometry.jl](../../../package/visual/main/style/Geometry.jl)) holds four
sides; helpers `inset_size`, `inset_top_left`, etc. compute derived values.
The default value is `inset_default`.

## Interaction state

Alongside `visible`, interactive widgets carry a shared **`enabled::Bool`**
(default `true`) — the second cross-cutting interactivity flag. The convention
for it is uniform:

- **Reader gating.** A widget's `read_intent` returns `nothing` for every
  event when `w.enabled === false` (guard at the top, before any operation is
  produced). A disabled control emits no action, no edit, and no transient state
  change.
- **Muted appearance.** Its printer branches on `w.enabled === false` and renders
  with the theme's `muted` / `muted_foreground` tokens instead of its normal
  surface/foreground, and drops interaction affordances (the button's drop
  shadow, any hover/press surface).

`WidgetButton` and `WidgetCheckbox` are the reference implementations; other
interactive widgets adopt `enabled` the same way (struct field next to `visible`,
threaded through the convenience constructor, gate + muted branch).

Note that **focus is not a separate flag** — the focused widget is the *selected*
one (`selection::Reference`, see [Selection](#selection)); there is no `focused`
field.

### Transient hover / press state

`hovered` and `pressed` (today on `WidgetButton`) are **transient UI state**, not
document content — they are not serialised. The convention:

- The **reader** writes them via `ReplaceReferencedValueOperation(self, "hovered"/"pressed",
  bool)` in response to `MouseEnter`/`MouseLeave` (hover) and `MouseDown`/`MouseUp`
  (press); see [Button behavior](#button-behavior).
- The **printer** reads them to pick the surface fill (`pressed → active`, else
  `hovered → hover`, else resting), and a disabled widget ignores them entirely.

A widget that needs interactive feedback copies this field-plus-cell pattern
rather than inventing its own. Two shared helpers in
[WidgetToGraphics.jl](../../../package/visual/main/widget/WidgetToGraphics.jl)
package it so a new widget opts in with two lines: `_hover_state_op(w, evt)` maps
a `MouseEnter`/`MouseLeave` to the `hovered` write (call it from the reader), and
`_push_hover_surface!(elems, w, enabled, …)` paints a faint themed surface behind
the control while `enabled && w.hovered === true` (call it from the printer,
*before* the content so it sits underneath). `WidgetButton` and `WidgetMenuItem`
are the reference adopters — the latter gives every menu, submenu, context menu,
menu bar, and toolbar a highlight on the row under the pointer.

## Form & data widgets

The data-entry surface (Qt's `QFormLayout` / `QSpinBox` / `QListWidget` /
`QStackedWidget`) is built from two new widgets, two layout features, and a
validation hook. The gallery's **Forms** tab
([visual/example/document/Widget.jl](../../../package/visual/example/document/Widget.jl))
shows them together.

- **`WidgetSpinBox(pos, value; min, max, step, width, validator)`** — a numeric
  field with up/down steppers (the `:plus` / `:minus` icons). A click on a stepper
  emits `ReplaceReferencedValueOperation(spin, "value", clamp(value ± step, min, max))`;
  `Up`/`Down` do the same from the keyboard. The default `validator` is
  `numeric_validator()`, so typing only commits numeric text. Disabled is inert.
- **`WidgetList(pos, items; selected, width)`** — a first-class single-column
  selectable list (the sanctioned `QListWidget`; previously expressible only as a
  one-column table). A left click selects the hit row (drawing the accent
  selection band); `Up`/`Down` move the selection. An empty list is inert.
- **`FormLayout(rows; label_align=:right, …)`** — thin sugar over a two-column
  `GridLayout`: each `row` is a `(label, field)` pair of **documents** (wrap text
  labels in `WidgetLabel`). It builds `GridLayout(2; column_align=[label_align,
  :left], column_stretch=[0, 1])` — the label column hugs (uniform width = widest
  label), the field column fills. The per-column `column_align` / `column_stretch`
  are a general `GridLayout` feature (Qt-grade grids); their defaults (empty)
  reproduce the previous content-sized, single-`horizontal_align` behaviour, so
  existing grids are unchanged. The field column only stretches when a parent
  seeded an `available_width`. `FormLayout` lives in
  [layout/Layout.jl](../../../package/visual/main/layout/Layout.jl) (not Widget.jl)
  because layouts load before widgets — hence it takes pre-built label documents
  rather than wrapping strings itself.
- **`StackLayout(children; active=0)`** — `active = 0` keeps the original z-stack
  (all children overlaid); `active = i` lays out **only** child `i`, sized to it —
  the `QStackedWidget` page container. Out-of-range clamps to empty.
- **Validators** — a `validator::Any` callable on `WidgetText` (and
  `WidgetSpinBox`), consulted by the editable-text reader before a
  `ReplaceStringRangeOperation` commits: an **acceptor** `(String) -> Bool` drops
  the edit when it returns `false`. `nothing` (the default) imposes no constraint.
  The built-in `numeric_validator(; integer=false, allow_negative=true)` accepts
  digits with an optional sign / decimal point.

## Widget operations

Most widget edits are a **single-field write into a carried widget**, so the
`WidgetToGraphics` reader emits a self-contained
`ReplaceReferencedValueOperation(widget, "field", value)` (see
[operation.md](../../../package/kernel/doc/operation.md#the-generic-write-operation-replacereferencedvalue))
rather than a bespoke operation. Because the widget is carried by identity
(`document !== nothing`), the write bubbles up through every container unchanged.

| Gesture | Operation emitted |
|---|---|
| show / hide | `ReplaceReferencedValueOperation(w, "visible", true/false)` |
| enable / disable | `ReplaceReferencedValueOperation(w, "enabled", true/false)` (disabled readers emit nothing) |
| scroll wheel | `ReplaceReferencedValueOperation(scroll_pane, "scroll_position", old + Δ)` (reader reads `old`) |
| wheel over a tab strip | `ReplaceReferencedValueOperation(tabbed_pane, "tab_scroll", clamped)` — scrolls overflow tabs into view |
| Ctrl+wheel / wheel on a transform pane | `ReplaceReferencedValueOperation(transform_pane, "transform", M')` (zoom about cursor / pan) |
| Ctrl+`=`/`-`/`0` on a transform pane | `ReplaceReferencedValueOperation(transform_pane, "transform", M')` (zoom in/out / reset, about centre) |
| drag scroll-bar | `ReplaceReferencedValueOperation(bar, "value", clamped)` |
| hover / press a button | `ReplaceReferencedValueOperation(widget, "hovered"/"pressed", bool)` |

The operations that remain bespoke (genuinely not single-slot writes) are defined
alongside the widget types in
[widget/Widget.jl](../../../package/visual/main/widget/Widget.jl):

| Operation | Effect |
|---|---|
| `SelectTabOperation(tabbed_pane, index)` | event-like "tab clicked"; the workbench overloads it into a document-selection move |
| `CloseTabRequestOperation` / `NewTabRequestOperation` / `DragTabOperation` | the other three event-like strip reports — see [Strip reports](#strip-reports) |
| `StartSplitterDragOperation` / `ResizeSplitPaneOperation` / `EndSplitterDragOperation` | drag a split-pane splitter to resize the two adjacent slots |
| `InvokeActionOperation(action)` | invoke a control's `Action` — its `callback` runs (with the editor if it takes one), guarded by the action's `enabled` |

The `WidgetToGraphics` reader produces these in response to
`MousePress`/`MouseScroll`, routing each through the appropriate container
via hit-testing.

### Splitter drag-to-resize

A `WidgetSplitPane` splitter is draggable. The reader recognises a
`MouseDown(:left)` inside a splitter's gap (`thickness` plus a few pixels of
grab tolerance), then resizes the two adjacent slots on each `MouseMove` until
`MouseUp`. The drag is **stateful but the event pipeline is not**, so the
in-progress drag lives on transient cells of the pane itself:

- `active_splitter::Int` — `0`, or `k` while the splitter after slot `k` is held.
- `drag_anchor` — `nothing`, or `(coord, size_a, size_b)` recording the grab
  origin so every motion resizes *relative to the grab* (no accumulated rounding
  drift).
- `pinned::CellVector` — per-slot `Bool`; a slot dragged at least once is laid
  out at its `sizes` extent exactly.

Each move grows slot `k` and shrinks slot `k+1` by the same delta (total
conserved), clamped to each slot's `layout_min`/`layout_max`. In the
*unconstrained* regime `sizes[k]`/`sizes[k+1]` are written directly; in the
*constrained* regime (`allocate_axis`) the dragged slots are **pinned** — their
`sizes` value becomes a hard preference and their layout weight is zeroed, so
the drag sticks instead of being undone by weighted redistribution. `sizes` is
materialised from the measured slot extents on the first drag if it was empty.
These cells are transient UI state and are not meant to be serialised.

## Strip reports

A tab strip can offer three more things than a tab click, each opt-in on the
pane, and each *reporting* rather than deciding:

| Flag | Draws | Reports |
|---|---|---|
| `closable` | a close button on every tab | `CloseTabRequestOperation(pane, index)` |
| `new_tab` | a `+` button after the last tab | `NewTabRequestOperation(pane)` |
| `draggable` | nothing | `DragTabOperation(pane, index)` on a left button down over a tab |

The strip knows a button was pressed and **nothing about what it means** — what
closing a tab does to the document behind it is the owning projection's business,
exactly as `SelectTabOperation` already worked. A report that nobody claims is
inert: `evaluate_operation` does nothing with it rather than failing.

`_tab_strip_geometry` is the single place that lays out the strip, and both the
printer and the reader read it — extend that function, never its callers, or the
drawn tab and the hit-tested tab drift apart.

The [pane domain](pane.md) is the reference consumer of all three.

## Button behavior

`WidgetButton` is interactive. Its reader maps mouse events to operations, and
its printer renders from transient state — the same input → operation → input →
printer loop every other widget uses:

- **Click → action.** A `MousePress(:left)` on the button yields an
  `InvokeActionOperation(button.action)`. The editor evaluates it by calling the
  action's `callback` — with the editor when it takes one argument (so it can
  mutate `editor.document` / projection state), otherwise with none. An action
  with no callback is inert on click, and its `dialog` (if any) opens instead.
  A projection that renders controls inside its own output must pass the
  operation on — see **Hosting controls** below.
- **Hover / press feedback.** The button carries two transient cells,
  `hovered` and `pressed` (like the split pane's drag state — not serialised).
  `MouseDown` / `MouseUp` set `pressed`; a `MouseMove` over the button sets
  `hovered`. The printer reads both and picks the surface fill
  (`pressed → active_color`, else `hovered → hover_color`, else
  `background_color`) and drops the drop-shadow while pressed, so the button
  re-renders reactively as its state changes.

### Hosting controls

A projection that renders controls inside its own output owns one more
responsibility: passing their activations on. A press answers with
`InvokeActionOperation`, which names its own `Action` and needs no re-rooting —
but the generic reader forwards only what it recognises and returns `nothing`
for everything else, so a hosting projection with no reader for it swallows the
press. The control renders, takes the click, answers, and the answer goes
nowhere. One method fixes it:

```julia
read_intent(::MyProjection, iomap, op::InvokeActionOperation) = op
```

A projection whose catch-all reader (`read_intent(::MyProjection, iomap, op)`)
already forwards every `Operation` needs nothing.

**Naming the projection is load-bearing.** The seemingly simpler
`read_intent(::Projection, iomap, op::InvokeActionOperation)` — one rule for
every projection at once — cannot work: it ties with that catch-all, since each
signature is more specific in one argument and less in another. The tie is
invisible until the first activation reaches such a projection, and then it is a
`MethodError`, not a dead button. This is a property of the 3-argument reader,
which dispatches on the payload.

### Enter / leave: `WidgetHoverTrackingProjection`

Container hit-test routing delivers a `MouseMove` only to the child *under* the
pointer, so a button learns when the pointer enters it but never when it leaves.

The split of responsibility is deliberate: the **generic tracker decides *when*
the pointer crosses a boundary; each widget decides *what that means* for its
own state.** `WidgetHoverTrackingProjection`
([projection/higherorder/WidgetHoverTracking.jl](../../../package/visual/main/widget/WidgetHoverTracking.jl))
is transparent on print; on each `MouseMove` it:

1. routes a synthetic `MouseEnter` at the pointer into the inner pipeline — the
   widget under the pointer answers with an operation identifying itself (an
   opaque `widget` field; the tracker inspects nothing else);
2. if that target is unchanged, emits nothing;
3. if it changed, routes a synthetic `MouseLeave` to the previously-entered
   widget (at the last position over it) so *it* undoes its own state, and
   forwards both responses (bundled as a `CompoundOperation`).

So the tracker constructs **no** widget-specific operation — it only delivers
`MouseEnter` / `MouseLeave` and forwards whatever the widget returns. The
`WidgetButton` reader is what maps `MouseEnter` → `hovered = true` and
`MouseLeave` → clear `hovered`/`pressed`. A different widget can react to the
same crossings differently. `MouseEnter` / `MouseLeave` are first-class
(synthesised, not backend) pointer gestures in `EventModule`; the tracker
mirrors `HoverProbeProjection` in shape.

To make this work, the container readers route `MouseEnter` / `MouseLeave` /
`MouseDown` / `MouseUp` to the hit child, alongside the `MousePress` /
`MouseScroll` they already routed. `WidgetComposite` does it for free-positioned
children; `WidgetMenu` and `WidgetToolbar` route the crossings to their items
(`_route_crossing_to_children`) so the menu/toolbar hover surfaces light up — and
the toolbar now routes `MousePress` too, so its items are clickable. (Wiring the
remaining containers — shell, split pane — is follow-up; these cover the menu,
toolbar, and free-layout examples.)

## Popups (the window route)

Dropdowns, click-menus, submenus, and context menus all open as **real
`WindowDocument`s** through the same `WindowManager` route the tooltip uses —
there is no separate in-window overlay layer. The flow:

1. A **trigger** (`WidgetSelect`, a submenu-opener `WidgetMenuItem`, a
   `WidgetContextMenu`) captures its own document path from `ctx.reference` at
   print time and, on the opening gesture, emits an
   **`OpenPopupOperation(anchor, dx, dy, content, auto_dismiss)`** — the *anchor*
   names the widget to open under (or at, for a context menu) and `(dx, dy)` is a
   trigger-baked offset (the trigger bakes its own size in, so "below the box" is
   `(0, box_height + gap)` and a context menu uses the local click coordinates).
   The trigger never computes its own absolute position.
2. A **`WidgetPopupResolverProjection`** sits at the content root (for a windowed
   app, *between* `WindowManagingProjection` and `ScreenToScreen`). It intercepts
   the `OpenPopupOperation`, forward-maps the anchor to absolute coordinates via
   `anchor_point` (which rides `map_reference_forward`), adds the offset, and
   emits an **`OpenWindowOperation`**. That bubbles up to `WindowManager`, which
   opens the popup window (`style = :floating`).
3. **Dismissal** is a window-level event: the popup window's
   `WindowClose` (Esc / close) or `WindowDefocus` (outside-click) becomes
   a `CloseWindowOperation`. The `auto_dismiss` flag gates focus-lost so only
   popups (never the default window) self-close. An option/menu-item click writes its
   value **and** closes the popup in one `CompoundOperation`.

**Anchor resolution across windows.** A widget's forward image is a
`PointReferenceStep` (its top-left in the output canvas frame), not a structural
path. Containers shift that point by where they placed the child (a layout by the
child's offset, `WidgetShell` by its band offset, and `ScreenToScreen` by the
window's screen origin), while structural paths pass through unchanged —
*coordinates accumulate, paths stay paths*. This is what lets a menu-bar entry or
a select buried inside `shell → layout → window` resolve to an absolute screen
position so its popup opens in the right place. See `make_widget_popup_*_example`
and `WidgetPopupExampleTest` for the end-to-end wiring.

### Modal dialogs (`WidgetDialog`)

A `WidgetDialog(title, content, buttons)` is a centered card over a translucent
scrim, opened as a window with **`modal = true`**. Unlike the popups above it is
**not anchored** (it is centered, so it needs none of the anchor-resolution
machinery) but it **is modal**:

- **Modality is a `WindowManager` concern.** While any window has `modal = true`,
  the manager's reader **drops every `WindowInput` routed to a different
  window** — the base content receives no input, with no per-widget swallowing.
  This reuses the existing `window_id` routing rather than fighting it. A modal
  window ignores focus-lost auto-dismiss (it is dismissed by an explicit choice).
- **Dismissal**: `Esc`, a **backdrop click** (on the scrim, outside the card), or
  a **button** — a button click runs its action *and* closes the window named by
  the dialog's `popup_id`, in one `CompoundOperation` (the same pattern as a menu
  item / dropdown option).
- **Opening**: a `WidgetButton` with a `dialog` field emits
  `OpenWindowOperation(modal = true, content = dialog)` on click;
  `WidgetMessageBox` / `WidgetInputDialog` are convenience builders.
- **`modal` flag**: carried on `WindowDocument` and `OpenWindowOperation` beside
  `auto_dismiss`, copied through by `WindowManager`/`ScreenToScreen`.

**Deferred (v1 limitation):** the scrim fills the dialog's own window, which opens
at a generous fixed box — a true full-screen scrim and exact screen-centering need
a screen-size source the document model does not yet carry (`ScreenDocument` holds
only per-window `x/y/w/h`). The modal *input blocking* is complete regardless of
window size.

## Actions & shortcuts (`Action`)

An `Action(label; icon, enabled, shortcut, callback)` is a shared command object
(Qt's `QAction`): a menu item, a toolbar button, and a keyboard shortcut can all
reference the **same** `Action`, so one object drives all three and toggling its
`enabled` disables all of them at once.

- **Every control has one.** `WidgetMenuItem` and `WidgetButton` carry an
  `action::Action` and nothing else about the command — there is no second
  behaviour or appearance field, so no precedence rule. Pass an `Action` to bind
  a shared command; pass a bare callable (or nothing) and the constructor folds
  the control's own `content` and `icon` into a **fresh** `Action`. A click
  emits `InvokeActionOperation(action)`. Toolbar entries are `WidgetMenuItem`s,
  so they inherit this.
- **A bound control is a LIVE view.** It reads the action's cells rather than
  owning copies, so renaming a command or disabling it re-renders every control
  bound to it with no re-binding step. A control never writes to a shared
  action: an own label or icon that differs from the bound action's is a
  constructor error, not a silent loss — make a second `Action` sharing the
  `callback` if two views need different faces.
- **Enablement is a conjunction.** The effective state is the control's own
  `enabled` **and** the action's, so one view can be inert while the shared
  command stays live in its others.
- **Shortcuts.** `Shortcut(:s; ctrl=true)` builds the chord (a `KeyDownPattern`
  with exact-modifier matching). The `WidgetShell` reader collects the commands
  carrying a shortcut from its `menu_bar`/`toolbar` — the menu *is* the registry —
  and, on a `KeyDown`, fires a matching enabled action **before** forwarding the
  key to the focused child. So `Ctrl+S` works regardless of which widget is
  selected; a non-matching key still reaches the selection.
- **Status bar.** `WidgetStatusBar(segments)` is a thin, non-interactive bottom
  band of stringified segments (Qt's `QStatusBar`); place one on a `WidgetShell`
  via its `status_bar` field and it renders along the bottom edge. *(v1: a
  fixed print-time bottom position, like the other bands.)*

See `make_widget_shell_document_example` (menu + toolbar sharing `Action`s,
`Ctrl+S`, a status bar) and `WidgetActionTest`.

## Icons (`icon = :name`)

An **icon is a named, theme-aware value — not a `GraphicsImage`**. `GraphicsImage`
is a baked raster blit (no color field); an icon must tint to the widget
foreground (and mute when disabled) and scale with the font, like text. So an icon
is a **name**, and a registry maps it to a *renderer* with the uniform signature
`(elems, x, y, size, color) -> nothing`. The widget printers ask the registry to
*draw `icon` at the label's color and size* — they never branch on the backing, so
three backings coexist:

| Backing | Emits | Tints / scales |
|---|---|---|
| **Vector** (built-in set) | `GraphicsPolyline` / `Circle` / `Polygon` | ✅ — generalises the chevron drawer |
| **Glyph-font** (`glyph_icon(font, codepoint)`) | `GraphicsText` | ✅ — needs a bundled icon font |
| **Raster** (`image_icon(image)`) | `GraphicsImage` | ❌ — for brand art |

- **Built-in vector names** (v1): `:save :folder :file :check :x/:close :plus
  :minus :chevron_down :chevron_right :menu :pencil/:edit :trash/:delete :search`.
- **Media-transport names** (filled shapes, for playback/simulation control):
  `:play :pause :stop :step_forward/:step :finish` — play triangle, pause bars,
  stop square, step triangle + bar, checkered finish flag.
- **Register your own:** `register_icon!(:name, renderer)` — pass a vector closure,
  or `glyph_icon` / `image_icon`. An unknown name draws nothing (zero width).
- **On widgets:** `WidgetButton` and `WidgetMenuItem` take an optional `icon`,
  drawn left of the label, tinted to its foreground. It is constructor sugar: the
  icon lives on the control's `Action` (`action.icon`), which is how a menu item
  and a toolbar button bound to one command share it. `WidgetToolButton(:save; …)`
  is an icon-first button (Qt's `QToolButton`).

See `make_widget_document_example` (File menu / toolbar / tool-button row with
icons) and `WidgetIconTest`.

## Transform pane (zoom & pan)

`WidgetTransformPane` is the scroll pane's generalisation: where a scroll pane
carries a transient *offset* (`scroll_position`) and translates its content, a
transform pane carries a transient *affine `transform`* (an `AffineTransform`,
default `affine_identity`) and magnifies/pans it. Both project to a clipping
`GraphicsViewport`; the viewport now carries a `transform` field, so the two are
the same machinery — a scroll is `translate(−offset)`, a zoom is `scale(z)`.

- **Why one node, not two nested panes.** A viewport *clips* at a fixed box, so
  nesting a zoom viewport inside a scroll viewport makes the inner clip fight the
  outer pan. A single viewport carrying one matrix and one clip composes cleanly,
  and makes **zoom-toward-cursor** a single-document matrix update rather than a
  cross-widget `scroll`+`zoom` coordination.
- **Gestures (reader).** `Ctrl`+wheel zooms about the cursor
  (`M' = T(c)∘S(f)∘T(−c)∘M`, total scale clamped to `[0.25, 4.0]`); a plain wheel
  pans (`M' = T(Δ)∘M`). **Keyboard:** `Ctrl`+`=`/`-` zoom in/out and `Ctrl`+`0`
  resets, all about the viewport centre. The keyboard zoom is a *fallback* —
  the key is forwarded to the content first, so a `Ctrl`+`=`/`-` bound inside the
  content (e.g. collection add/remove) still wins. Every edit is a single
  `ReplaceReferencedValueOperation(pane, "transform", M')`, like other widget edits; other
  events are forwarded to the content with the pointer mapped through
  `affine_inverse(M)`, then re-rooted at `.content` exactly as the scroll pane.
- **`transform` is transient view state** (like `scroll_position`) — not
  serialised.
- **Renderer scope.** The SDL, web (`ctx.transform`), and PDF (`cm`) backends
  honour the **translate+scale** subset; rotation/shear is future work (it needs
  `RenderGeometry`/rotated glyphs/stencil clipping on SDL — the document, reader,
  and hit-test math are already general). The console backend is text-only and
  unaffected.

Try `run_example(widget_transform_pane_example)`.

## Image content

A leaf widget's `content` is polymorphic: besides a string (or, for some
widgets, a child `Document`), `WidgetLabel` and `WidgetButton` accept an
`ImageDocument` (`ImageFile` / `ImageMemory`). The printer detects it and emits a
`GraphicsImage` sized to the image's natural size, centered like a text label
(a muted placeholder rect until the image's `raw` cell is decoded). Decoding
stays in the backend (`decode_image_file!`); the domain-layer printer only
*reads* `content.raw`, the same seam inline text images use. See
`widget_button_image_example`.

## Projection to graphics

`WidgetToGraphics(font; measure=sdl_measure_text, theme=widget_theme_light())`
is the convenience factory that returns

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
    # …plus the 17 extension widgets, each with its own ToGraphicsCanvas:
    # WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
    # WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
    # WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetTextarea,
    # WidgetAccordion, WidgetTable, WidgetTree.
))
```

The real factory maps all 33 widget types: the 15 core widgets above, the
`WidgetInsertion` type-replace placeholder, and the 17 extension widgets.

Each per-widget projection takes a `font`, a backend `measure` function,
and a `theme::WidgetTheme` (colours are read from the theme, not stored on
individual widgets). Containers project their children recursively via the
`recursion` argument and assemble the resulting canvases.

`WidgetScrollPaneToGraphicsViewport` is a separate composable projection
that emits a `GraphicsViewport` instead of a flat canvas — useful when the
downstream backend can clip to a viewport efficiently.

## Selection

Widgets carry a `selection::Reference` field like every other Document.
Selection paths typically descend into `content` for leaf widgets, into
`elements`/`selector_element_pairs` (collections) for containers, or to specific
fields like `scroll_position` of a scroll pane. The standard rules in
[the reference guide](../../../package/kernel/doc/reference.md) apply.

### Keyboard routing follows the selection

The selection is the focus: a container forwards a coordless (keyboard) event to
the child its selection points at, and returns `nothing` when the selection is
not inside it — **never** to a default child (no "active tab", no broadcast, no
first-answer fallback). When the selection is elsewhere the container is
untouched and its prior state simply stays. This holds for `WidgetComposite`,
`WidgetSplitPane`, `WidgetTabbedPane`, and the `LayoutDocument` family. (The
tabbed pane still falls back to tab 1 to *render* a tab when nothing is selected;
that is a printing concern, not routing.) An unselected tree therefore delivers
keystrokes nowhere — the first selection is established by a click or by Tab
traversal, not by a routing guess.

## When to use widgets vs. graphics

- Build user interfaces (workbenches, menus, dialogs, IDE layouts) at the
  widget level — the layer is meant for layout abstractions, not pixels.
- Custom drawing primitives (specialised visualisations, plot canvases)
  can go straight to `GraphicsCanvas`.
- A document being edited should generally not be a widget tree. Project
  through widgets only as a presentation layer; keep the source-of-truth
  document in its own semantic domain.

The Workbench domain (see [the workbench guide](../../../package/domain/doc/workbench.md)) is the largest
example of a widget consumer in ProjecturEd.
