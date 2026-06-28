# Selection-driven keyboard routing & Tab traversal

> **Status: ✅ DONE (verified in tree 2026-06-28).** Shipped: selection-driven
> coordless routing + Tab/Shift+Tab traversal, with `first_focusable_path` /
> `last_focusable_path` / `_next_focusable_in` in
> `package/domain/src/document/Widget.jl` (the traversal's cyclic-ListNode
> stack-overflow was later fixed; composite/layout Tab covered by
> `WidgetButtonTest`). Detailed plan for **Stage 2** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Selection-driven
> keyboard routing & traversal"). Depended on Stage 1
> ([widget-interaction-state.md](widget-interaction-state.md)) for the `enabled`
> flag — Tab skips disabled widgets.

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
   (enabled, interactive) widget; Shift-Tab to the previous; wraps at the ends;
   disabled widgets (Stage 1) are skipped. Done **compositionally** — the focused
   leaf gets Tab, declines if it can't advance, and its parent advances to the
   next sibling — rather than via a central enumerator (see Steps 2–3).
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
9. **A selection-move operation already exists.** `ReplaceSelectionOperation(path)`
   (`Operation.jl:74-80`) is evaluated as `update_selection!(editor.document,
   path)`, and `prepend_steps_to_op` already re-roots it
   (`OperationRerooting.jl:65-66`) — exactly like the edit ops container readers
   re-root today. So a container can emit a *relative* selection move and have it
   become absolute as it bubbles up, with **no new operation type**.
10. **Enumeration precedent (test-only):** `collect_tree_selections(document;
    is_node=…)` DFS-enumerates every whole-element selection
    (`test/.../SelectionEnumeration.jl:90-133`) — useful for the *test* Tab-walk,
    though production traversal is distributed (Steps 2–3), not table-driven.

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

## Step 2 — Two local descent helpers (no global enumeration)

**Design decision (per review): traversal is distributed across the container
readers — no dedicated traversal projection and no flat enumeration table.** The
focused leaf gets Tab first (selection routing already delivers it there); if it
can't advance, it declines (`nothing`) and its parent advances the selection to
the next sibling; if the parent can't, it declines to *its* parent; and so on.
The two pieces of shared logic this needs are both **local subtree** operations,
not whole-document walks:

- `first_focusable_path(widget) -> Reference` / `last_focusable_path(widget)` — the
  relative path from `widget` down to its first (last) **enabled interactive**
  leaf, or `nothing` if the subtree contains none. Used to *enter* a sibling: when
  a container advances to sibling `j`, focus must land on a leaf, so the target
  path is `slot_j ⧺ first_focusable_path(child_j)`. Recurses only into the entered
  subtree. Skips `enabled === false` widgets (Stage 1 synergy).
- `_next_focusable_slot(w, after, dir)` per container — the next slot index after
  the currently-selected one whose child has *some* focusable (skipping disabled /
  empty / non-interactive children). Builds on the existing `_selected_*_slot`
  helpers (`WidgetToGraphics.jl:1167-1176` etc.).

Both are pure (document → path / index), unit-testable without rendering.

**Tests:** `first_focusable_path` on a composite `[disabled button, text,
checkbox]` returns the path to `text` (skips the disabled leaf); on a
display-only composite returns `nothing`. `_next_focusable_slot` skips a disabled
middle slot.

## Step 3 — Distributed Tab handling in the container readers

Each **container** reader gains a `KeyDown(:tab)` branch (Shift-Tab = the same
with `modifiers.shift`, walking backward). The recursion is:

