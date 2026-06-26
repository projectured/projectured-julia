# Qt Widget Gap Analysis

> **Status: planning / not started.** This document is a gap analysis of the
> ProjecturEd widget domain against the Qt Widgets (`QtWidgets`) library, plus a
> staged plan to close the gap. It is a roadmap, not a spec — each stage needs
> its own detailed plan before implementation. Generated 2026-06-24.

The goal is **not** to clone Qt one class at a time. ProjecturEd is a
projectional editor: widgets are a *backend-agnostic presentation layer*
(`WidgetDocument` → `WidgetToGraphics` → `GraphicsCanvas`), not a retained-mode
OS toolkit. Qt is used here only as a well-known, exhaustive checklist of "what a
mature UI toolkit offers" so we can see, deliberately, what we have, what we are
missing, and what we are choosing not to build.

See [documentation/document/widget.md](../../documentation/document/widget.md)
for the current widget set and
[package/domain/src/document/Widget.jl](../../package/domain/src/document/Widget.jl)
for the source of truth.

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

**5 layout documents** (`LayoutDocument` subtypes in `Layout.jl`):
`HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`, `StackLayout`.

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

3. **Icons.** No icon concept (confirmed: no `icon` field). Everything is text.
   Qt's `QIcon` is pervasive (buttons, menu items, tabs, tree nodes, toolbar).
   Needs an icon document/primitive (glyph-font or `GraphicsImage`-backed) plus
   an `icon` slot on the relevant widgets.

4. **Actions (`QAction`).** No shared command object bound across
   menu item + toolbar button + keyboard shortcut + enabled-state. Today a menu
   item and a toolbar button duplicate intent. An `Action`-style document that
   widgets reference would dedupe and unlock shortcuts/mnemonics.

5. **Dialogs / modal overlays / popups.** No modal layer. `WindowManager`
   composites windows and tooltips/inspector float, but there is no modal dialog
   frame, no popup-menu-opens-on-click, no `WidgetSelect` dropdown list. This
   blocks `QDialog`, `QMessageBox`, the standard dialogs, editable combobox, and
   context menus.

6. **Validators / input masks.** `WidgetText` has no validation, mask, or
   placeholder-driven constraint hook (placeholder text itself exists via the
   assistant-input plan). Qt's `QValidator`/`QInputMask` have no analogue.

7. **Drag & drop.** A `dragging` plan shipped for split-pane resize, but there is
   no general DnD (drag an item between containers, reorder list rows). Qt's
   model is toolkit-wide.

8. **Context menus & shortcuts/mnemonics.** No right-click context menu routing
   and no accelerator (`&File`, `Ctrl+S`) layer. Depends on Actions (#4) and
   popups (#5).

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
[widget-focus-traversal.md](widget-focus-traversal.md).

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
*Unblocks: dropdowns, context menus, dialogs, message boxes.*

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

- An icon primitive (glyph-font lookup and/or `GraphicsImage`-backed) and an
  optional `icon` slot on `WidgetButton`, `WidgetMenuItem`, `WidgetTabbedPane`
  tabs, `WidgetTree` nodes, `WidgetToolbar` entries.
- `WidgetToolButton` (icon-first button) falls out of this.
- Tests: a button renders icon + label; a toolbar of icon buttons lays out.

### Stage 6 — Form widgets & form layout
*Unblocks: real data-entry UIs; rides on Stages 1–3.*

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
  (popups) and tooltips.
- [layout-extensions.md](../tentative/layout-extensions.md) — `FormLayout`
  (Stage 6), `ConstraintLayout` (deferred), spacer items.
- [search-input-widget.md](../tentative/search-input-widget.md) — autocomplete
  (`QCompleter`) lands on Stages 2–3.
- [document-link-feature.md](document-link-feature.md) — rich-text links
  (`QTextBrowser`).
- [syntax-to-widget.md](syntax-to-widget.md) — its deferred keyboard-navigation
  blocker is exactly Stage 2 (selection-driven keyboard routing).
- [tooltip.md](tooltip.md) — already shipped; the overlay layer (Stage 3)
  generalizes its floating mechanism.
