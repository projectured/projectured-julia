# Qt Widget Gap Analysis

> **Status (2026-08-12): DONE.** Stages 1 to 6 are built: interaction state,
> selection-driven keyboard routing, popups and dialogs, actions and shortcuts,
> icons, and form widgets. Each stage has its own detailed plan, now in
> `plan/done/` (`widget-interaction-state.md`, `widget-focus-traversal.md`,
> `widget-popup-overlay.md`, `widget-actions-shortcuts.md`, `widget-icons.md`,
> `qt-gap-closeout.md`). `qt-gap-closeout.md` records that the user considers
> the Qt widget gap closed; Stage 7 (general drag and drop, dock panels,
> sortable headers, accessibility, animation, RTL, and niche widgets) stays
> deferred by design, not dropped. This document is still a gap analysis and
> roadmap, not a spec, and the sections below keep the original wording with
> "As built" / "Confirmed" notes added where the code moved past them.

The goal is **not** to clone Qt one class at a time. ProjecturEd is a
projectional editor: widgets are a *backend-agnostic presentation layer*
(`WidgetDocument` → `WidgetToGraphics` → `GraphicsCanvas`), not a retained-mode
OS toolkit. Qt is used here only as a well-known, exhaustive checklist of "what a
mature UI toolkit offers" so we can see, deliberately, what we have, what we are
missing, and what we are choosing not to build.

See [package/widget/doc/widget.md](../../package/widget/doc/widget.md)
for the current widget set and
[package/widget/main/Widget.jl](../../package/widget/main/Widget.jl)
for the source of truth. (`package/visual/` — the location named when this
analysis was written — no longer exists; it was split into `package/widget/`,
`package/style/`, `package/syntax/`, `package/pane/`, `package/graphics/`,
`package/text/`, `package/layout/`, and others.)

---

## 1. What we have today

**33 widget types** (`WidgetDocument` subtypes, verified in `Widget.jl`):

- **Core (16):** `WidgetInsertion`, `WidgetLabel`, `WidgetText`,
  `WidgetCheckbox`, `WidgetButton`, `WidgetTooltip`, `WidgetMenu`,
  `WidgetMenuItem`, `WidgetComposite`, `WidgetToolbar`, `WidgetShell`,
  `WidgetTitlePane`, `WidgetSplitPane`, `WidgetTabbedPane`, `WidgetScrollPane`,
  `WidgetScrollBar`.
- **Extension (17, shadcn-styled):** `WidgetBadge`, `WidgetSeparator`,
  `WidgetCard`, `WidgetSwitch`, `WidgetProgress`, `WidgetSlider`,
  `WidgetRadioGroup`, `WidgetAvatar`, `WidgetAlert`, `WidgetSkeleton`,
  `WidgetToggle`, `WidgetToggleGroup`, `WidgetSelect`, `WidgetTextarea`,
  `WidgetAccordion`, `WidgetTable`, `WidgetTree`.

**As built (2026-08-12): 43 widget types.** All 33 above are still present, plus
10 new `WidgetDocument` subtypes added by the Qt-gap stages, verified with
`grep -c "<: WidgetDocument" package/widget/main/Widget.jl`: `WidgetSpinBox`,
`WidgetList` (Stage 6 / `qt-gap-closeout.md`); `WidgetContextMenu`,
`WidgetDialog` (Stage 3 popups, with `WidgetMessageBox`/`WidgetInputDialog` as
constructor sugar over `WidgetDialog`, not separate types); `WidgetStatusBar`
(Stage 4); `WidgetTabPage` (the tabbed-pane locality fix); `WidgetTransformPane`;
`WidgetHighlight`; `WidgetOption` (a `WidgetSelect` dropdown row); and
`WidgetAccordionItem`.

**5 layout documents** (`LayoutDocument` subtypes in `Layout.jl`):
`HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`, `StackLayout`.

