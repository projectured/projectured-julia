# Per-instance widget behavior via a reified gesture table

Status: **Steps 1–7 implemented** (2026-07-02) on branch
`worktree-widget-per-instance-gestures`. Step 8 (sibling widgets) remains a
follow-up. Not yet verified by a test run — see *Verification* below.

## Implementation notes (2026-07-02)

Built as planned, with one deliberate simplification recorded here:

- **Built-in defaults were NOT reified into a `@gestures WidgetButton` domain
  table.** Instead the built-in click/Enter/Space (button) and select/collapse/
  navigate (tree) handling stays in the reader as a **fallback**, and the reader
  consults the per-instance table *first* via `read_document_gesture` /
  `read_node_gesture`. This delivers the same user-facing capability (add /
  override-by-shadowing / suppress) with far less risk than moving `_activate_button`
  + `OpenWindowOperation` into the domain layer and wiring new `@gestures` imports
  — important because this environment cannot run the full Julia precompile/tests
  to catch a macro/definition-order regression. Consequence: a plain button's
  reader now calls `read_document_gesture`, which returns `nothing` immediately for
  an empty table (no `@gestures` exists on any widget supertype), so behavior is
  unchanged.
- **`_activate_button` was renamed `_button_primary_op`** to reflect that it is
  just the default primary gesture's op-builder, not privileged "activation".
- **Suppression** is a real `NoOperation` (kernel `OperationApiModule`); a binding
  returns it to consume-without-acting. Returning `nothing` still means "decline,
  fall through".
- **Help surfacing** lives in the kernel `collect_gestures` (appends
  `instance_gestures(input)` ahead of the per-type table), not in the help
  decorator — one source of truth next to `document_gestures`. v1 surfaces the
  collected input's own bindings; per-nested-widget surfacing is deferred (widget
  projections don't yet override `collect_gestures` to recurse).
- **`WidgetTreeNode`** got the `gestures` field as a plain 4th struct field plus
  2-/3-arg keyword convenience ctors; `WidgetTree` and `WidgetButton` got a
  `gestures` cell field threaded through their hand-written constructors.
  `FileSystemToWidget`'s direct inner-ctor call was updated for the new arity.

Commits: `142db82` (kernel), `bb29860` (widget+reader), `eb02944` (collector),
`5c95205` (tests).

### Verification (deferred to the user — external terminal)

Per the "no heavy Julia runs here" constraint, run in an external terminal:

```
julia --project=. -e 'using ProjecturedTest; test_widget_gestures()'
julia --project=. -e 'using ProjecturedTest; test_widget_button_behavior(); test_widget_tree()'  # regressions
```

## Problem

