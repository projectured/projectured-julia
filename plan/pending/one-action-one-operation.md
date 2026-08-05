# One action, one operation

A control's behaviour is carried two ways — `action`, a bare callable, and
`command`, a shared `Action` — and each way grew its own operation
(`InvokeWidgetActionOperation`, `InvokeActionOperation`). The command's
appearance is likewise carried twice: `content`/`icon` on the control,
`label`/`icon` on the `Action`. This plan collapses every pair:

**Every control carries an `Action`. The `Action` is the single home of what
the command *is* — label, icon, availability, shortcut, callback. Activating
any control produces an `InvokeActionOperation`. What stays on the widget is
exactly the view: placement, box, visibility, transient pointer state,
selection, per-instance gestures, and the subtrees it owns.**

> **Stopgap.** The uncommitted `WidgetActionOperation` union is superseded by
> this plan and should be dropped, not committed. It is five files: in
> projectured-julia `Widget.jl` (adds the union, *deletes* the committed generic
> forwarder at HEAD:1790), `WidgetActionTest.jl`, `widget.md` (a "Hosting
> widgets" section); in omnetpp-julia `SimulationEmbedToWidget.jl` (widens :768
> to the union) and `CatalogShellToWidget.jl` (adds a union forwarder).
> Dropping it restores `SimulationEmbedToWidget:768` to naming
> `InvokeActionOperation` alone — exactly its post-plan shape.

## What is duplicated today

| Concept | On the `Action` | On the widget |
|---|---|---|
| what it does | `callback` | `action` (bare callable) + `command` (an `Action`) |
| name | `label` | `content` |
| icon | `icon` | `icon` |
| availability | `enabled` | `enabled` (*not* duplication — see the conjunction below) |

and the readers emit **two operations** in lockstep with the two behaviour
fields (`_button_primary_op`, `WidgetToGraphics.jl:1187`, quote verified
verbatim):

```julia
command = _button_command(w)
command === nothing || return InvokeActionOperation(command)
dlg = w.dialog
dlg === nothing && return InvokeWidgetActionOperation(w)
```

On a bound control today the action is already the source of truth:
`_button_label_content` (:1072) uses `string(command.label)` and ignores
`w.content` entirely; `_button_icon` (:1074) prefers `command.icon`;
`_button_enabled` (:1070) conjoins the two enabled flags. The merge finishes
that thought rather than inventing a new rule.

**`content` is not a pure name field** (validated): the *unbound* path passes
it raw, and downstream `_content_size`/`_push_content!` (:662–686) special-case
`ImageDocument` (a real image-button example exists,
`example/document/Widget.jl:230-240`), while the menu-item printer (:1522)
recurses a `WidgetDocument` content as a child widget via a
`reconcile_child_iomap(() -> w.content, …)` closure (:1510). The fold must
preserve this: **the merged label read is raw — no `string()` coercion
anywhere** — and the polymorphic branches stay in the printers, repointed at
`w.action.label`.

### Why it matters beyond tidiness

Every site that must pass a control's activation up through a projection has to
name the operation type. With two types, each site names one and is silently
wrong about the other — the same bug twice over:

- `EmbedToSyntax.jl:222` forwards `InvokeWidgetActionOperation` only.
- `SimulationEmbedToWidget.jl:768` forwarded `InvokeActionOperation` only.

Each was reported separately as "the buttons do nothing". One type makes each of
those a single line that cannot be half-right.

## Why one action and one operation

**An activation is reified, and reification has a price that scales with the
number of types.** A reader returns an operation and the editor applies it —
which is what keeps readers pure, makes an edit inspectable, and lets the same
step be driven from the REPL (`evaluate_operation(editor, op)`). The price is
that the operation travels back up the projection chain, so every intermediary
must consent to pass it. Keeping reification and minimising the type count gets
both: one type means a forwarding site has one thing to name and cannot be
half-right.

