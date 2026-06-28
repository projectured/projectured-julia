# Qt-gap closeout — generalized grid, stacked pages, spin box, list, validators, hover feedback

> **Status: DONE (2026-06-28).** All six parts shipped + a gallery Forms tab + docs.
> With this batch the user considers the Qt widget gap **closed**
> ([qt-widget-gap-analysis.md](qt-widget-gap-analysis.md)). Everything else in that
> analysis (mnemonics, DnD, dock panels, accessibility, animation, RTL, niche
> widgets) is explicitly **out of scope** — "the rest is not important."
>
> See **[As-built notes](#as-built-notes)** at the bottom for where the
> implementation diverged from this plan.

## Context

Stages 3–5 (popups, actions/shortcuts, icons) are done. This closeout finishes the
**form/data-entry** surface (Stage 6) plus two cross-cutting polish items the user
called out: a real **stacked-page** container and **hover feedback** on everything
clickable. Six parts, each independently shippable + tested. The widget layer is a
backend-agnostic presentation layer, so all of this is document + projection work,
verified with the printer/reader sweeps and a rendered gallery.

## Scope decisions (recommendations ✅)

1. **Grid: generalize, don't fork.** ✅ Add per-column `align` + `stretch` to the
   existing `GridLayout` (Qt-grade grid features), defaulted so today's layout is
   byte-for-byte unchanged. `FormLayout` is then **thin sugar** over it, not a new
   engine. (Settled with the user: the form *math* is a parametrized grid; only the
   optional row-wrap is form-specific, and that's deferred.)
2. **StackLayout gains a page index** rather than a new `WidgetStack` type. ✅
   `active = 0` keeps the current z-stack (all children overlaid); `active = i`
   shows only page `i` — the `QStackedWidget` behaviour. Backward compatible.
3. **Validators are a hook, not a type.** ✅ A `validator` *callable* on the text
   inputs, consulted by the reader before committing an edit. No `QValidator` class
   hierarchy.
4. **Hover feedback rides the existing mechanism.** ✅ `WidgetHoverTrackingProjection`
   already synthesises `MouseEnter`/`MouseLeave` to the hovered widget; we just let
   more widgets *respond* (a shared `hovered` cell + a themed hover surface /
   underline), exactly as `WidgetButton` already does. No new projection.

---

## Part A — Generalize `GridLayout` (+ `FormLayout` sugar)

**`GridLayout`** (`document/Layout.jl` + `projection/primitive/LayoutToGraphics.jl`):
- Add optional `column_align::Vector{Symbol}` and `column_stretch::Vector{Int}`
  (per-column horizontal alignment + stretch weights). Defaults reproduce today:
  `column_align` empty ⇒ fall back to the single `horizontal_align` for every
  column; `column_stretch` empty ⇒ all-zero ⇒ content-sized (current behaviour).
- Measure change (the `col_w` cells, `_gl_col_w_cell` / `_gl_col_x_cell`): base
  each column at its content width (as now); when the parent seeded an
  `available_width` **and** any `column_stretch > 0`, distribute the leftover
  `available_width − Σcontent − gaps` across stretched columns by weight. A
  per-column align places each child within its (possibly widened) column.
- **Blast radius:** `GridLayout` is used by `ObjectToWidget` property grids and the
  examples — the defaults keep those unchanged; re-run `test_object_to_widget` +
  the grid/widget printer sweeps.

**`FormLayout`** (thin convenience, `document/Layout.jl`):
- `FormLayout(rows; label_align=:right, gap=…)` where each row is `(label, field)`
  (a field with `label = nothing` spans both columns). Builds a
  `GridLayout(children, 2; column_align=[label_align, :left],
  column_stretch=[0, 1])` — label column hugs, field column fills. Export.
- **Deferred (form-only, optional):** responsive row-wrap (label above field on
  narrow widths). Not needed for v1; noted so it isn't silently dropped.

**Tests:** a stretched column fills the seeded width while a `0`-stretch column
hugs; per-column align positions children independently; a `FormLayout` lays a
label column (right-aligned, uniform width = widest label) beside a filling field
column; `column_align`/`stretch` omitted ⇒ identical output to today (golden).

## Part B — `StackLayout` page container (`QStackedWidget`)

- Add `active::Int` to `StackLayout` (default `0`). `0` ⇒ today's z-stack (all
  children, overlaid). `i ≥ 1` ⇒ the printer lays out **only** child `i`, sized to
  it — a page container.
- Optional `SelectPageOperation(stack, i)` (mirrors `SelectTabOperation`) so a
  controller can switch pages; or just document setting `stack.active`.
- **Tests:** `active=0` renders all children (unchanged); `active=2` renders only
  the 2nd; out-of-range clamps/empties safely.

## Part C — `WidgetSpinBox`

- **Document:** `WidgetSpinBox(value; min, max, step, width, validator=…)` —
  `value::Real`, `min`/`max`/`step`, plus the shared box-model/`enabled` fields. A
  numeric `validator` (Part E) is the default.
- **Projection:** a `WidgetText`-like field showing the value, with up/down stepper
  buttons (reuse `WidgetButton` + the `:plus`/`:minus` or `:chevron` icons from
  Stage 5, and the interaction states). Reader: a click on up/down emits a
  `ReplaceReferencedValue(spin, "value", clamp(value ± step, min, max))`; typing a
  number into the field commits through the numeric validator; disabled ⇒ inert.
- **Tests:** stepping clamps at `min`/`max`; a non-numeric typed entry is rejected
  by the validator; disabled is inert; renders muted when disabled.

## Part D — `WidgetList`

- **Document:** `WidgetList(items; selected=…)` — a first-class single-column
  **selectable** list (`items::CellVector` of strings/widgets, `selected::Int` /
  `selection::Reference`). The sanctioned answer to `QListWidget` (today only
  expressible as a 1-col table / vertical layout).
- **Projection:** a vertical stack of rows; the selected row draws a selection
  band (like the tree/table); each row is hover-highlighted (Part F). Reader: a
  left click on a row selects it (emits the select op / sets `selected`);
  Up/Down/Home/End move the selection via the Stage-2 selection routing.
- **Tests:** a click selects the hit row (selection band moves); Up/Down change the
  selection; an empty list is inert.

## Part E — Validators on text inputs

- A `validator::Any` field on **`WidgetText`** (and `WidgetTextarea`,
  `WidgetSpinBox`): a callable. Two supported shapes, detected by what it returns:
  an **acceptor** `(String) -> Bool` (reject the edit if `false`) or a
  **normaliser** `(String) -> String` (commit the returned value). `nothing` ⇒ no
  constraint (today's behaviour).
- The editable-text reader consults the validator before committing an edit
  (the keystroke/paste path that produces the new string). A rejected edit is a
  no-op; a normalised edit commits the transformed string.
- Built-ins: `numeric_validator(; min, max, integer=…)` used by `WidgetSpinBox`;
  document the contract so callers can pass their own.
- **Tests:** a numeric validator rejects letters and clamps out-of-range; a
  normaliser uppercases on commit; `nothing` leaves editing unchanged
  (regression vs. `test_widget_text_editing`).

## Part F — Hover feedback for actionable widgets

The mechanism already exists (`WidgetHoverTrackingProjection` → synthetic
`MouseEnter`/`MouseLeave` to the hovered widget; `WidgetButton` flips a `hovered`
cell and restyles). Generalise the *convention*:

- **Shared `hovered` state + theme tokens.** Actionable widgets gain a `hovered`
  field; their reader sets it on `MouseEnter` / clears on `MouseLeave` (the
  button's pattern); their printer renders a **hover affordance** when `hovered` &&
  `enabled`. Use existing theme colors (`accent` / `muted` for a hover **surface**;
  `ring`/foreground for an **underline**), so no palette change — pick per widget:
  - **Row-like (surface):** `WidgetMenuItem`, `WidgetOption`, `WidgetList` rows,
    `WidgetTree` rows, `WidgetTabbedPane` inactive tabs, `WidgetAccordion` headers
    — a faint hover background behind the row.
  - **Controls (box/shift):** `WidgetSelect`, `WidgetToggle`, `WidgetSwitch`,
    `WidgetCheckbox` — a subtle border/background shift on hover.
  - **Text-y (underline):** clickable labels / `WidgetContextMenu` target (if a
    label) — underline on hover.
- **Disabled widgets never show hover feedback** (gate on the effective `enabled`,
  reusing Stages 1/4 helpers); their readers already swallow input.
- Keep it a *small shared convention* (a `_hover_surface!` helper + a `hovered`
  reader branch), not per-widget ad-hoc code — mirror how the box-model / focus-ring
  fan-out is shared.

**Tests:** a `MouseEnter` on each actionable widget sets `hovered` and its printer
emits the hover affordance (surface rect / underline); `MouseLeave` clears it; a
**disabled** widget shows none; the hover tracker clears the previously-hovered
widget when the pointer moves to another (extend `test_widget_button_behavior`'s
hover-tracker case to a menu item + list row).

---

## Verification (overall)

- New tests per part (`WidgetSpinBoxTest`, `WidgetListTest`, validator + hover cases
  folded into existing widget tests; grid/form/stack into `LayoutTest` or a new
  `FormLayoutTest`), registered in `ProjecturedTest.jl`.
- Regression: `test_object_to_widget` (grid generalization), `test_widget_text_editing`
  (validators), `test_widget_button_behavior` (hover), and the
  `widget`/`widget_shell` printer sweeps.
- **Render the gallery** (`write_example_image`) with a new **Forms tab**
  (`FormLayout` of labeled inputs incl. a spin box + a list), a stacked-page demo,
  and visible hover state — verify visually as we did for icons.
- Delegate the slow Julia runs to a Sonnet subagent; report summaries + first
  failure verbatim.

## Commit & plan upkeep

Commit per part (grid+form, stack, spinbox, list, validators, hover, then
example+docs), no `Co-Authored-By`. Update this plan as I go; move it to
`plan/done/` once all six parts land — at which point the user considers the Qt gap
**closed**. Document the new widgets/layouts + the hover convention in
[documentation/document/widget.md](../../documentation/document/widget.md).

## Relationship to other plans
- [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) — Stage 6 (`FormLayout`,
  `WidgetSpinBox`, `WidgetList`, validator) + the Stage 7 `QStackedWidget` page
  container, and the cross-cutting hover-state item from Section 3.
- [done/widget-icons.md](../done/widget-icons.md) — the spin-box stepper + hover
  affordances reuse the icon set and interaction-state conventions.
- [layout-extensions.md](../tentative/layout-extensions.md) — `FormLayout` was
  flagged there; this supersedes it for the form/grid piece.

---

## As-built notes

What actually shipped, and where it diverged from the plan above:

- **Part A (grid/form).** `GridLayout` gained `column_align::Vector{Symbol}` +
  `column_stretch::Vector{Int}` (empty defaults reproduce the old output — verified
  against `test_object_to_widget`). `FormLayout` is sugar over it but lives in
  `document/Layout.jl`, **not** `Widget.jl`: layouts load *before* widgets, so it
  takes pre-built `(label, field)` **documents** rather than wrapping strings.
  Stretch only kicks in when a parent seeds `available_width` (the gallery's
  tabbed pane does). Commit `b41fe1b`.
- **Part B (stack).** `StackLayout` gained `active::Int` (0 = z-stack,
  `i` = page `i`, out-of-range = empty). No `SelectPageOperation` — setting
  `active` is enough for v1. Same commit as A.
- **Parts C/D (spin box / list).** `WidgetSpinBox` + `WidgetList` as planned;
  steppers reuse the `:plus`/`:minus` icons. Tests live in **`WidgetFormsTest.jl`**
  (one file), not separate `WidgetSpinBoxTest`/`WidgetListTest`. Commit `9b552fa`.
- **Part E (validators).** Shipped as **acceptor only** (`(String) -> Bool`); the
  normaliser shape was dropped as unused (YAGNI). Field is on `WidgetText` +
  `WidgetSpinBox` (not `WidgetTextarea`). The reader drops a
  `StringReplaceRangeOperation` whose replacement the validator rejects.
  `numeric_validator(; integer=false, allow_negative=true)` — no min/max in the
  validator (clamping is the spin box reader's job). Same commit as C/D.
- **Part F (hover).** Scoped to **`WidgetMenuItem`** — which covers menus,
  submenus, context menus, menu bars, **and** toolbars (the biggest visible win),
  plus `WidgetButton` (already had it). Shared helpers `_hover_state_op` +
  `_push_hover_surface!`; `WidgetMenu`/`WidgetToolbar` readers route crossings via
  `_route_crossing_to_children` (toolbar also gained `MousePress` routing, so its
  items are now clickable). **Deferred (same convention, follow-up):**
  `WidgetOption`/`WidgetSelect`/`WidgetToggle`/`WidgetCheckbox`/list rows/tree
  rows/inactive tabs/accordion headers. Commit `947711c`.
- **Closeout.** Gallery gained a 6th **Forms** tab (commit `e945d16`), rendered
  with that tab selected to verify (widget printer 7429/7429). Layout tests in
  **`LayoutCloseoutTest.jl`**, hover test folded into `WidgetMenuTest.jl`. Docs in
  [widget.md](../../documentation/document/widget.md): a "Form & data widgets"
  section + the generalized hover convention.
