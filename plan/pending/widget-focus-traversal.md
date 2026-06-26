# Selection-driven keyboard routing & Tab traversal

> **Status: planning / not started.** Detailed plan for **Stage 2** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Selection-driven
> keyboard routing & traversal"). Generated 2026-06-26 against the current tree.
> Verified file:line citations below. Depends on Stage 1
> ([widget-interaction-state.md](widget-interaction-state.md)) for the `enabled`
> flag — Tab must skip disabled widgets.

## Goal

Make keyboard interaction follow the **selection**, and let the keyboard move the
selection — with **no new focus concept**. In ProjecturEd the focused widget *is*
the selected widget (every widget carries `selection::Reference`,
`Widget.jl:49-85`). Three deliverables:

1. **Uniform routing.** Every container routes coordless (keyboard) events to the
   child the selection points at — and to **nothing** when the selection is not
   inside it (no "active tab", no broadcast, no first-slot guess). Composite and
   split pane are already selection-routed (but carry a no-selection fallback to
   drop); the tabbed pane still routes to the visible "active tab". Make all of
   them selection-only.
2. **Tab / Shift-Tab traversal.** Tab moves the selection to the next focusable
   (enabled, interactive) widget in a deterministic order; Shift-Tab to the
   previous. Wraps at the ends. Disabled widgets (Stage 1) are skipped.
3. **Focus ring + activation.** Render `theme.ring` around the selected widget,
   and let Enter/Space activate the selected button/checkbox (the keystroke
   already reaches it via routing).

This unblocks the `syntax-to-widget` keyboard-navigation blocker (its deferred
case is exactly this) and is a prerequisite for real forms and for shortcuts
(Stage 4).

## Non-goals

- No `focused` field, no separate focus state — selection is the single source of
  truth (`set_selection!`, `Operation.jl:423-477`).
- No arrow-key 2-D spatial navigation between widgets (Tab order only). Arrow keys
  stay owned by the focused leaf (text caret, slider value, …).
- No popup/overlay focus trapping — that rides on Stage 3 (dialogs).

---

## Background (verified facts this plan builds on)

1. **Routing is mostly selection-driven already.** The composite reader forwards
   coordless events to `_selected_composite_slot(w, n)` — which reads
   `getfield(w,:selection)[]` and extracts the `.elements[i]` slot — falling back
   to "try each slot" only when the widget carries no selection
   (`WidgetToGraphics.jl:1100-1125`, helper `:1167-1176`). The split pane does the
   same via `_selected_split_slot` (`:1665-1700`). The **shell** forwards to all
   children (`:1257-1268`); the **scroll pane** forwards to its wrapped content
   (`:2116-2152`).
2. **The tabbed pane is the deviation.** Its coordless branch routes to
   `_route_active_tab` / `_active_tab_index` — the *visible* tab, not the
   *selected* descendant (`:1935-1938`, `:1942-1979`). It also already has
   `_tab_index_from_selection` (`:1989-2002`) — so the selected-tab lookup exists;
   it just isn't used for routing yet.
3. **Selection is one global path, propagated to per-node relative cells.**
   `set_selection!(document, path)` canonicalises then walks the tree writing each
   node's `selection` cell to its *relative* remaining path; the terminal node
   gets `EmptyReferencePath()` (∅, whole-element) (`Operation.jl:423-477`). So a
   leaf control is focused **iff its `selection` cell is not `nothing`** (a
   button/checkbox holds ∅; a text widget holds a cursor path into its content).
4. **Reference types** (`reference/Reference.jl:34-217`): `ConcreteReferencePath(type,
   head::ReferenceStep, tail)`, `EmptyReferencePath()`, steps `FieldReference(name)`,
   `RangeReference(start,stop)` with `ElementReference(i)=RangeReference(i-1,i)`.
   Whole-element selection of a widget = a path ending in `EmptyReferencePath()`.
5. **Tab already bubbles up unhandled.** Text navigation explicitly declines it:
   `KeyDown(:tab) => :decline` (`TextToGraphics.jl:142-148`), and the leaf controls
   don't handle it either, so a Tab keystroke routed to the focused leaf returns
   `nothing` and is free for a higher layer to claim.
6. **`theme.ring::StyleColor` exists but is unused** (`WidgetToGraphics.jl:96-152`,
   presets e.g. `:192-210`). Borders are drawn by `_push_panel!(...; border=,
   border_w=)` (`:298-320`) — a ring is one more `_push_panel!` with `border=ring`.
7. **Click→set-selection is a proven pattern.** `SelectTabOperation(w, i)` →
   `evaluate_operation` sets `op.widget.selection = ConcreteReferencePath(
   ElementReference(i), EmptyReferencePath())` (`Widget.jl:1156-1232`,
   `WidgetToGraphics.jl:1920-1925`). Tab traversal emits the analogous "set the
   selection to this path" operation.