**A control bound to an action is a live view of it.** The action supplies
label, icon, availability, shortcut and callback; the control *reads through*
the action's cells rather than owning copies (validated: the button printer
body runs inside a `ComputedCell` — `_reactive_canvas`, `WidgetToGraphics.jl:742`,
closure at :1079–1102 — and the menu-item build is a `ComputedCell` at :1511,
so `w.action.label` reads are tracked and re-render on change). Construction
folds a control's own label/icon into a *fresh* action when no shared one is
supplied, so after construction there is exactly one home for the command's
appearance and the printers need no precedence rule at all.

**Enablement is a conjunction, not an override.** `_button_enabled` is
widget-enabled *and* action-enabled, so one control can be locally inert while
the shared command stays live elsewhere. The merge must not flatten this.

**Any control that can be activated can be bound to an action.** A button, a
menu item and a toolbar entry are the same relationship to a command.
(`WidgetToolButton` needs nothing: it is a one-line convenience constructor
forwarding into `WidgetButton` — `Widget.jl:397` — not a struct.)

## What is a command, what is a view

The full field inventory (the widgets and `Action` alike get a macro-injected
`selection` field — `DocumentMacro.jl:274`; only the widgets' is used):

| | `Action` | `WidgetButton` | `WidgetMenuItem` |
|---|---|---|---|
| **name** | `label` | `content` | `content` |
| **icon** | `icon` | `icon` | `icon` |
| **availability** | `enabled` | `enabled` | `enabled` |
| **keyboard** | `shortcut` | — | — |
| **what it does** | `callback` | `action`, `command` | `action`, `command` |
| geometry | — | `position`, `size` | — (the menu lays it out) |
| box model | — | `margin`/`border`/`padding` + colors | same |
| shown | — | `visible` | `visible` |
| pointer inside | — | `hovered` | `hovered` |
| held down | — | `pressed` | — |
| per-instance overrides | — | `gestures` | `gestures` |
| owned subtree | — | `dialog` | `submenu` |

Invariants the merge must respect:

- **Per-view transient state stays on the view.** One command shown in a menu
  and a toolbar has two independent hover states. `hovered`, `pressed`,
  `selection` cannot move to the `Action` (press is a button affordance, hover
  universal — the menu item has `hovered` but no `pressed`).
- **`enabled` appears on both sides deliberately** (the conjunction).
- **Owned subtrees stay on the widget.** `dialog` and `submenu` are child
  documents; the widget is the tree node.
- **Geometry, box model and `visible` are placement** — meaningless on a
  shared command.

Removed by this plan: `content`, `icon` (folded into the action at
construction) and `command` (merged with `action`). Everything else on the
widget is genuinely the view's.

## End state

```julia
@document struct WidgetButton <: WidgetDocument
    position::Point2D
    size::Point2D
    action::Any        # always an Action — the command this control is a view of
    gestures::Any
    dialog::Any
    visible::Bool
    enabled::Bool      # this view's own gate; effective = enabled ∧ action.enabled
    margin::Inset
    ...                # box model unchanged
    hovered::Bool
    pressed::Bool
end                    # content, icon, command are gone; WidgetMenuItem likewise
```

Constructors — the positional `content` stays as sugar and folds into a fresh
`Action`; a supplied `Action` is the source of truth:

```julia
WidgetButton(pos, size, "Go")                # inert view:  action = Action("Go")
WidgetButton(pos, size, "Go"; action = f)    # fresh command: Action("Go"; callback = f)
WidgetButton(pos, size, "Go"; icon = ic)     # icon folds in: Action("Go"; icon = ic)
WidgetButton(pos, size, save)                # bound view of the shared Action `save`
```

`as_action` guards the degenerate corners loudly instead of silently
(validated: no current site occupies any of them):

- an `Action` **and** a differing non-empty `content`/`icon` supplied → error,
  pointing at "make a second `Action` sharing the callback" (a widget never
  writes to a shared action, so the extra label has nowhere to live);
- `action =` a callable **and** an `Action` in the same call (post-merge:
  an `Action` plus `command =` during the transition) → error, not an
  arbitrary winner.

The bound-view sugar is handled **inside the single keyword constructor** via
`as_action` — not as a second positional method, which would be
cross-specificity-ambiguous with the typed `(::Point2D, ::Point2D, content)`
method for the call `(Point2D, Point2D, Action)` (validated against the
generated ctors: those exist only at full arity, so the hazard is between the
two hand-written methods).

Reader:

```julia
_button_primary_op(w) =           # after the enabled-conjunction gate
    w.action.callback === nothing && w.dialog !== nothing ?
        <open dialog> :           # dialog is the fallback for a command that does nothing
        InvokeActionOperation(w.action)
```

For **menu items, `submenu` stays first** — it beats the callback, exactly as
it beats `command` today (`WidgetToGraphics.jl:1582`); `WidgetMenuTest:106-114`
pins this and must keep passing. An item whose action has no callback still
closes the popup (same net behaviour as today's no-action item).

`evaluate_operation(::InvokeActionOperation)` survives unchanged — verified a
strict superset of the widget-action path (adds the `enabled` gate; same
editor-taking-callback preference). `InvokeWidgetActionOperation` is deleted.

**Precedence matrix** (validated cell by cell). Two cells change, one becomes
an error; **zero current call sites occupy any of them** (only two `dialog =`
sites exist, both bare; no site passes `action` + `command`, none passes
`dialog` + a callable):

| today | post-merge |
|---|---|
| bare `action` + `dialog` → dialog opens, callable dead | callback runs, dialog dead |
| inert `command` (no callback) + `dialog` → click no-ops | dialog opens |
| `action` + `command` both → command wins silently | constructor error |

## Validated impact

From a nine-agent sweep of projectured-julia, omnetpp-julia, inet-julia,
opp_repl (2026-08-05):

- **Two repos, not three.** `command =` call sites exist **only in
  projectured-julia**: `example/document/Widget.jl` (10) and
  `WidgetActionTest.jl` (8) + `WidgetIconTest.jl` (1), plus the two ctor
  defaults. omnetpp-julia's exposure is tests (`.content`/`.icon` reads,
  operation constructions) and six reactive-label sites (below).
  **inet-julia and opp_repl have zero widget-button/menu-item references** —
  their only obligation is loading against the live checkout.
- **Full-arity positional constructions: exactly 2** — the keyword-ctor bodies
  themselves (`Widget.jl:377`, `:646`). Keyword-ctor call sites that keep
  working unchanged: ~55 `WidgetButton` + ~74 `WidgetMenuItem` in
  projectured-julia, 18 + 0 in omnetpp-julia.
- **The reactive-label channel** (missed by the original plan):
  `set_cell_function!(::WidgetButton, f)` at `Widget.jl:385` (menu-item twin
  :654) writes the `:content` cell — the API omnetpp uses for live labels.
  Six real sites: `SimulationControlButtons.jl:94` (icon cell direct), `:95`,
  `SimulationWorkflowToWidget.jl:554`, `:659`, `:780`, `:784`. These delegators
  must be retargeted to the action's label/icon cells **in the same landing as
  the printer switch**, or every live label freezes. Residual hazard to
  document: on a *shared* action this now renames the command everywhere.
- **Deleting the type touches more than its definition**: the committed generic
  forwarder `read_intent(::Projection, iomap, ::InvokeWidgetActionOperation)`
  (`Widget.jl` HEAD:1790 — present exactly when the stopgap is dropped), the
  export (`Widget.jl:28`), imports (`WidgetToGraphics.jl:50`,
  `EmbedToSyntax.jl:51`, `SimulationEmbedToWidget.jl:27`), the
  `EmbedToSyntax.jl:218-221` comment that cites the generic forwarder, and
  `CatalogShellToWidget`, which on HEAD has **no** forwarder (it relied on the
  generic one) and must *gain* one naming `InvokeActionOperation`.
- **Hover tracker unaffected** (verified exhaustively): the
  `hasproperty(op, :widget)` branch in `WidgetHoverTracking.jl:164` is dead
  legacy — every built-in MouseEnter response is `nothing` or a
  `ReplaceReferencedValueOperation` caught one line earlier; no reader returns
  a widget-identity op for MouseEnter and no `MouseEnterPattern` binding
  exists in any repo.
- **Copy/sync/shadow machinery self-adapts**: `copy_document`, `Copying.jl:141`,
  `ProjectionTemplate.jl:390` (`_with_selection`), `DocumentSync`, `BoundedSync`
  all iterate `fieldnames` of the live type — no positional or count constants.
  Old and new positional arities are disjoint (18/19→15/16 button,
  15/16→12/13 menu item), so any stale positional call is a **loud**
  MethodError, never a silent field shift.
- **Binary persistence**: a `.prjd` file saved pre-merge containing a
  button/menu item fails **loudly** on load (the serialized kind-parameterized
  type tag no longer matches). `BinarySerialization.jl` explicitly disclaims
  cross-version reads; note it, don't engineer for it.
- **Test surface**: visual — `WidgetActionTest`, `WidgetButtonTest` (5
  testsets assert the widget op / `op.widget`), `WidgetMenuTest:52`,
  `WidgetDialogTest:62`, `WidgetContextMenuTest:45`, `WidgetGestureTest`
  (a gesture *binding callback* constructs the widget op at :27),
  `WidgetIconTest:52,70`; omnetpp — `WatchExampleTest` (import :25, MockEditor
  method :35, **19 direct-fire `evaluate_operation(…, InvokeWidgetActionOperation(btn))`
  sites**, `find_btn`-by-`.content` helpers :281/:734/:737, Pause/Resume
  `.content`/`.icon` flip asserts), `SimulationEmbedTest:150,218`,
  `DemoCatalogTest:21,250-251` (also reads `op.widget.action`). Direct-fire
  sites gain `InvokeActionOperation`'s enabled gate — a real behaviour delta
  for tests firing disabled buttons. `AnchorPointTest`: audit its four
  testsets for positional constructions (likely 3-arg sugar).
- **No read-through test exists anywhere**: nothing in either repo mutates a
  shared `Action`'s label after print and asserts the *rendered output*
  changes (the closest, `WidgetActionTest:66-90`, re-reads intent, not
  render). Step 5 writes it new.

## Steps

The merge core cannot be split thinner than step 2 (validated: folding without
switching the readers regresses the dialog example and turns unbound clicks
into silent no-ops, since `evaluate` would call an `Action` as a bare callable;
switching printers without retargeting the `set_cell_function!` delegators
freezes the six live omnetpp labels). Steps 2 and 3 are cross-repo landings —
omnetpp-julia resolves against the live checkout.

- [x] **1. Prep (green, tiny).** Drop the `string()` coercions on bound-label
      reads (`WidgetToGraphics.jl:1072`, `:1518`) — behaviour-identical today
      (every current command label is a `String`), and required so the merged
      raw-label read preserves image/widget content.

- [x] **2. The merge (one cross-repo landing).**
      - `as_action` + both keyword ctors always store a real `Action` in the
        `action` field (folding positional `content` + `icon =`; guarding the
        error corners above); `command =` feeds the same slot during the
        transition.
      - Helpers read `w.action` (+ widget `enabled` conjunction):
        `_button_label_content` (raw), `_button_icon`, `_button_enabled`,
        `_menu_item_*` (label read is inline at :1518), the menu-item child
        closure at :1510, `_collect_command_actions!` (its
        `shortcut !== nothing` filter already drops sugar actions — verified
        the collected set is identical).
      - Readers emit `InvokeActionOperation(w.action)`: `_button_primary_op`
        with callback-beats-dialog; menu item keeps submenu-first and the
        close-popup compound.
      - Retarget `set_cell_function!(::WidgetButton/::WidgetMenuItem)` to the
        action's label cell; migrate `SimulationControlButtons.jl:94` (icon
        cell) and the five other omnetpp reactive-label sites.
      - Migrate every test that asserts/constructs/fires the widget op (the
        inventory above), including `WidgetGestureTest:27`'s binding callback
        → `InvokeActionOperation(doc.action)` and identity asserts
        `op.widget === btn` → `op.action === btn.action`.