1. Find the selected slot `i` via `_selected_*_slot`. (If the selection isn't in
   me, I already return `nothing` per Step 1 — I'm not on the focus path.)
2. **Delegate** Tab to child `i` (recurse). If it returns an op (the child or a
   descendant advanced internally), re-root it with the existing
   `prepend_steps_to_op(op, my_slot_steps)` and return it.
3. If child `i` returns `nothing` (**declined** — ran off its own end), advance:
   find `j = _next_focusable_slot(me, i, dir)`. If found, emit
   `ReplaceSelectionOperation(slot_j_steps ⧺ first_focusable_path(child_j))`
   — **relative to me**; my parent's `prepend_steps_to_op` turns it absolute as it
   bubbles up.
4. If there is no next focusable slot, return `nothing` — **I decline**, and my
   parent advances to *its* next sibling.

Each **leaf** interactive reader declines Tab (`KeyDown(:tab) => nothing`) — Tab is
inter-widget, never intra-leaf (text already declines it,
`TextToGraphics.jl:142-148`). This needs no per-leaf code if the leaf readers
already fall through to `nothing` for unrecognised events; confirm each does.

**Why this works with zero new machinery:** `ReplaceSelectionOperation(path)`
already exists and is evaluated by `update_selection!(editor.document, path)`
(`Operation.jl:74-80`); `prepend_steps_to_op` already re-roots it
(`OperationRerooting.jl:65-66`); and container readers already call
`prepend_steps_to_op` to re-root child ops. Tab traversal is just these existing
parts wired through the decline-and-advance recursion.

### The one genuinely global concern: wrap + bootstrap

Wrap-around (Tab on the *last* focusable → *first*) and bootstrap (Tab with **no**
selection → first focusable) cannot be local: a nested container must *not* wrap
within itself (focus should leave a finished sub-form, not cycle inside it). Both
collapse to a single top-level rule:

> If a `KeyDown(:tab)` bubbles all the way to the top still unhandled
> (`nothing`), set the selection to the whole tree's first focusable
> (`first_focusable_path(root)`); Shift-Tab → `last_focusable_path(root)`.

An unhandled Tab means either nothing was selected (bootstrap) or the last
focusable declined (wrap) — both want the first focusable, so the one rule covers
both. **This is the only non-local piece**, and it does **not** require a new
dedicated projection: place it in the editor's top-level key handling (where the
read loop already turns the root op into a selection update) or fold it into the
existing outer `SequentialProjection`/hover-tracker seam that already wraps the
widget renderer. No `WidgetFocusTraversalProjection` is introduced.

**Tests:** a composite of three text inputs — repeated Tab cycles 1→2→3→1 (the
3→1 step exercises the top-level wrap); Shift-Tab reverses; a disabled middle
widget is skipped; Tab from "no selection" lands on the first focusable; a nested
composite is traversed depth-first (entering it via `first_focusable_path`, and on
exit the outer container advances to the sibling after it).

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
- **Decline must be unambiguous.** The whole scheme relies on "child returned
  `nothing` for Tab ⇒ it declined, so I advance." Confirm no leaf/container returns
  a non-`nothing` op for Tab for some *other* reason; Tab should only ever produce
  a `ReplaceSelectionOperation` (advance) or `nothing` (decline).
- **Re-rooting the selection move.** Each container emits
  `ReplaceSelectionOperation` **relative to itself** (targeting its own next
  sibling) and relies on the *parent* to prepend its slot. Do **not** prepend the
  container's own slot to its own advance op — only to ops delegated up from the
  selected child. Verify the absolute path that reaches `update_selection!` is
  correct for a 2-level nesting.
- **`first_focusable_path` and empty subtrees.** Entering a sibling that turns out
  to have no focusable (`first_focusable_path` → `nothing`) must make the container
  keep scanning to the *next* sibling, not emit a selection into a dead subtree.
- **Wrap/bootstrap placement.** The single top-level rule is the only non-local
  part; put it where the read loop already converts the root op into a selection
  update so it can't be bypassed, and make sure an inner container's legitimate
  decline (no next sibling) still bubbles up to trigger it rather than being
  swallowed.
- **Ring projection churn.** Threading `ring` into every interactive projection is
  repetitive and (as in Stage 1) not runtime-verifiable in a sandbox without
  Julia; land Button+Checkbox first, sweep the rest in one reviewed pass.

## Step status

- [x] Step 1 — selection-only coordless routing: dropped the broadcast/try-each-slot
      fallback in `WidgetComposite`, `WidgetSplitPane`, and the `LayoutDocument`
      readers (removed the now-dead `_forward_composite_event`/`_forward_split_event`/
      `_forward_layout_event` helpers), and routed the tabbed pane's coordless
      events via a new `_route_selected_tab` (no active-tab fallback; the printer's
      `_active_tab_index` is untouched so rendering still shows a tab). Invariant
      documented in `widget.md`. *Not executed — Julia unavailable in sandbox; the
      existing keyboard/REPL tests should be run to catch any reliance on the
      removed fallback.*