Widgets are documents whose *behavior* users routinely want to customize per
instance: what a left-click does, what a double-click does, what a key press
does. Today the only per-instance behavior hook is the single `action` callback
field on [`WidgetButton`](../../package/domain/src/document/Widget.jl#L307)
(and the analogous `action`/`command`/`submenu` on `WidgetMenuItem`). Everything
else is hard-wired in the hand-written `projection_read` methods in
[WidgetToGraphics.jl](../../package/domain/src/projection/primitive/WidgetToGraphics.jl).

The naive fix — one field per event kind (`on_click`, `on_double_click`,
`on_key_*`, …) — bloats the struct and never covers modifier/chord variants.

## Key insight

The codebase already has the right abstraction. The reified gesture system in
[GestureBinding.jl](../../package/kernel/src/common/GestureBinding.jl) is exactly a
"pattern → intent" table:

```julia
GestureBinding(pattern::GesturePattern, operation, applicable, description, domain)
#   operation   :: (doc, event) -> Operation | Nothing   (built in doc's own vocab)
#   applicable  :: (doc, selection) -> Bool               (event-independent guard)
```

interpreted by
[`read_document_gesture(doc, event)`](../../package/kernel/src/common/GestureBinding.jl#L254),
which fires the first binding whose pattern `matches` and whose precondition
holds. The `WidgetButton.action` field **is a degenerate one-entry gesture
table** ("`MousePress(:left)` → run this"), spelled out as a bespoke field.

Gesture patterns already match on kind + button + modifiers and **ignore x/y**
([MouseDownPattern etc.](../../package/kernel/src/common/GestureBinding.jl#L139)),
which is exactly what we want: by the time a widget's `projection_read` runs, the
composite has already hit-tested and coordinate-translated the event down to
*this* widget (e.g. `WidgetButtonToGraphicsCanvas` gets a `SimpleIoMap` with the
event local to the button). That is the "resolved, coordinate-stripped intent"
layer.

## The boundary this design draws

- **Projection reader owns geometry** — hit-testing, routing to children,
  coordinate translation, split-pane/scrollbar drag math. *Not* customizable;
  it's how the widget is drawn. Stays in WidgetToGraphics.
- **Gesture table owns intent** — given a resolved event, what operation
  results. Customizable per instance.

This is the codebase's own principle ("a gesture carries no intent; intent is
the reader's job") pushed one level: the reader resolves *which widget + which
gesture*, then reads the *intent* out of reified data instead of a hardcoded
`@event_case`.

## Design decisions

1. **One field, not N.** Add a single `gestures` field to widgets holding a
   per-instance `Vector{GestureBinding}` of overrides/additions. No per-event
   fields.
2. **Keep `action`/`command`/`dialog` fields as sugar.** They are *read by the
   type-level default binding's operation* (`_activate_button(doc)` already reads
   `doc.command`/`doc.dialog`/`doc.action`). So `WidgetButton(...; action=save)`
   is unchanged; the field is consumed by a default gesture, not a bespoke reader
   branch.
3. **Values are `GestureBinding`s (operation-builders), not raw callbacks.**
   Reified → rides the read→operation→apply pipeline (undoable, testable), and
   the *same* vocabulary already drives help ([GestureMap](../../package/domain/src/document/GestureMap.jl))
   and tooltips, so a custom double-click can show up there.
4. **Type defaults + instance overrides merge.** Built-in behavior is a
   type-level `@gestures WidgetButton` table; the instance list is prepended so
   an instance binding *shadows* a default of the same pattern.
5. **Pilot on `WidgetButton` first**, then extend to `WidgetTree` /
   `WidgetTreeNode` (the requested scope), and finally the other
   activation-shaped widgets (`WidgetMenuItem`, `WidgetCheckbox`,
   `WidgetSwitch`). One widget per step keeps each independently testable.

## Implementation steps

### Step 1 — kernel: instance-aware gesture collection
- [ ] Add a trait `instance_gestures(doc) = GestureBinding[]` (default empty) to
      [GestureBinding.jl](../../package/kernel/src/common/GestureBinding.jl),
      exported alongside `document_gestures`.
- [ ] Change [`read_document_gesture`](../../package/kernel/src/common/GestureBinding.jl#L254)
      to iterate `vcat(instance_gestures(doc), document_gestures(typeof(doc)))`
      instead of just `document_gestures(typeof(doc))`. Default empty instance
      list ⇒ **no behavior change for any non-widget document**. This single,
      general change enables per-instance overrides everywhere at zero cost.
- [ ] Leave the `_GESTURE_CACHE` (type-level) untouched; instance bindings are
      per-instance and recomputed per read (cheap, per-event).

### Step 2 — widget: the `gestures` field
- [ ] Add `gestures::Any` to `WidgetButton` (store like `action`: a **primitive
      cell value**, not reactive content, so projection printers don't walk it as
      children — see the `Cell(action)` note at
      [Widget.jl:341](../../package/domain/src/document/Widget.jl#L341)).
- [ ] Constructor kwarg `gestures=GestureBinding[]`.
- [ ] Override `instance_gestures(w::WidgetButton) = w.gestures` (or, more
      broadly, `instance_gestures(w::WidgetDocument)` reading a `gestures` field
      once the field is shared — decide when extending beyond the pilot).

### Step 3 — widget: the built-in default table

**Clarifying `_activate_button` (the thing that was confusing).**
`_activate_button(w)` at
[WidgetToGraphics.jl:1099](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L1099)
is **not** "the button's behavior." It is *one operation-builder*: given a
button, it resolves what the button's **primary action** is — a bound `command`
→ `InvokeActionOperation`, else a `dialog` → `OpenWindowOperation`, else the plain
`action` callback → `InvokeWidgetActionOperation`. The confusing part is that
today **three different gestures — left-click, Enter, Space — all funnel into
this single "activate" notion** ([reader lines 1078, 1089](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L1078)).
That conflation is exactly what this redesign removes.

**New model: there is no privileged "activate."** A button can be acted on many
ways (left/double/right/shift-click, Enter, Space, Ctrl+Enter, …); **each way is
its own binding row.** The default table just binds a few patterns, and for
backward compatibility points three of them at the same primary-op builder — but
every row is now individually overridable or removable per instance.

- [ ] Rename `_activate_button` → `_button_primary_op` (it builds the op for the
      *primary* gesture; the command/dialog/action resolution logic is unchanged
      and still shared). Keep `_button_enabled`.
- [ ] Declare `@gestures WidgetButton begin … end` for the built-in defaults,
      replacing the activation branches of the hand-written reader:
      - `when(_button_enabled(doc))` block precondition.
      - `MousePress(:left) => "activate" => _button_primary_op(doc)`
      - `KeyDown(:return)  => "activate" => _button_primary_op(doc)`
      - `KeyDown(:space)   => "activate" => _button_primary_op(doc)`
- [ ] Everything else is expressed as **additional bindings** — not hard-wired
      branches — either as further defaults or, more usually, per instance via
      `gestures`. These use the *existing* pattern vocabulary:
      - right-click → `MousePress(:right) => …`
      - shift-click → `MousePress(:left; shift) => …`
      - Ctrl+Enter  → `KeyDown(:return; ctrl) => …`
- [ ] **Double-click is a prerequisite gap.** The gesture vocabulary today has
      only `KeyPress`/`KeyDown`/`KeyUp` and `MousePress`/`MouseDown`/`MouseUp`/
      `MouseMove`/`MouseScroll` patterns
      ([GestureBinding.jl:46](../../package/kernel/src/common/GestureBinding.jl#L46))
      — **there is no double-click event or pattern.** Supporting
      `double-click → X` requires first introducing one: either a
      `MouseDoubleClick` event + `MouseDoubleClickPattern`, or reader-side
      detection of two `MousePress` within a time/distance window that synthesises
      such an event. Right/shift/ctrl variants need no new machinery. Track this
      as its own sub-task before any double-click binding.
- [ ] Decide where the `@gestures` block + `_button_primary_op`/`_button_enabled`
      live (domain-layer Widget.jl vs beside the reader in WidgetToGraphics).

### Step 4 — widget: reader delegates intent, keeps state
- [ ] Rewrite [`projection_read(::WidgetButtonToGraphicsCanvas, …)`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L1071)
      so it:
      1. returns `nothing` early when disabled (unchanged),
      2. delegates intent first: `op = read_document_gesture(w, evt); op === nothing || return op`,
      3. retains the **transient state transitions** in a small `@event_case`:
         `MouseDown(:left) → pressed=true`, `MouseUp(:left) → pressed=false`,
         `MouseEnter → hovered=true`, `MouseLeave → clear hovered+pressed`.
      These are orthogonal events (activation fires on `MousePress`/`KeyDown`, not
      on `MouseDown`/`MouseUp`), so table and state branches don't collide.
- [ ] Confirm state transitions are *not* customization targets in v1; they stay
      reader-owned (revisit later if desired).

### Step 5 — precedence & suppression semantics
- [ ] Instance-first merge gives **override by shadowing** for free.
- [ ] **Suppression is expressed by binding the pattern to an operation that does
      nothing** (per decision). The important nuance to preserve: an
      operation-*builder* returning `nothing` means *decline, fall through to the
      next binding* — so it would hit the default. To *suppress* the default the
      instance binding must return an actual **no-op `Operation` value** (this
      consumes the event and stops the fall-through). Reuse an existing trivial
      operation if one exists; otherwise add a `NoOperation` whose
      `evaluate_operation` does nothing. Document this in the code.

### Step 6 — help / tooltip integration (small, not free)
- [ ] Help currently surfaces `document_gestures(type)`; to show a widget's
      *per-instance* bindings, include `instance_gestures(focused_doc)` where the
      help/`GestureMap` is built (see `gesture_map` / `collect_gestures`). Wire
      this so custom gestures are discoverable. Note honestly: this is an extra
      hook, not automatic.

### Step 7 — extend to `WidgetTree` and `WidgetTreeNode`

These two need different treatment because **only one of them is a document.**

**`WidgetTree` — a `WidgetDocument`** ([Widget.jl:1604](../../package/domain/src/document/Widget.jl#L1604)).
- [ ] Give it a `gestures` field + `instance_gestures` exactly like the button,
      for **tree-level** gestures (e.g. custom key bindings over the whole tree).
- [ ] Its reader is the `Change`-based 4-arg form
      ([WidgetToGraphics.jl:5153](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L5153))
      doing geometry→path routing (`_wtree_mouse_press`, `_wtree_key_navigate`,
      hover). Delegate *intent* to `read_document_gesture(tree, evt)` **before**
      the built-in select/collapse/navigate fallbacks; keep all the geometry
      routing where it is.

**`WidgetTreeNode` — NOT a document** ([Widget.jl:1580](../../package/domain/src/document/Widget.jl#L1580)):
a plain `struct WidgetTreeNode` (`icon`, `label`, `children`) nested in
`WidgetTree.roots`. It has **no `selection` field and no reference identity of its
own** (its identity is its 1-based path within the tree). So per-node behavior
cannot reuse the widget mechanism verbatim:
- [ ] Add a `gestures` field to the plain struct (default empty vector); keep the
      existing positional constructors working.
- [ ] In the tree reader, after `(x,y)`→row resolution (it already computes
      `row.path` and can reach the node), consult **that node's** table for the
      resolved event *before* the built-in select/collapse
      (`_wtree_mouse_press`, [line 5176](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L5176)).
- [ ] The shared interpreter `read_document_gesture` can't be used directly for a
      node — it reads `getfield(doc,:selection)`. Add a **selection-agnostic
      variant** that takes the enclosing tree's selection explicitly:
      `read_node_gesture(node, event, tree_selection)`. (Factor the common loop so
      `read_document_gesture` and `read_node_gesture` share it.)
- [ ] Node operation-builders receive `(node, event)`. The **primary intended use
      case — double-click / Enter on a node runs a callback** (e.g. "open this
      file") — needs no path/tree context, so it works with a plain
      `InvokeWidgetActionOperation`-style callback op. Node operations that must
      *change selection or structure by path* would need the tree + path threaded
      in; **defer those** — the built-in select/collapse already covers structural
      changes, and double-click activation is the concrete ask here.

### Step 8 — extend to sibling widgets (follow-up)
- [ ] Apply the same pattern to `WidgetMenuItem`
      ([reader](../../package/domain/src/projection/primitive/WidgetToGraphics.jl#L1457)),
      `WidgetCheckbox`, `WidgetSwitch`. Consider hoisting `gestures` +
      `instance_gestures` onto `WidgetDocument` so it's declared once.

## Testing

Per repo `CLAUDE.md`, run the **narrowest** test that covers the change; never
`test_all`. And per the "no heavy Julia runs" memory, hand full-stack precompile
/ live-editor verification to the user in an external terminal.

- [ ] Extend `WidgetButtonTest.jl` / `WidgetActionTest.jl`:
      - default left-click still activates (regression),
      - a per-instance `gestures=[…]` binding fires (right-click / shift-click /
        Ctrl+Enter, which need no new machinery),
      - an instance `MousePress(:left)` binding **shadows** the default,
      - a suppress binding (pattern → no-op `Operation`) makes the button inert.
- [ ] `WidgetTreeTest.jl`: a per-node `gestures` binding fires on the resolved
      row (Enter/right-click on a node) while built-in select/collapse still work;
      a tree-level `gestures` binding fires via `read_document_gesture(tree, …)`.
- [ ] Narrow runs only: `test_printer(widget_button_example)`,
      `test_reader(widget_button_example)`, plus the widget action + tree tests.
- [ ] `test_cell()` unaffected; a quick `test_json()`/`test_syntax()` sanity check
      that the `read_document_gesture` merge change didn't perturb existing
      `@gestures`-driven domains (instance list is empty for them).
- [ ] Per the "no heavy Julia runs" note, hand full-stack precompile / live-editor
      verification (and any double-click work) to the user in an external terminal.

## Non-goals / deferred

- Coordinate-dependent gestures (split-pane drag, scrollbar thumb, child routing)
  stay in the reader — they are geometry, not intent.
- Hover/pressed transient state stays reader-owned in v1.
- Cross-cutting *optional* behavior (drag, tooltip, help overlays) remains a
  **decorator projection** concern (`TooltipDecorator`, `GestureHelpDecorator`,
  `HoverProbe`, `Dragging`) — this plan covers *intrinsic per-instance* behavior
  only.

## Decisions (resolved) and remaining open items

**Resolved:**
- **Suppression** → bind the pattern to an operation that does nothing (Step 5).
  Reuse an existing trivial op or add `NoOperation`; the only subtlety is that it
  must be a real `Operation` value, not `nothing`.
- **Help/tooltip integration** → proceed with the extra hook (Step 6); accepted.
- **`_activate_button`** → clarified: it's just the primary-op builder, renamed
  `_button_primary_op`; every gesture is its own binding, nothing is privileged
  (Step 3).

**Remaining open items:**
1. **`gestures` on `WidgetDocument` vs per-struct?** Pilot puts it on
   `WidgetButton`; hoist to the abstract type once ≥2 documents use it (Step 8).
   Note `WidgetTreeNode` is *not* a `WidgetDocument`, so it carries its own field
   regardless (Step 7).
2. **Double-click has no gesture yet** — introducing a `MouseDoubleClick`
   event/pattern (or reader-side detection) is a prerequisite before any
   double-click binding (Step 3). Right/shift/ctrl-click and Enter/Space/Ctrl+Enter
   already work.
3. **Where `@gestures WidgetButton` + `_button_primary_op`/`_button_enabled`
   live** — Widget.jl (domain) vs beside the reader in WidgetToGraphics (Step 3).
4. **Node ops that need path/tree context** are deferred (Step 7); if a real use
   case appears, decide how to thread the tree + resolved path into
   `read_node_gesture` operation-builders.