**As built (2026-08-12): 7 layout documents.** All 5 above are unchanged, plus
`AnchoredLayout` (see [anchored-layout.md](anchored-layout.md), status DONE) and
`ConstraintLayout`. `FormLayout` (Stage 6) is **not** an 8th `LayoutDocument`
subtype — it is a constructor function in
[package/layout/main/Layout.jl](../../package/layout/main/Layout.jl) that builds
a `GridLayout` with per-column `align`/`stretch` set for a label/field form.

**Cross-cutting machinery already in place:**

- A single-token theme (`WidgetTheme`, light/dark presets) — colors live in the
  theme, not on widgets.
- Seven shared box-model fields (`visible`, `margin`/`border`/`padding` + their
  colors) mapping to nested CSS-style boxes via `Inset`.
- Selection plumbing (`selection::Reference` on every widget) and reference
  forward/backward mapping through `WidgetToGraphics`. **This is also the focus
  model** — in a projectional editor the focused widget is simply the selected
  one; there is no separate focus concept (and we do not need one).
- Event routing by hit-test (`MousePress`/`MouseScroll`) and **partial** coordless
  (keyboard) routing: `KeyDown`/`KeyPress` already follow the selection in places
  (the split-pane reader forwards to "the forward-projected selection",
  `WidgetToGraphics.jl:1654`) but elsewhere fall back to an ad-hoc "active tab"
  path (`WidgetToGraphics.jl:1910`) instead of the selection.
  **As built:** this is now closed. `WidgetToGraphics.jl` has a dedicated
  `_route_selected_tab` function (currently around line 3014) whose comment
  states the rule directly: "Unlike `_route_active_tab` there is NO fallback to
  a default/visible tab — selection is authoritative for keyboard [events]."
  `_route_active_tab` still exists, but only for coordinate-bearing events
  (mouse hit-test, drag) that must reach the visibly hovered tab, which is
  correct by design, not the old gap. See Stage 2 below.
- A `WindowManager` (kernel) that composites multiple screens/windows — the
  substrate the inspector and tooltip overlays already use.
- `ProjectionContext` threading `available_width`/`available_height` for
  content-aware sizing / word-wrap.

---

## 2. Qt widget library — reference checklist

Mapped against what we have. Legend: ✅ have · 🟡 partial / adjacent · ❌ missing.

### Buttons
| Qt | ProjecturEd | |
|---|---|---|
| `QPushButton` | `WidgetButton` | ✅ |
| `QCheckBox` | `WidgetCheckbox` | ✅ |
| `QRadioButton` | `WidgetRadioGroup` | ✅ |
| `QToolButton` | toolbar entries | 🟡 no standalone icon-button |
| `QCommandLinkButton` | — | ❌ |
| `QDialogButtonBox` | — | ❌ (needs dialogs) |

**As built:** `QToolButton` is closed — `WidgetToolButton(icon; label, …)` is an
icon-first `WidgetButton` (`Widget.jl` around line 406). `QDialogButtonBox` is
now less of a gap: `WidgetDialog` (Stage 3) carries a `buttons::CellVector` row
directly, so the button-row pattern exists, though there is still no standalone
button-box type. `QCommandLinkButton` is still missing.

### Input / editing
| Qt | ProjecturEd | |
|---|---|---|
| `QLineEdit` | `WidgetText` | ✅ |
| `QTextEdit` / `QPlainTextEdit` | `WidgetTextarea` | ✅ |
| `QComboBox` (closed) | `WidgetSelect` | 🟡 renders closed state; no open popup list |
| `QComboBox` (editable) | — | ❌ |
| `QSpinBox` / `QDoubleSpinBox` | — | ❌ numeric stepper |
| `QSlider` | `WidgetSlider` | ✅ |
| `QDial` | — | ❌ rotary |
| `QScrollBar` | `WidgetScrollBar` | ✅ |
| `QDateEdit` / `QTimeEdit` / `QDateTimeEdit` | — | ❌ |
| `QCalendarWidget` | — | ❌ |
| `QKeySequenceEdit` | — | ❌ |
| `QFontComboBox` | — | ❌ |
| `QCompleter` (autocomplete) | — | ❌ (search-input plan adjacent) |

