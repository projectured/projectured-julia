# Stage 4 — Actions, shortcuts, status bar (+ mnemonics)

> **Status: core ✅ DONE (sub-steps 1–5 & 7); mnemonics (6) optional/remaining.**
> Detailed plan for **Stage 4** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Actions, menu bar,
> shortcuts, context menus"). Builds on the now-complete **Stage 3**
> ([done/widget-popup-overlay.md](../done/widget-popup-overlay.md)).
>
> **Implemented & tested** (`WidgetActionTest`, 22 assertions; commits `9ead1fe`,
> `c61a462`): ✅ 1 `Action` document + `Shortcut` + `InvokeActionOperation`;
> ✅ 2 `WidgetMenuItem`/`WidgetButton` `command::Action` binding (label + enabled +
> activation from the Action); ✅ 3 shell shortcut dispatch (Ctrl+S before the
> focused child); ✅ 4 `WidgetStatusBar` + `WidgetShell.status_bar`; ✅ 5
> `WidgetMessageBox`-style done in Stage 3 — here the `widget_shell` example shares
> Actions across menu+toolbar with a Ctrl+S; ✅ 7 docs (`widget.md` "Actions &
> shortcuts"). **Remaining (optional):** 6 mnemonics (`&File` / Alt-letter) —
> self-contained, deferrable.

## Context

Qt's `QAction` is a single command object — label, icon, enabled-state, keyboard
shortcut, callback — that a menu item, a toolbar button, and a keyboard shortcut
all **share**. Today ProjecturEd duplicates intent: a `WidgetMenuItem` and a
`WidgetToolbar` button each carry their own `action` callback and their own label,
and there is no keyboard-shortcut layer at all. Stage 4 introduces the shared
`Action` so one object drives all three, and so toggling its `enabled` disables
all three at once.

**Already landed in Stage 3** (so out of this plan's scope): the **menu bar**
(`WidgetShell.menu_bar` rendered horizontally, Step 4c) and the **right-click
context menu** (`WidgetContextMenu`, Step 4d). What remains from the gap-analysis
Stage 4 is: the **`Action` object**, **keyboard shortcuts/accelerators**, a
**`WidgetStatusBar`**, and (optional, last) **mnemonics** (`&File` / Alt-letter).

The machinery to reuse is all in place:
- Activation seam: `InvokeWidgetActionOperation(widget)` →
  `evaluate_operation` calls `widget.action` with the editor or 0 args
  (`document/Widget.jl`). An `Action` invocation mirrors this exactly.
- Shortcut matching: the gesture layer already has `KeyDownPattern(key, mods,
  guard)` with exact-modifier `matches(pattern, KeyDown)` matching
  (`kernel/common/GestureBinding.jl`) — reuse it verbatim for `Ctrl+S`.
- Shortcut dispatch point: `WidgetShell` already aggregates `menu_bar` +
  `toolbar` + (dormant) `context_menu`, and its reader forwards coordless events
  to the focused child via `_forward_to_children`
  (`projection/primitive/WidgetToGraphics.jl`). The shell is where a `KeyDown`
  should first be offered to the registered shortcuts, *before* the focused child.

## Scope decisions (please weigh in — recommendations marked ✅)

1. **Action representation.** ✅ A dedicated **`Action` document** (reactive cells
   for `label`/`enabled`/`icon`/`shortcut`/`callback`) that widgets *reference* —
   the QAction model. Toggling `action.enabled` then re-renders every referencing
   widget reactively. (Alternative: overload the existing `action::Any` field to
   also accept an `Action` — rejected: muddier, and a menu item presenting an
   Action must read its *label* from the Action, which a bare callback can't give.)

2. **How a widget binds to an Action.** ✅ Add an optional **`action::Action`**
   reference distinct from the existing callback. A `WidgetMenuItem` / `WidgetButton`
   that carries an `Action` renders its label/enabled **from the Action** and, on
   activation, emits `InvokeActionOperation(action)`; one without falls back to
   today's `content` + callback behaviour. (Keeps every existing call site working.)

3. **Shortcut registry source.** ✅ **Collect from the `menu_bar` + `toolbar`
   subtree** — the menu *is* the action registry, so no separate list to keep in
   sync. The shell reader walks those fields for `Action`s with a `shortcut`,
   matches the incoming `KeyDown`, and emits `InvokeActionOperation` before
   forwarding to the focused child. (Alternative: an explicit `actions::CellVector`
   on the shell — more wiring, easy to desync; revisit only if walking proves a
   hotspot.)

4. **Mnemonics (`&File`, Alt-F).** ✅ **Optional last sub-step**, shippable
   separately. It needs label `&`-parsing + an underline glyph + Alt-routing, none
   of which the rest depends on. Land Actions + shortcuts + status bar first.

## Implementation

### 1. `Action` document (`domain/document/Widget.jl`)
`Action(label; icon=nothing, enabled=true, shortcut=nothing, callback=nothing)`.
- `label::Any`, `enabled::Bool`, `icon::Any` (a slot — populated by **Stage 5**;
  `nothing` for now), `callback::Any` (stored as a primitive cell value via
  `setval!`, like `WidgetButton.action`), `shortcut::Any` (a `KeyDownPattern`, or
  `nothing`). Export `Action` / `IAction`.
- Helper `action_shortcut_matches(action, evt)::Bool` = `action.shortcut !== nothing
  && action.enabled !== false && matches(action.shortcut, evt)` (reuses the kernel
  `matches`). A `Shortcut(key; ctrl=…, alt=…, shift=…)` convenience builds the
  `KeyDownPattern`.

### 2. `InvokeActionOperation` (`domain/document/Widget.jl`)
`struct InvokeActionOperation <: Operation; action::Action; end` +
`evaluate_operation(editor, ::InvokeActionOperation)` — call `action.callback`
(editor-arg preferred, else 0-arg), **guarded by `action.enabled`** (a disabled
action is a no-op). Mirrors `InvokeWidgetActionOperation`. Export.

### 3. Bind widgets to an Action (`document` + `projection/primitive/WidgetToGraphics.jl`)
- `WidgetMenuItem` and `WidgetButton` gain an optional `action::Action` reference
  (alongside the existing callback field — pick a non-colliding name, e.g.
  `command::Action`, to avoid overloading `action`). Their **printers** read the
  label + `enabled` from the bound `Action` when present (so the muted/disabled
  appearance and the text both follow the Action); their **readers** emit
  `InvokeActionOperation(command)` (wrapped with the popup `CloseWindowOperation`
  for menu items, exactly as 4a does) instead of `InvokeWidgetActionOperation`.
  No bound command ⇒ unchanged behaviour.
- Toolbar entries are already `WidgetMenuItem`s, so they inherit this for free.

### 4. Keyboard shortcuts via the shell (`projection/primitive/WidgetToGraphics.jl`)
- A pure `_collect_actions(widget)::Vector{Action}` walking `menu_bar` + `toolbar`
  (recursing menus/submenus), returning bound `Action`s that have a `shortcut`.
  (Mirror the subtree walk the focus-traversal helpers already do.)
- In the `WidgetShell` reader, **before** `_forward_to_children`: on a `KeyDown`,
  find the first collected action whose `shortcut` matches and is enabled → return
  `InvokeActionOperation(action)`. Otherwise fall through to the existing
  selection-forwarding. (Global within the window, selection-independent — the
  correct semantics for an app shortcut.)

### 5. `WidgetStatusBar` (`document` + `projection`)
A thin bottom band of text segments (`WidgetStatusBar(segments)`; each segment a
string or small widget), rendered like the `menu_bar` band. Add an optional
`status_bar::WidgetStatusBar` field to `WidgetShell` (rendered below `content`).
Non-interactive in v1. Export + register in the factory.

### 6. Mnemonics — optional (`projection`)
Parse a leading/`&`-marked letter in an `Action`/menu label, draw it underlined,
and have the shell match `Alt+<letter>` against menu-bar entries (reusing the
Step 4 submenu-open path) and `&`-letters against open-menu items. Self-contained;
land last or defer.

### 7. Example + docs
- Extend `make_widget_popup_document_example` (or a small `widget_actions`
  example): a `File` menu whose **New**/**Open**/**Save** items and a matching
  toolbar share `Action`s, one with `Ctrl+S`; a status bar; a checkbox that toggles
  an Action's `enabled` to show all referencing widgets disabling together.
- Document the Action model in
  [documentation/document/widget.md](../../documentation/document/widget.md): one
  `Action` shared by menu item + toolbar button + shortcut; `enabled` propagation;
  `InvokeActionOperation`; the shell shortcut-dispatch order (shortcuts before the
  focused child).

## Verification

New `WidgetActionTest.jl` (registered in `ProjecturedTest.jl`; run via the
worktree-root env `julia --project=. -e 'using Projectured, ProjecturedExample,
ProjecturedTest; test_widget_action()'`):

- **One Action, three triggers**: build an `Action("Save"; shortcut=Ctrl+S,
  callback=…)` shared by a `WidgetMenuItem`, a toolbar `WidgetButton`, and the
  shell shortcut. A menu-item click, a toolbar-button click, and a `KeyDown(:s,
  ctrl)` envelope each emit `InvokeActionOperation(action)`; applying it fires the
  callback once.
- **Enabled propagation**: set `action.enabled = false`; the menu item and the
  toolbar button render via the muted/disabled branch, both readers go inert, and
  the shortcut no longer fires (the shell skips a disabled action).
- **Shortcut precedence**: a `KeyDown` matching a shortcut is consumed by the shell
  (returns `InvokeActionOperation`) and is **not** also forwarded to the focused
  child; a non-matching `KeyDown` still reaches the selected widget.
- **Status bar**: `test_printer` over the example renders the status band; a shell
  with a `status_bar` lays it out below the content.
- **Regression**: `test_widget_menu`, `test_widget_button_behavior`,
  `test_widget_popup_example`, and a `test_printer(widget_shell_example)` sweep stay
  green (menu-item/button/shell touched).

Delegate the (slow) Julia runs to a Sonnet subagent, reporting testset summaries +
any first failure verbatim.

## Commit & plan upkeep

Commit incrementally on the current branch (one commit per shippable sub-step:
Action+invoke, widget binding, shortcuts, status bar, mnemonics, example+docs), no
`Co-Authored-By`. Update this plan as I go; move it to `plan/done/` once Stage 4 is
fully implemented. Stage 5 (icons) then fills the `Action.icon` slot left here.

## Relationship to other plans
- [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) — Stage 4; Stage 5 (icons)
  populates the `icon` slot, Stage 6 (forms) reuses Actions for form buttons.
- [done/widget-popup-overlay.md](../done/widget-popup-overlay.md) — Stage 3; the
  menu/toolbar/popup/context-menu surface Actions plug into.
- [widget-focus-traversal.md](widget-focus-traversal.md) — Stage 2; the
  selection-driven keyboard routing that shortcuts sit in front of.
