# Popup / overlay layer

> **Status: planning / not started.** Detailed plan for **Stage 3** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Popup / overlay
> layer"). Generated 2026-06-27 against the current tree. Builds on Stage 1
> ([widget-interaction-state.md](widget-interaction-state.md), `enabled`) and
> Stage 2 ([widget-focus-traversal.md](widget-focus-traversal.md),
> selection-driven keyboard routing).

## Goal

A widget-level mechanism to float a child **over** other widgets, anchored to a
trigger, dismissed on **Esc** or **outside-click** — the substrate for:

- **Dropdown lists** — `WidgetSelect` opens a real option list (today it renders
  the closed value + chevron only).
- **Context menus / click menus** — `WidgetMenu` opens on click / right-click
  (today it renders its items inline, always visible).
- **Modal dialogs** — `WidgetDialog` (backdrop + centered card + button row), and
  convenience `WidgetMessageBox` / `WidgetInputDialog`.

This unblocks `QDialog`, `QMessageBox`, the standard dialogs, the editable
combobox, and context menus (Stage 4).

---

## Architectural decision: in-window overlay (StackLayout), not new windows

There are two substrates for "draw something on top". **This plan uses in-window
overlays.**

- **`WindowManager` (separate OS windows)** already floats the **tooltip** and the
  **reference inspector** (`WindowManager.jl`, `Screen.jl` — `OpenWindowOperation`/
  `CloseWindowOperation` push/pop `WindowDocument`s; `HoverProbe.jl:95-130` and
  `TooltipDecorator.jl:83-131` re-issue an open op each frame to reposition). But
  events are routed to a window by a **static `EventEnvelope.window_id`**
  (`Screen.jl:124-127`), and there is **no coordinate hit-test for the topmost
  window**. So a popup in its own window **cannot observe an outside-click** on the
  main window — exactly what dismissal needs. The existing overlays sidestep this
  because they are non-interactive (tooltip) or hover-driven (inspector).

- **`StackLayout` (in-window z-stack)** draws children at a shared origin, **list
  order = z-order** (`Layout.jl:176-181`, printer `LayoutToGraphics.jl:1053-1115`).
  A popup hosted as the top child of a stack lives in the **same** window as its
  trigger, so the one event stream sees every click — outside-click and Esc are
  trivially observable by a reader at the overlay layer. `StackLayout` itself has
  **no reader** (no dismissal), so the dismissal logic is the new piece.

⇒ **Use an in-window overlay host** (StackLayout-style) for all Stage-3 popups.
Separate windows stay the right tool for OS-level, non-interactive floats
(tooltips). Implementing topmost-window hit-test routing in `WindowManager` is a
larger, separate effort and is **out of scope** here.

---

## Background (verified facts)

1. **WindowManager substrate.** `ScreenDocument.windows::CellVector` of
   `WindowDocument{id,x,y,w,h,style,content}`; open/close mutate it
   (`WindowManager.jl:97-173`). Re-issuing open with the same `id` updates in
   place — how the inspector follows the mouse (`HoverProbe.jl:112-130`).
2. **No outside-click / hit-test.** Routing is by `EventEnvelope.window_id`
   (`Screen.jl:124-127`); window order "carries no visual semantics"
   (`Screen.jl:43-44`). Confirmed gap vs. the Stage-3 dismissal requirement.
3. **StackLayout** z-stacks reactively (`LayoutToGraphics.jl:1053-1115`); no reader.
4. **WidgetMenu** renders all items inline, always; reader only routes
   `MouseScroll` (`WidgetToGraphics.jl:1064-1093`). **WidgetSelect** renders the
   closed state only and is `@_printer_only` (no reader, no `options` field)
   (`Widget.jl:959-1000`, `WidgetToGraphics.jl:2885-2910`).
5. **Esc** is delivered as `KeyDown(:escape)` (SDL `ProjecturedSdl.jl:349`, web
   `ProjecturedWeb.jl:140`) and already consumed by gesture bindings elsewhere
   (`ProjectionConfiguring.jl:505`). Free at the widget layer.