- [x] Step 2 — `first_focusable_path`/`last_focusable_path` + `_next_focusable_in`
      implemented (pure, generic field/element descent, skips disabled leaves) +
      unit tests; exported from `WidgetToGraphicsModule`. *Generic entry verified by
      reading for composite/layout; split (LayoutConstraint) / tabbed (selector
      pairs) entry still needs REPL verification.*
- [~] Step 3 — distributed Tab implemented for **`WidgetComposite`**
      (`_composite_tab`): delegate to selected child → on decline advance to next
      focusable sibling via `ReplaceSelectionOperation` (re-rooted by the parent's
      `prepend_steps_to_op`) → decline if none. Bootstrap is principled: a Tab that
      arrives with no child slot selected (selection ∅ on the container, only
      possible at the root or a whole-selected container under selection-only
      routing) focuses the first/last leaf. Tests cover advance / Shift-Tab /
      skip-disabled / bootstrap / wrap-around. The single top-level **wrap-around**
      rule (last→first) is implemented in the `WidgetHoverTracking` reader — the
      outer widget seam, included after the widget module so it can import the
      focus helpers, so **no new projection**: a Tab that bubbles up declined wraps
      to the root's first (last for Shift) focusable; bootstrap stays in the
      containers. Also implemented for the **`LayoutDocument`** readers
      (`_layout_tab` in `LayoutToGraphics`, `children[i]` shape) — the cross-module
      issue was resolved by extracting the focus-path helpers into the document-layer
      `WidgetModule` (included before both `LayoutToGraphics` and `WidgetToGraphics`),
      which both now import. Tests cover the layout `children[i]` path + wrap.
      **All containers now covered:** `WidgetSplitPane` (`_split_tab`, walking a
      `LayoutConstraint`'s `.child` on the delegate re-root; `first_focusable_path`
      descends the constraint generically for the advance) and `StackLayout`
      (`_route_stack_event` Tab branch reusing `_layout_tab`). `GridLayout` was
      already covered (its reader delegates to `_route_layout_event`).
      `WidgetTabbedPane` needs no extra code — its coordless branch delegates Tab
      into the *selected tab's content*, which advances via its own reader and
      declines when exhausted, so the pane declines and the parent advances past it
      (Tab does not switch tabs, which is correct). *Not executed — Julia
      unavailable in sandbox; this selection/reference behaviour especially needs
      REPL verification, and the module extraction is load-time-sensitive.*
- [x] Step 4 — Enter/Space activation on the focused Button/Checkbox: the button
      reader maps `KeyDown(:return)`/`:space` to `InvokeWidgetActionOperation`; the
      checkbox catch-all toggles on the same keys (factored into `_checkbox_toggle`).
      `:tab` is deliberately not matched, so traversal still claims it. Both stay
      behind the Stage-1 `enabled` guard. Tests cover activate + disabled-inert.
      *Not executed — Julia unavailable in sandbox.*
- [x] Step 5 — focus ring on the selected widget (focus = non-nothing selection):
      `_push_focus_ring!` draws a 2px `theme.ring` outline; threaded (`ring_color`
      field, fed `theme.ring`) into Button, Checkbox, Switch, Slider, Toggle,
      ToggleGroup, Select, RadioGroup, Textarea, **and `WidgetText`** (both its
      editable and non-editable printer paths). Test asserts +1 canvas element when
      a Button/Checkbox is selected. **Intentionally not ringed:** `WidgetMenuItem`
      — menu items signal the active item with a highlight, not a focus ring (and
      open-menu behaviour is Stage 3). *Not executed — Julia unavailable in sandbox.*
- [~] Step 6 — added the `widget_focus` example (a `VerticalLayout` of controls
      with an initial selection on the first via `first_focusable_path` +
      `set_selection!`, a disabled control mid-list to show skipping); registered,
      exported, added to the `examples` sweep. Tab traversal itself is covered by
      the composite/layout Tab tests in `WidgetButtonTest`. **Not done:** un-skip
      the syntax-to-widget keyboard-nav sweep — that skip covers *full keyboard
      tree navigation* (Ctrl+Alt+Home, arrow tree-moves), which Stage 2's Tab
      focus does not provide; un-skipping needs broader widget keyboard support.
      *Not executed — Julia unavailable in sandbox.*