- [x] **3. Delete the dead type.** `InvokeWidgetActionOperation` struct +
      docstring, its `evaluate_operation`, the generic forwarder (HEAD:1790),
      export + the three imports, the `EmbedToSyntax:218-221` comment;
      `EmbedToSyntax.jl:222`'s two generated methods and
      `SimulationEmbedToWidget.jl:768` retype to `InvokeActionOperation`;
      `CatalogShellToWidget` gains an `InvokeActionOperation` forwarder.
      Comment-only mentions in the five omnetpp catch-all readers and
      `SimulationToWidget.jl:163` get reworded.

- [ ] **4. Drop the fields.** Remove `content`, `icon`, `command` from both
      structs; rewrite the two ctor bodies (:377 → 15 args, :646 → 12); no new
      field defaults (the keyword-only ctor trap is gated exactly on that).
      Rewrite the ~19 `command =` sites (example file → bound form
      `WidgetButton(pos, size, save)`; tests likewise) and the `.content`/
      `.icon` field reads (`find_btn` helpers → `b.action.label`,
      `WidgetIconTest:70` → `tb.action.icon`, `SimulationEmbedTest`,
      `DemoCatalogTest:251`). Update the ctor docstrings (`Widget.jl:311`,
      `:603`, WidgetToolButton `:391-395` which advertises `command`).