6. **`anchored-layout.md` is entirely unimplemented** (audit: ALL OPEN). Stage 3
   "reuses its design" — this plan takes a **minimal placement** subset now and
   leaves the full collision-avoiding engine to that plan.
7. **Selection routing (Stage 2)** already delivers keyboard events to the
   selected widget and `Esc` will follow the same path; the overlay host sits at
   the outer seam (like the hover tracker / focus wrap).

---

## Step 1 — Overlay host + dismissal (the core mechanism)

The one new primitive: a host that draws `base` content and, when a popup is
active, composites the popup on top and routes/dismisses events.

- **Document.** `WidgetOverlay` (or reuse `StackLayout` + a thin wrapper): a
  `base::Document` plus an optional `overlay::Document` and the overlay's
  screen-space `origin::Point2D`. When `overlay === nothing` it is a transparent
  passthrough to `base`.
- **Open state.** Where "which popup is open" lives must be reactive. Recommended:
  a single overlay slot on the host (one popup at a time per window), written by an
  **`OpenOverlayOperation(content, origin)`** / **`CloseOverlayOperation()`**
  (mirroring `OpenWindowOperation`, but in-document). Triggers emit the open op;
  dismissal emits the close op.
- **Printer.** Passthrough when empty; else a `StackLayout`-style composite: base
  at z0, overlay wrapped at `origin` on top. Reuse `LayoutToGraphics`'s
  `_wrap_child` / canvas-compositing helpers.
- **Reader (dismissal + routing).** On `MousePress`: hit-test the overlay's bounds
  — inside → route to the overlay (re-rooted), outside → `CloseOverlayOperation`.
  On `KeyDown(:escape)` → `CloseOverlayOperation`. Coordless events route to the
  overlay while open (it holds focus). This is the piece `StackLayout` lacks.

**Tests:** with an overlay open, a click inside reaches the overlay's reader; a
click outside emits `CloseOverlayOperation`; `Esc` closes it; with no overlay the
host is a transparent passthrough (printer + reader unchanged vs. base).

## Step 2 — Minimal anchored placement

Popups need a screen position relative to their trigger. Take a **minimal** subset
of `anchored-layout.md` now; defer the collision-avoiding engine.

- A helper `anchor_below(trigger_rect; gap) -> Point2D` (and `anchor_at(point)`
  for context menus) computing the overlay origin. Clamp to the host bounds
  (`ProjectionContext` already threads `available_width/height`).
- The trigger supplies its own rect (it knows its canvas bounds at print time);
  the open op carries the computed `origin`.
- **Out of scope:** flip-to-opposite-side, perpendicular fallback, multi-popup
  stacking — those are `anchored-layout.md`. Note the limitation in code.

**Tests:** a dropdown opened from a trigger at `(x,y,h)` gets `origin ≈ (x, y+h+gap)`;
near the bottom edge it is clamped within the host.

## Step 3 — `WidgetSelect` dropdown

Make the select interactive, the first end-to-end popup.

- **Document.** Add `options::CellVector` and (optional) an open marker;
  `value` stays the displayed/selected entry.
- **Reader (new — drop `@_printer_only`).** `MousePress` on the closed box →
  `OpenOverlayOperation(content = a WidgetMenu/list of the options,
  origin = anchor_below(self_rect))`. While open, picking an option emits
  `ReplaceReferencedValue(self, "value", option)` **and** `CloseOverlayOperation`
  (a `CompoundOperation`).
- **Printer.** Unchanged closed state; the open list is rendered by the overlay
  host, not the select itself.

**Tests:** clicking the select opens the option list; clicking an option
round-trips `value` and closes; clicking elsewhere closes without changing value;
`Esc` closes.

## Step 4 — `WidgetMenu` open-on-click + context menu

- `WidgetMenu` gains a click-to-open path: a trigger (a `WidgetButton`/menu-bar
  entry, Stage 4) emits `OpenOverlayOperation(content = the menu, origin = …)`.
  The menu's existing inline-item printer becomes the overlay content; a menu item
  click emits its action + `CloseOverlayOperation`.