8. **Tab is `KeyDown(:tab)`**, Shift-Tab is `KeyDown(:tab)` with
   `modifiers.shift` (`device/Keyboard.jl:40-140`).
9. **Enumeration precedent (test-only):** `collect_tree_selections(document;
   is_node=…)` DFS-enumerates every whole-element selection
   (`test/.../SelectionEnumeration.jl:90-133`) — the shape to mirror for a
   production focusable-enumeration helper.

---

## Step 1 — Route coordless events by selection only (no fallback)

**Design decision (per review): selection is authoritative.** A container routes
a coordless (keyboard) event to a child **iff** its selection points at that
child. When the selection does not point into the container, the reader returns
`nothing` — it does **not** guess a default (no "active tab", no broadcast, no
first-slot fallback). The keystroke belongs wherever the selection actually is;
this container is untouched and its prior state simply stays.

- **Tabbed pane** (`WidgetToGraphics.jl:1935-1938`): replace the
  `_route_active_tab` / `_active_tab_index` target with the tab index from
  `_tab_index_from_selection` (`:1989-2002`). If the selection is not in the pane,
  return `nothing` — never route to the visible tab.
- **Composite / split pane** (`:1100-1125`, `:1665-1700`): remove the existing
  "no selection → try each slot in order" fallback (`_forward_composite_event` /
  `_forward_split_event` at `slot == 0`) so these too are selection-only. The
  genuinely-unselected case (a freshly built tree before any click/Tab) is
  handled by Tab traversal (Step 3) and clicks establishing the first selection,
  not by a routing guess.
- **Title pane** (`:1318-1322`) and **toolbar** (`:2184-2187`) handle only
  `MouseScroll` today; leave them (note: when they need key forwarding, use the
  same selection-only branch).
- Document the invariant in [documentation/document/widget.md](../../documentation/document/widget.md):
  *a container forwards a coordless event to the child its selection points at, or
  returns `nothing` if the selection is not inside it — never to a default child.*

**Tests:** a tabbed pane with selection in tab 2 but tab 1 visible delivers a
`KeyDown` to tab 2's content; **with the selection outside the pane the pane
returns `nothing`** (the visible tab is *not* activated, and its content is
unchanged). A composite with no selection returns `nothing` for a `KeyDown`
(no slot guessed).

## Step 2 — Production focusable-enumeration helper

Add `collect_focusable_widgets(document) -> Vector{ReferencePath}` (domain layer,
next to the widget readers), modelled on `collect_tree_selections`
(`SelectionEnumeration.jl:90-133`) but:

- DFS in **render order** (children in declaration order), returning the
  whole-element (∅) path to each **interactive** widget (Button, Checkbox, Text,
  Textarea, Select, Switch, Slider, Toggle, ToggleGroup, RadioGroup, MenuItem —
  the Stage 1 `enabled`-bearing set), skipping pure containers/display widgets.
- **Skip widgets with `enabled === false`** (Stage 1 synergy) — a disabled control
  is not a Tab stop.
- Keep it pure (document → list of paths) so it is unit-testable without rendering.

**Tests:** a composite of [enabled button, disabled button, text, checkbox]
enumerates exactly [button, text, checkbox] in that order, each with the correct
`.elements[i]` path.

## Step 3 — Tab / Shift-Tab traversal projection

Add `WidgetFocusTraversalProjection`, a higher-order projection mirroring
`WidgetHoverTrackingProjection` (which wraps the tree to interpret mouse-move);
this one wraps the tree to interpret Tab. In its `projection_read`:

- Non-`KeyDown(:tab)` events delegate to the inner projection unchanged (exactly
  as the hover tracker passes through non-`MouseMove`).
- On `KeyDown(:tab)`: enumerate `collect_focusable_widgets(iomap.input)`, resolve
  the current global selection to find the current index (or -1 if the selection
  is not on a focusable), compute `shift ? prev : next` with wraparound, and emit
  a **selection-move operation** targeting that widget's path. Handle it directly
  — do not delegate (Tab is never a leaf concern; cf. background fact 5).
- Emit the move via the editor's existing selection mechanism: reuse the operation
  clicks already use to set selection by reference; if no generic one exists, add
  `MoveSelectionOperation(reference)` whose `evaluate_operation` calls
  `set_selection!(editor.document, reference)` (`Operation.jl:423`) — the same
  effect as `SelectTabOperation` (`Widget.jl:1230-1232`), generalised to any path.