- [ ] **5. Tests and docs.**
      - New: the rendered read-through test (print → mutate a shared action's
        label + enabled → force → assert drawn text/tint changed); the
        callback-beats-dialog and inert-command+dialog cells; an
        image-content button and a widget-content menu item through the fold.
      - Docs: `widget.md` :240 (operation table row), :277 (click→action),
        :433 ("without a command they keep their own content" — contradicts
        the end state); `operation.md` row 117 (rewrite justification; fix the
        stale `document/Widget.jl` path); omnetpp
        `legacy/doc/simulation.md:88`; the example comment
        `visual/example/document/Widget.jl:213`. Done-plans in both repos
        mention the old op widely — history, left alone.

## Risks

- **The two ctor bodies are the only full-arity positional calls** — rewrite
  them in the same commit as the field drop; everything else fails loud.
- **No field defaults in step 4** — adding one flips the `@document` gate to
  keyword-only constructors and extends Rule Y to lower arities.
- **`set_cell_function!` on a bound (shared) action** now renames the command
  in every view — document it beside the retargeted delegator.
- **Direct-fire tests gain the enabled gate** — a test firing a disabled
  button's action changes from "fires" to "inert"; audit while migrating.
- **Pre-merge `.prjd` files with buttons/menu items fail loudly on load** —
  within `BinarySerialization`'s stated same-version contract.

## Open questions and recorded gaps

- **Does `WidgetMenuItem` survive?** After step 4 it is `action` + `submenu` +
  box + `hovered` + `gestures` + `visible` + `selection`. A menu may simply be
  a list of commands, a submenu named by the action that opens it. Larger than
  this plan; decide separately.
- **Shortcut dispatch ignores the presenting widget's `enabled`** (and
  `visible`): `_collect_command_actions!` filters on the action only —
  pre-existing, unchanged by the merge, recorded.
- **Nothing is checkable.** A checked/unchecked command cannot be expressed;
  if added it belongs on the `Action`.
- **`visible` is per-view only.** A command hidden from every view at once has
  no representation; possibly fine, recorded.
- **The hover tracker's `hasproperty(op, :widget)` branch is dead** — optional
  cleanup, not part of this plan.

## Not in scope

The demo catalog's dropped button press is a separate, still-open problem: the
loss is inside the page renderer, before `CatalogShellToWidget` is consulted.
This plan halves the surface that has to forward, but does not by itself find
that site. The 3-arg vs 4-arg `read_intent` question (286 payload-dispatching
methods against 168 `Intent` ones) is likewise deferred.