**As built:** `QComboBox` (closed) is now ✅ — `WidgetSelect` opens a real
dropdown of `WidgetOption` rows through the popup layer (Stage 3;
`OpenPopupOperation`, `Widget.jl` around line 1504). `QSpinBox` is now ✅ —
`WidgetSpinBox` (Stage 6 / `qt-gap-closeout.md` Part C), with a numeric
`validator` and clamped up/down steppers. Editable `QComboBox` is still missing.

### Display
| Qt | ProjecturEd | |
|---|---|---|
| `QLabel` | `WidgetLabel` | ✅ |
| `QProgressBar` | `WidgetProgress` | ✅ |
| `QToolTip` | `WidgetTooltip` | ✅ |
| `QTextBrowser` (rich text + links) | — | ❌ (document-link plan adjacent) |
| `QLCDNumber` | — | ❌ (niche) |
| `QGraphicsView` | graphics domain | ✅ (different layer) |

### Item views
| Qt | ProjecturEd | |
|---|---|---|
| `QTableView`/`QTableWidget` | `WidgetTable` | ✅ |
| `QTreeView`/`QTreeWidget` | `WidgetTree` | ✅ |
| `QListView`/`QListWidget` | — | 🟡 expressible as 1-col table / vertical layout; no first-class list |
| `QColumnView` | — | ❌ (niche) |
| `QHeaderView` | table headers | 🟡 no resizable/sortable header |