Wire the projection into the widget renderers (the workbench/example
`make_widget_projection_example` and the workbench projection) by composing it in
the `SequentialProjection` alongside the hover tracker.

**Tests:** a composite of three text inputs — repeated Tab cycles the selection
1→2→3→1; Shift-Tab reverses; a disabled middle widget is skipped; Tab from "no
selection" lands on the first focusable.

## Step 4 — Enter / Space activation on the focused leaf

Because Step 1 routes keys to the selected leaf, activation is local to each leaf
reader:

- `WidgetButton` reader (`WidgetToGraphics.jl:909`): add
  `KeyDown(:return)`/`KeyDown(:space)` → `InvokeWidgetActionOperation(w)` (still
  behind the Stage 1 `enabled` guard, so a disabled focused button stays inert).
- `WidgetCheckbox` reader (`:854`): add the same keys → the existing toggle op.
- (Switch/Toggle/Select grow theirs when they gain readers — out of scope here.)

**Tests:** with the button selected, `KeyDown(:return)` invokes its action;
`KeyDown(:space)` toggles the selected checkbox; both are no-ops when disabled.

## Step 5 — Focus ring

Render `theme.ring` around the selected widget. Detection is local: a leaf is
focused iff `getfield(w,:selection)[] !== nothing` (background fact 3).

- **Recommended (low churn):** draw the ring in a small post-step shared by the
  interactive-leaf printers — a helper `_push_focus_ring!(elements, w, width,
  height, ring_color)` that, when focused, appends a `_push_panel!` outline in
  `ring` (≈2px, `radius` matched to the control). Thread `ring` into the handful
  of interactive projections the same way Stage 1 threaded `disabled_color`
  (append a `ring_color::StyleColor` field, feed `theme.ring` in the
  `WidgetToGraphics` factory).
- Start with the reference pair (Button + Checkbox), then fan out to the rest.
- Containers do **not** draw a ring (they only delegate); the ring lands on the
  focused leaf.

**Tests:** a button whose `selection` is ∅ renders an extra ring element in the
`ring` color; clearing the selection removes it.

## Step 6 — Example, sweep, and un-skip

- Add a `widget_focus` example: a `VerticalLayout`/composite of a few inputs with
  an initial selection, so `run_example`/screenshots show the ring and Tab can be
  driven; register + export + add to the `examples` sweep (as done for
  `widget_disabled` in Stage 1).
- Add a `test_text_navigation`-style Tab walk asserting Tab reaches every
  focusable (reuse the navigation harness; see
  [documentation/testing.md](../../documentation/testing.md)).
- **Un-skip** the `syntax-to-widget` keyboard-navigation case this stage unblocks
  (its plan flags Stage 2 as the blocker).

---

## Risks / watch-outs

- **No-fallback bootstrap.** With routing now selection-only, an unselected tree
  delivers coordless events nowhere. That is fine *provided* there is always a way
  to establish the first selection: clicks already set it, and Tab traversal
  (Step 3) must work even when nothing is selected (land on the first focusable).
  Verify the first Tab from an unselected tree both selects *and* that following
  keys then reach the now-selected widget — this is the one path that previously
  leaned on the removed fallback.
- **Resolving the current index.** The global selection may point into a leaf's
  *content* (text cursor), not at the leaf's ∅. `collect_focusable_widgets` keys
  on the path *prefix* that reaches the widget; the "current index" lookup must
  match a selection whose tail descends into the widget, not only exact-∅.
- **Where Tab is caught.** The traversal projection must wrap the tree *outside*
  the containers so it sees Tab regardless of which leaf is selected (the leaf
  returns `nothing` for Tab, but the projection handles it top-down before
  delegating — it never reaches the leaf). Confirm compose order in the
  `SequentialProjection`.
- **Operation re-rooting.** A `MoveSelectionOperation(reference)` carries an
  absolute path from the root; ensure it is **not** re-rooted by container readers
  the way edit ops are (it targets the root selection, not a slot-relative edit).
- **Ring projection churn.** Threading `ring` into every interactive projection is
  repetitive and (as in Stage 1) not runtime-verifiable in a sandbox without
  Julia; land Button+Checkbox first, sweep the rest in one reviewed pass.

## Step status

- [ ] Step 1 — unify coordless routing on selection (tabbed pane + audit)
- [ ] Step 2 — `collect_focusable_widgets` (enabled-aware, render-order)
- [ ] Step 3 — `WidgetFocusTraversalProjection` + selection-move operation
- [ ] Step 4 — Enter/Space activation on focused Button/Checkbox
- [ ] Step 5 — focus ring (`theme.ring`) on the selected widget
- [ ] Step 6 — `widget_focus` example, Tab-walk test, un-skip syntax-to-widget