- **Context menu:** a right-click (`MousePress(:right, …)`) on a widget that
  declares a context menu emits `OpenOverlayOperation(menu, anchor_at(pointer))`.
- Menu items reuse Stage-1 `enabled` (disabled items don't dismiss/activate) and
  Stage-2 selection (arrow-key menu navigation can ride selection later).

**Tests:** a click opens the menu as an overlay; an item click runs its action and
closes; outside-click / Esc close; a right-click opens a context menu at the
pointer.

## Step 5 — `WidgetDialog` (modal) + convenience dialogs

- **`WidgetDialog`** document: `title`, `content`, `buttons::CellVector` (of
  `WidgetButton`). Rendered as an overlay whose `origin` centers it, **behind a
  full-bleed semi-transparent backdrop** (a z0 scrim in the overlay composite, the
  dialog card at z1). Modal = while open, base content does not receive events
  (the overlay reader swallows non-overlay clicks instead of routing to base).
- **Dismissal.** `Esc` closes; backdrop-click closes (configurable for "must
  choose"); a button's action closes via `CloseOverlayOperation`.
- **Convenience.** `WidgetMessageBox(title, message; buttons)` and
  `WidgetInputDialog(title, prompt; value)` built on `WidgetDialog` + existing
  `WidgetText`/`WidgetButton`.

**Tests:** opening a dialog dims the base and centers the card; `Esc` and
backdrop-click close; a button action closes and fires; a click on the dimmed
base while modal is swallowed (does not reach base widgets).

## Step 6 — Example, sweep, docs

- A `widget_popup` example: a select + a "menu" button + a "show dialog" button in
  a `VerticalLayout`, with one popup pre-opened so the overlay renders in the
  sweep/screenshot. Register + export + add to the `examples` list (as for
  `widget_disabled` / `widget_focus`).
- Document the overlay model in
  [documentation/document/widget.md](../../documentation/document/widget.md):
  in-window overlay vs. WindowManager windows; the open/close ops; dismissal rules.

---

## Risks / watch-outs

- **One-popup-at-a-time vs. nested.** A select inside a dialog means a popup over a
  popup. Start with a single overlay slot per host and document the limit; nested
  overlays (a stack of overlays) are a follow-up.
- **Event re-rooting into the overlay.** The overlay content is a detached subtree
  at `origin`; its reader ops must be re-rooted to wherever the overlay content is
  addressed (the host's overlay slot), exactly as container readers re-root child
  ops via `prepend_steps_to_op`. Get the overlay's reference path right.
- **Modal event-swallowing.** "Click on dimmed base is swallowed" must not also
  swallow the dialog's own clicks — hit-test the dialog card first, backdrop
  second, then swallow.
- **Placement is minimal.** No flip/collision avoidance — a dropdown near the
  bottom edge clamps (may overlap the trigger). Acceptable for v1; full behavior is
  `anchored-layout.md`. `log`/comment the limitation; don't let it read as complete.
- **Don't reach for new windows.** Resist solving dismissal by adding
  topmost-window hit-test to `WindowManager` — that is a separate, larger change;
  in-window overlay is the scoped path.

## Step status

- [ ] Step 1 — overlay host + dismissal (Esc / outside-click), in-window composite
- [ ] Step 2 — minimal anchored placement (`anchor_below` / `anchor_at`, clamp)
- [ ] Step 3 — `WidgetSelect` dropdown (options + open op + pick→value+close)
- [ ] Step 4 — `WidgetMenu` open-on-click + right-click context menu
- [ ] Step 5 — `WidgetDialog` modal (backdrop + centered card + buttons) + MessageBox/InputDialog
- [ ] Step 6 — `widget_popup` example, sweep, docs

## Relationship to other plans

- [anchored-layout.md](anchored-layout.md) — Step 2 takes a minimal placement
  subset; the full collision-avoiding engine stays that plan's scope.
- [tooltip.md](tooltip.md) — the WindowManager float precedent; tooltips keep using
  separate windows (non-interactive), not this in-window overlay.
- [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) — Stage 4 (Actions, menu
  bar, context menus, shortcuts) builds directly on this overlay layer.