**As built:** `QListView`/`QListWidget` is now ✅ — `WidgetList` (Stage 6 /
`qt-gap-closeout.md` Part D) is a first-class single-column selectable list with
click-to-select and Up/Down/Home/End selection routing. Separately, `WidgetTable`
and `WidgetTree` selection now draws as a persistent overlay rather than being
baked into content (commit `29b04eef`, "table & tree selection highlight as a
persistent overlay"). `QHeaderView` resizable/sortable headers are still
missing.

### Containers
| Qt | ProjecturEd | |
|---|---|---|
| `QMainWindow` | `WidgetShell` | ✅ |
| `QTabWidget` | `WidgetTabbedPane` | ✅ |
| `QScrollArea` | `WidgetScrollPane` | ✅ |
| `QSplitter` | `WidgetSplitPane` | ✅ |
| `QGroupBox` | `WidgetCard`/`WidgetTitlePane` | ✅ |
| `QToolBox` | `WidgetAccordion` | ✅ |
| `QFrame` | `WidgetComposite`/`WidgetSeparator` | ✅ |
| `QStackedWidget` | `StackLayout` | 🟡 z-stack exists; no "show page N" selector container |
| `QDockWidget` | — | ❌ dockable/floating panels |
| `QMdiArea` | `WindowManager` | 🟡 multi-window exists; no MDI sub-window chrome |
| `QWizard` | — | ❌ |

**As built:** `QStackedWidget` is now ✅ — `StackLayout` gained an `active::Int`
field (Stage 6 / `qt-gap-closeout.md` Part B; `active = 0` keeps today's
z-stack, `active = i` shows only page `i`, confirmed at
`package/layout/main/Layout.jl` around line 192). `QDockWidget` and `QWizard` are
still missing (Stage 7, deferred).

### Windows / dialogs / chrome
| Qt | ProjecturEd | |
|---|---|---|
| `QMenu` | `WidgetMenu` | ✅ |
| `QToolBar` | `WidgetToolbar` | ✅ |
| `QMenuBar` | — | ❌ window-top menu bar |
| `QStatusBar` | — | ❌ |
| `QDialog` (modal frame) | — | ❌ |
| `QMessageBox` | — | ❌ |
| `QFileDialog` / `QColorDialog` / `QFontDialog` / `QInputDialog` | — | ❌ standard dialogs |
| `QSizeGrip` | split-pane drag | 🟡 |
| `QRubberBand` (marquee select) | — | ❌ |
| `QSplashScreen` / `QSystemTrayIcon` | — | ❌ (OS-level, out of scope) |

**As built:** `QMenuBar`, `QStatusBar`, `QDialog`, and `QMessageBox` are now all
✅. `WidgetShell` carries a `menu_bar::WidgetMenu` field (a horizontal
window-top bar, `Widget.jl` around line 796) and a `status_bar::WidgetStatusBar`
field (Stage 4). `WidgetDialog` is a modal popup frame (backdrop + centered
card + button row, Stage 3), with `WidgetMessageBox`/`WidgetInputDialog` as
convenience constructors over it (not new document types). `QInputDialog` is
covered the same way (`WidgetInputDialog`); `QFileDialog`/`QColorDialog`/
`QFontDialog` are still missing. `QRubberBand` marquee select is still missing.

### Layout managers (vs our `LayoutDocument` family)
| Qt | ProjecturEd | |
|---|---|---|
| `QHBoxLayout` / `QVBoxLayout` | `Horizontal`/`VerticalLayout` | ✅ |
| `QGridLayout` | `GridLayout` | ✅ |
| `QStackedLayout` | `StackLayout` | 🟡 (no page index) |
| `QFormLayout` (label/field rows) | — | ❌ |
| flow layout | `FlowLayout` | ✅ |
| spacers / stretch factors | `layout_min`/`max`/weight | 🟡 no explicit spacer item |
| `ConstraintLayout` / anchors | — | ❌ (see `anchored-layout.md`, `layout-extensions.md`) |

**As built:** `QStackedLayout` and `QFormLayout` are now ✅ (see "As built" note
above for `StackLayout.active` and `FormLayout` sugar over `GridLayout`).
`ConstraintLayout` / anchors are also now ✅ — both `AnchoredLayout` (see
[anchored-layout.md](anchored-layout.md), status DONE) and `ConstraintLayout`
exist as `LayoutDocument` subtypes in `package/layout/main/Layout.jl`. Explicit
spacer items are still missing.

---

## 3. Cross-cutting features — the bigger gap

Individual widgets are largely covered; the real gaps are toolkit-wide
behaviors. These matter more than any single missing widget because they unblock
many widgets at once and because they touch the projectional architecture
(reader/reference plumbing), not just rendering.

1. **Interaction / visual state beyond `visible`.** No `enabled`/`disabled`
   state (confirmed: no `enabled` field anywhere in `Widget.jl`), and
   hover/pressed/focused visual states are ad-hoc per widget rather than a shared
   convention. Qt centralizes this; we should too (likely a small shared field
   set + theme tokens, mirroring how `visible`/box-model fields are shared).
   **As built:** closed by Stage 1 ([widget-interaction-state.md](../done/widget-interaction-state.md),
   status DONE). `enabled::Bool` (default `true`) is now a shared field on the
   interactive widgets, readers gate on it, and `hovered`/`pressed` are a
   formalized shared convention (extended toolkit-wide in `qt-gap-closeout.md`
   Part F).

2. **Keyboard routing & tab order via selection.** Focus is **not** a new
   concept here — the focused widget is the **selected** widget
   (`selection::Reference` already exists on every widget). What is missing is
   making coordless routing *consistently* follow the selection (it does in the
   split-pane reader, `WidgetToGraphics.jl:1654`, but elsewhere falls back to an
   "active tab" path, `:1910`), a Tab/Shift-Tab traversal order that *moves the
   selection* across a container subtree, and a focus ring that renders on the
   selected widget. This is the prerequisite the `syntax-to-widget` plan calls
   out as blocking widget-layer keyboard navigation, and it gates real form
   interaction. No `focused` field is added.
   **As built:** closed by Stage 2 ([widget-focus-traversal.md](../done/widget-focus-traversal.md),
   status DONE). Coordless routing now follows the selection consistently
   (`_route_selected_tab` in `WidgetToGraphics.jl`, with no active-tab
   fallback), Tab/Shift-Tab moves the selection across a container subtree
   (`_composite_tab` and the split-pane equivalent), and a focus ring renders on
   the selected widget. No `focused` field was added, as planned. One follow-up
   stays open: Tab does not wrap from the last focusable widget back to the
   first (a source comment marks this as a known remaining case).

3. **Icons.** No icon concept (confirmed: no `icon` field). Everything is text.
   Qt's `QIcon` is pervasive (buttons, menu items, tabs, tree nodes, toolbar).
   Needs an icon document/primitive (glyph-font or `GraphicsImage`-backed) plus
   an `icon` slot on the relevant widgets.
   **As built:** closed by Stage 5 ([widget-icons.md](../done/widget-icons.md),
   status DONE, including the tab/tree-node follow-up). An `icon` slot now
   exists on `WidgetButton`, `WidgetMenuItem`, `WidgetToolButton`,
   `WidgetTabPage`, and `WidgetTreeNode` (`Widget.jl`).

4. **Actions (`QAction`).** No shared command object bound across
   menu item + toolbar button + keyboard shortcut + enabled-state. Today a menu
   item and a toolbar button duplicate intent. An `Action`-style document that
   widgets reference would dedupe and unlock shortcuts/mnemonics.
   **As built:** the core is closed by Stage 4
   ([widget-actions-shortcuts.md](../done/widget-actions-shortcuts.md), status
   "core DONE, sub-steps 1-5 & 7; mnemonics (6) optional/remaining"). `Action`
   is a real document (`@document struct Action` at `Widget.jl` around line
   1869: `label`/`icon`/`enabled`/`shortcut`/`callback`), `WidgetMenuItem` and
   `WidgetButton` bind to one via `command::Action`, and
   `action_shortcut_matches` drives `Ctrl+S`-style shortcuts. Mnemonics
   (`&File` / Alt-letter accelerators) are the one sub-step still not done.

5. **Dialogs / modal overlays / popups.** No modal layer. `WindowManager`
   composites windows and tooltips/inspector float, but there is no modal dialog
   frame, no popup-menu-opens-on-click, no `WidgetSelect` dropdown list. This
   blocks `QDialog`, `QMessageBox`, the standard dialogs, editable combobox, and
   context menus.
   **As built:** closed by Stage 3 ([widget-popup-overlay.md](../done/widget-popup-overlay.md),
   status "COMPLETE, Steps 1-6 all implemented & tested"). `WidgetPopupResolverProjectionModule`
   turns an anchor-relative `OpenPopupOperation` into an `OpenWindowOperation`
   through the existing `WindowManager` route; `WidgetSelect` opens a real
   dropdown, `WidgetMenu` opens on click, and `WidgetDialog` /
   `WidgetMessageBox` / `WidgetInputDialog` are built on the same popup route.
   Editable combobox is still missing (see the input/editing checklist above).

6. **Validators / input masks.** `WidgetText` has no validation, mask, or
   placeholder-driven constraint hook (placeholder text itself exists via the
   assistant-input plan). Qt's `QValidator`/`QInputMask` have no analogue.
   **As built:** partially closed by `qt-gap-closeout.md` Part E. `WidgetText`
   and `WidgetSpinBox` gained a `validator::Any` callable field (an acceptor
   `(String) -> Bool`; the normalizer shape from the original design was
   dropped as unused). `WidgetTextarea` still has no validator, and there is
   still no input-mask analogue.

7. **Drag & drop.** A `dragging` plan shipped for split-pane resize, but there is
   no general DnD (drag an item between containers, reorder list rows). Qt's
   model is toolkit-wide.

8. **Context menus & shortcuts/mnemonics.** No right-click context menu routing
   and no accelerator (`&File`, `Ctrl+S`) layer. Depends on Actions (#4) and
   popups (#5).
   **As built:** context menus and `Ctrl+S`-style shortcuts are closed (see
   #4 and #5 above): `WidgetContextMenu` routes a right-click through the
   popup window route (`Widget.jl` around line 452). Mnemonics
   (`&File` / Alt-letter) are still the one open piece, same as in #4.

9. **Accessibility.** No accessible-name/role metadata. Out of near-term scope
   but worth a placeholder so widgets can carry the field when needed.

10. **Animation / transitions.** None of the widgets or layouts tween. Qt has
    `QPropertyAnimation`. Explicitly deferred (also flagged in
    `layout-extensions.md`).

11. **Internationalization / RTL.** Layouts and the box model are LTR-only; no
    bidi/RTL mirroring. Deferred.

---

## 4. Prioritization

Rank by **leverage** (how many widgets/use-cases it unblocks) × **architectural
fit** (does it extend existing patterns cleanly):

- **High leverage, good fit:** enabled/disabled + interaction states (#1),
  selection-driven keyboard routing + tab order (#2), Actions (#4),
  popup/overlay layer (#5). These unblock dialogs, context menus, editable
  combobox, shortcuts, and real forms.
- **Medium:** icons (#3), the small missing widgets that ride on the above
  (spinbox, dialog, message box, menu bar, status bar, list view, form layout).
- **Low / deferred:** validators (#6), DnD generalization (#7), accessibility
  (#9), animation (#10), i18n/RTL (#11), and niche widgets (LCD, dial, calendar,
  column view, MDI, wizard).

Guiding rule: **prefer cross-cutting features over one-off widgets** —
selection-driven keyboard routing + a popup layer + Actions is worth more than
ten new leaf widgets, and most of the "missing" widgets are cheap once those
land.

---

## 5. Staged plan

Each stage is independently shippable and ends with examples + tests. Stages are
ordered so each unblocks the next. Every stage needs its own detailed plan doc
under `plan/pending/` before coding.

### Stage 1 — Shared interaction state
*Unblocks: every interactive widget; prerequisite for forms and dialogs.*

**As built (2026-08-12): DONE.** See [widget-interaction-state.md](../done/widget-interaction-state.md)
(status DONE, verified in tree 2026-06-28). `enabled::Bool` and the formalized
`hovered`/`pressed` convention are both in `Widget.jl`.

- Add a shared `enabled::Bool` field (default `true`) to interactive widgets,
  alongside the existing `visible`/box-model fields, and theme tokens for the
  disabled appearance (muted foreground, reduced opacity).
- Formalize hover/pressed/focused as a small shared convention rather than
  per-widget ad-hoc logic; render via theme tokens (`ring` for focus already
  exists).
- Readers must refuse to emit operations from a disabled widget.
- Tests: a disabled button/checkbox/select renders muted and swallows clicks.

### Stage 2 — Selection-driven keyboard routing & traversal
*Unblocks: forms, widget-layer keyboard nav (the `syntax-to-widget` blocker),
shortcuts.* **Detailed plan:**
[widget-focus-traversal.md](../done/widget-focus-traversal.md) (moved to
`plan/done/`; the link above is corrected).

**As built (2026-08-12): DONE**, with one follow-up open. Tab wrap-around (Tab
on the last focusable widget back to the first) is explicitly not handled yet —
see the note on item 2 in section 3 above.

- **No new focus concept** — focus is selection. Use the existing
  `selection::Reference` as the keyboard target.
- Generalize coordless-event forwarding so `KeyDown` consistently reaches the
  **selected** widget (as the split-pane reader already does,
  `WidgetToGraphics.jl:1654`), replacing the ad-hoc "active tab" path (`:1910`).
- Define a deterministic traversal order (Tab / Shift-Tab) that **moves the
  selection** across a container subtree.
- Render a focus ring (theme `ring`) on the *selected* widget.
- Tests: Tab moves the selection across a composite of text inputs; Enter/Space
  activate the selected button/checkbox; un-skip a widget keyboard-nav case.

### Stage 3 — Popup / overlay layer
*Unblocks: dropdowns, context menus, dialogs, message boxes.* **Detailed plan:**
[widget-popup-overlay.md](../done/widget-popup-overlay.md) (moved to
`plan/done/`; the link above is corrected) (chooses **in-window overlays**
over new windows — WindowManager has no outside-click hit-test).

**As built (2026-08-12): DONE** (status "COMPLETE, Steps 1-6 all implemented &
tested"). **Design change during implementation:** the choice named on this
line — in-window overlays because `WindowManager` has no outside-click
hit-test — was reversed. `widget-popup-overlay.md` records an architecture
revision on 2026-06-27: it uses the existing `WindowManager` **window** route
after all (`WidgetPopupResolverProjectionModule`, confirmed in
`package/widget/main/WidgetPopupResolver.jl`), the same route the tooltip
already uses, because the original objection to windows did not hold once the
code was read closely.

- A widget-level overlay/popup mechanism layered on `WindowManager` (or a
  `StackLayout`-based in-window overlay): open a floating child anchored to a
  trigger, dismiss on outside-click / Esc. Reuse the `anchored-layout.md` design
  for placement.
- Make `WidgetMenu` open on click and `WidgetSelect` open a real dropdown list
  (currently closed-state only).
- Add `WidgetDialog` (modal frame: backdrop + centered card + button row) and a
  convenience `WidgetMessageBox`/`WidgetInputDialog` built on it.
- Tests: clicking `WidgetSelect` opens the list and picking an item round-trips
  an operation; Esc closes a dialog; backdrop click dismisses.

### Stage 4 — Actions, menu bar, shortcuts, context menus
*Unblocks: deduped command wiring, accelerators.*

**As built (2026-08-12):** core DONE, mnemonics remaining. See
[widget-actions-shortcuts.md](../done/widget-actions-shortcuts.md) (status
"core DONE, sub-steps 1-5 & 7; mnemonics (6) optional/remaining"). The menu bar
and right-click context menu actually landed as part of Stage 3, not here
(`WidgetShell.menu_bar` and `WidgetContextMenu`) — that plan documents this
sequencing correction.

- An `Action` document (label, icon, enabled, shortcut, callback/operation) that
  menu items, toolbar buttons, and shortcuts all reference.
- `WidgetMenuBar` (window-top bar of menus) and `WidgetStatusBar`.
- Mnemonics/accelerators (`Ctrl+S`, `&File`) routed through the selection-driven
  keyboard routing from Stage 2.
- Right-click → context menu via the popup layer.
- Tests: one `Action` drives a menu item + toolbar button + shortcut; toggling
  the action's `enabled` disables all three.

### Stage 5 — Icons
*Unblocks: visually complete buttons/menus/tabs/tree/toolbar; QToolButton.*

**As built (2026-08-12): DONE**, including the tab/tree-node follow-up. See
[widget-icons.md](../done/widget-icons.md) (status DONE, all sub-steps).

- An icon primitive (glyph-font lookup and/or `GraphicsImage`-backed) and an
  optional `icon` slot on `WidgetButton`, `WidgetMenuItem`, `WidgetTabbedPane`
  tabs, `WidgetTree` nodes, `WidgetToolbar` entries.
- `WidgetToolButton` (icon-first button) falls out of this.
- Tests: a button renders icon + label; a toolbar of icon buttons lays out.

### Stage 6 — Form widgets & form layout
*Unblocks: real data-entry UIs; rides on Stages 1–3.*

**As built (2026-08-12): DONE.** Shipped as
[qt-gap-closeout.md](../done/qt-gap-closeout.md) (status DONE, 2026-06-28),
which also folded in two extra cross-cutting items beyond this stage's
original scope: a `StackLayout` page container and toolkit-wide hover
feedback. Its "As-built notes" section records where the shipped design
diverged from this outline — for example, `FormLayout` lives in
`document/Layout.jl`, not `Widget.jl` (layouts load before widgets), and the
validator shipped as acceptor-only, dropping the normalizer shape as unused.

- `FormLayout` (label/field rows, aligned columns) in the `LayoutDocument`
  family — straightforward `recurse-then-measure`.
- `WidgetSpinBox` / numeric stepper (and optionally date/time editors) built on
  `WidgetText` + the interaction states + buttons.
- `WidgetList` as a first-class single-column selectable list (or document that
  `WidgetTable`/vertical layout is the sanctioned substitute).
- Optional: a lightweight validator hook on `WidgetText`.
- Tests: a form (labels + text + spinbox + select + checkbox + button row) lays
  out, tabs through, and round-trips edits.

### Stage 7 — Deferred / opportunistic
*Pursue only on concrete demand.*

**As built (2026-08-12):** the `QStackedWidget`-style page container bullet
below is DONE (`StackLayout.active`, shipped early as part of
`qt-gap-closeout.md` Part B rather than waiting for Stage 7). Everything else
in this stage is still open, by design: `qt-gap-closeout.md` records that the
user considers the Qt widget gap closed and treats the rest of this stage as
explicitly out of scope ("the rest is not important"), not a queued backlog.

- General drag & drop (reorder rows, drag between containers) — generalize the
  `dragging` work.
- `QStackedWidget`-style page container (page index over `StackLayout`).
- Dockable panels (`WidgetDock`), `QStackedWidget` selector, resizable/sortable
  table headers.
- Accessibility metadata fields; animation/transition layer; RTL/bidi.
- Niche widgets (LCD number, dial, calendar, column view, MDI chrome, wizard) —
  build per real use case, not speculatively.

---

## 6. Explicitly out of scope

OS-integration widgets that don't fit a backend-agnostic projection layer:
`QSystemTrayIcon`, `QSplashScreen`, native file/print dialogs (we'd build our own
`WidgetDialog`-based versions instead), `QOpenGLWidget`/`QQuickWidget` (the
graphics domain is the rendering substrate). Animation, accessibility, and RTL
are deferred (not rejected) — recorded so they aren't silently dropped.

---

## 7. Relationship to existing plans

This analysis subsumes / sequences several existing plans:

- [anchored-layout.md](anchored-layout.md) — placement engine reused by Stage 3
  (popups) and tooltips. **As built:** still in `plan/pending/`, status DONE
  (`AnchoredEntry`/`AnchoredLayout` shipped).
- [layout-extensions.md](../tentative/layout-extensions.md) — `FormLayout`
  (Stage 6), `ConstraintLayout` (deferred), spacer items. **As built:** still in
  `plan/tentative/`, but both items it flagged are now done elsewhere:
  `FormLayout` shipped in Stage 6 / `qt-gap-closeout.md`, and `ConstraintLayout`
  shipped as its own plan, [../done/constraint-layout.md](../done/constraint-layout.md)
  (status DONE, verified green 2026-06-28). Explicit spacer items are still
  missing.
- [search-input-widget.md](../tentative/search-input-widget.md) — autocomplete
  (`QCompleter`) lands on Stages 2–3. **As built:** the path still resolves,
  but the file at that path is Stage 2 of a `ProjectionConfiguringProjection`
  plan (a generic projection-parameter control), not a `QCompleter`-style
  autocomplete box; Stage 1 of that plan is done
  ([../done/search-input-widget.md](../done/search-input-widget.md)).
  Autocomplete on `WidgetSelect`/`WidgetText` itself is still missing.
- [document-link-feature.md](document-link-feature.md) — rich-text links
  (`QTextBrowser`). **As built:** still in `plan/pending/`, status NOT STARTED.
- [syntax-to-widget.md](syntax-to-widget.md) — its deferred keyboard-navigation
  blocker is exactly Stage 2 (selection-driven keyboard routing). **As built:**
  this plan moved to `plan/done/` — the link above is stale and should read
  [../done/syntax-to-widget.md](../done/syntax-to-widget.md). Its keyboard-nav
  blocker is closed by Stage 2 (see section 3, item 2, above).
- [tooltip.md](tooltip.md) — already shipped; the overlay layer (Stage 3)
  generalizes its floating mechanism. **As built:** the v1 tooltip mechanism
  this line means (`TooltipSource`, `WindowManagerProjection`, the `:tooltip`
  window flag) is indeed in place and is the route Stage 3's popup resolver
  reuses. But the `tooltip.md` plan itself is not fully shipped: it carries its
  own status "(2026-08-12): IN PROGRESS", with several remaining steps (its
  own steps 1, 5, 6, 7, 8) still open.
