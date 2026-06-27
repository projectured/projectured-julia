# Popup / overlay layer

> **Status: planning / not started.** Detailed plan for **Stage 3** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Popup / overlay
> layer"). Generated 2026-06-27; **architecture revised 2026-06-27** to use the
> existing `WindowManager` window route instead of an in-window `StackLayout`
> overlay (see "Architectural decision" — the original objection to windows did
> not hold up against the code). Builds on Stage 1
> ([widget-interaction-state.md](widget-interaction-state.md), `enabled`) and
> Stage 2 ([widget-focus-traversal.md](widget-focus-traversal.md),
> selection-driven keyboard routing).

## Goal

A widget-level mechanism to float a child **over** other widgets, anchored to a
trigger, dismissed on **Esc**, **outside-click**, or the window's own
**close/focus-lost** signal — the substrate for:

- **Dropdown lists** — `WidgetSelect` opens a real option list (today it renders
  the closed value + chevron only).
- **Context menus / click menus** — `WidgetMenu` opens on click / right-click
  (today it renders its items inline, always visible).
- **Modal dialogs** — `WidgetDialog` (backdrop + centered card + button row), and
  convenience `WidgetMessageBox` / `WidgetInputDialog`.

This unblocks `QDialog`, `QMessageBox`, the standard dialogs, the editable
combobox, and context menus (Stage 4).

---

## Architectural decision: the WindowManager window route (revised)

There are two substrates for "draw something on top". **This plan uses the
existing `WindowManager` window route** — generalizing the float that the
**tooltip** already performs — rather than a new in-window `StackLayout` overlay.

**Why the earlier in-window choice was reconsidered.** The first draft chose
in-window overlays because "a popup in its own window cannot observe an
outside-click — `WindowManager` routes by a static `EventEnvelope.window_id` and
has no topmost-window coordinate hit-test." That premise was wrong about what
dismissal needs: an outside-click on a real popup window does **not** require a
coordinate hit-test on the main window — it surfaces as a **focus-lost / close
event on the popup's own window**, which becomes a `CloseWindowOperation`. This
is exactly how native menus and combobox dropdowns dismiss. The machinery for it
is almost entirely in place:

- The backends already emit a per-window close event — `WindowCloseRequest`,
  carrying the window id (SDL `SDL_WINDOWEVENT_CLOSE` → `ProjecturedSdl.jl:1936`,
  web → `ProjecturedWeb.jl:585`).
- `WindowManagerProjection`'s reader already turns a window-level backend event
  into a window operation: `WindowResizeEvent` → `ResizeWindowOperation`
  (`WindowManager.jl:69-74`). The close case is the identical pattern and is
  currently the only missing wire (see Step 1).
- The **tooltip already opens and closes its float as a window** via
  `OpenWindowOperation` / `CloseWindowOperation` bubbling to
  `WindowManagerProjection` (`TooltipDecorator.jl:11-13, 26`). Stage 3 reuses
  that open/close-via-operation plumbing; the only thing the tooltip lacks (and
  popups need) is interactive dismissal — the close/focus-lost events.

**Why windows over the in-window stack.** Reusing the window route means one
mechanism for every float (tooltip, dropdown, menu, dialog, inspector), real
clipping/compositing handled by the existing `ScreenDocument` → window pipeline,
and no new z-stack reader. The in-window `StackLayout` path would duplicate a
second compositing-and-dismissal mechanism alongside the window one.

⇒ **Open Stage-3 popups as `WindowDocument`s through `OpenWindowOperation`;
dismiss them by translating the popup window's `WindowCloseRequest` / focus-lost
event into `CloseWindowOperation`.** Modality (Step 5) is enforced in
`WindowManager` by tracking a modal window id and not routing envelopes to other
windows while it is set — no per-widget input-swallowing needed.

The one genuinely missing backend signal is **focus-lost**: SDL delivers
`SDL_WINDOWEVENT_FOCUS_LOST` (sub-event 12) but it is not mapped today (only the
close button, sub-event 14, is). Step 1 adds it. Until/unless a backend provides
focus-lost, outside-click dismissal degrades to Esc + an explicit
click-catcher; with it, dismissal is automatic.

---

## Background (verified facts)

1. **WindowManager substrate.** `ScreenDocument.windows::CellVector` of
   `WindowDocument{id,x,y,w,h,style,content}`; open/close mutate it
   (`WindowManager.jl:97-173`). Re-issuing open with the same `id` updates in
   place — how the inspector follows the mouse (`HoverProbe.jl:112-130`).
2. **Window event → operation already exists.** The reader maps
   `WindowResizeEvent` → `ResizeWindowOperation` resolving the window by id
   (`WindowManager.jl:69-74`), and applies `OpenWindowOperation` /
   `CloseWindowOperation` (`:78-83`). Adding the close-request branch is the same
   shape.
3. **`WindowCloseRequest` is emitted but not yet consumed.** Defined in
   `Screen.jl:139` (its docstring already *says* "Readers translate it into a
   document mutation that removes the matching `WindowDocument`" — but no reader
   does this yet; confirmed zero handlers in the domain/projection layer). Both
   backends already produce it with the window id.
4. **Tooltip is the working window-float precedent.** `TooltipDecorator` floats
   `source.child` in its own window by emitting `OpenWindowOperation` /
   `CloseWindowOperation`; state (armed / open) is held per `source.id` on the
   projection instance (`TooltipDecorator.jl:11-17, 26`). Non-interactive and
   trigger-driven, but the open/close plumbing is exactly what popups need.
5. **WidgetMenu / WidgetSelect today.** `WidgetMenu` renders all items inline,
   always; reader only routes `MouseScroll` (`WidgetToGraphics.jl:1064-1093`).
   `WidgetSelect` renders the closed state only and is `@_printer_only` (no
   reader, no `options` field) (`Widget.jl:959-1000`,
   `WidgetToGraphics.jl:2885-2910`).
6. **Esc** is delivered as `KeyDown(:escape)` (SDL `ProjecturedSdl.jl:349`, web
   `ProjecturedWeb.jl:140`) and already consumed by gesture bindings elsewhere
   (`ProjectionConfiguring.jl:505`). Free at the widget layer.
7. **Focus-lost is not yet wired.** SDL has `SDL_WINDOWEVENT_FOCUS_LOST`
   (sub-event 12); only close (14) and resize (5) are mapped today
   (`ProjecturedSdl.jl:1931-1949`). Step 1 adds focus-lost as a new inner event
   (`WindowFocusLost`) carried in the same `EventEnvelope` shape.
8. **`anchored-layout.md` is entirely unimplemented** (audit: ALL OPEN). Stage 3
   "reuses its design" — this plan takes a **minimal placement** subset now
   (screen-space window x/y for the popup) and leaves the full
   collision-avoiding engine to that plan.
9. **Selection routing (Stage 2)** already delivers keyboard events to the
   selected widget; while a popup window holds focus, `Esc`/arrow keys route to
   it through the same window-id path.

---

## Step 1 — Window close → `CloseWindowOperation` (the core wire) ✅

The one new piece of routing: make the native window-close event remove the
window, completing the event→operation pattern resize already follows.

- **`WindowCloseRequest` branch.** ✅ Done. In `WindowManagerProjection`'s reader,
  before the inner copier: if the envelope's inner event is a
  `WindowCloseRequest`, resolve the window by `env.window_id` and apply a
  `CloseWindowOperation` via `_apply_close!` (the same dual input+output mutation
  the manager performs for a close bubbling up from below), returning
  `Change(gesture, nothing)`. This makes the native close button work for *every*
  window, independent of Stage 3. Also corrected the `WindowCloseRequest`
  docstring (`Screen.jl`), which previously claimed a reader already handled it.
  Tested in `TooltipTest.jl` (`WindowCloseRequest removes the matching window`,
  9 assertions): popup closes leaving main; unknown id is a no-op; main can be
  closed too, leaving zero windows.

**Design note — apply directly, don't bubble.** `CloseWindowOperation` is
*intercepted* by the manager (it must mutate both the input screen and the
mirrored output `CellVector`), not handled by `evaluate_operation`. So the
close-request branch applies it in place rather than returning it upward.

**Deferred to Step 3 (folded in, where they gain a real consumer):** the
focus-lost dismissal pair was pulled out of Step 1 because it is speculative
until a popup exists to dismiss — and it cannot land *safely* on its own (an
unconditional focus-lost→close would close the main window whenever the app
loses focus, so it needs the `auto_dismiss` gate, which in turn needs a popup
to mark). It therefore ships with the first popup:

- **Focus-lost event.** Add a `WindowFocusLost` inner event (`Screen.jl`, beside
  `WindowCloseRequest`); map SDL `SDL_WINDOWEVENT_FOCUS_LOST` (sub 12) and the
  web `blur`. In the WindowManager reader, treat it like close **only for windows
  flagged auto-dismiss**, so the main window losing focus does not self-close.
- **Popup marker.** `OpenWindowOperation` / `WindowDocument` gains an optional
  `auto_dismiss::Bool` (default `false`). Tooltips and the main window stay
  `false`; dropdowns/menus/context-menus open with `true`.
- **Open helper.** Factor the tooltip's "build a `WindowDocument` and emit
  `OpenWindowOperation`" into a reusable `open_popup(content, x, y, w, h;
  auto_dismiss=true, modal=false)` once Step 3 needs it.

**Tests (done):** a `WindowCloseRequest` for a window id removes exactly that
window from input and output; an unknown id is a no-op; the main window can be
closed. (`WindowFocusLost` / `open_popup` round-trip tests move to Step 3.)

## Step 2.0 — Complete widget-layer forward-mapping to graphics coordinates (prerequisite)

**Why this is here.** Placement is an *anchored-layout* problem, not a
screen-coordinate problem (decided with the user, 2026-06-27). The deep trigger
reader does **not** compute its own absolute position; instead the popup-open op
carries **what to anchor to** (a reference path to the trigger in the document
domain) and **where, relative to it** (a placement/offset). A receiver then maps
the anchor **forward to the output (graphics) domain** via
`map_reference_forward`, walks the resulting graphics path accumulating nested
canvas `(x, y)` offsets to get the anchor's **absolute** rect, and adds the
relative offset. This is exactly `anchored-layout.md`'s Phase 4
`resolve_target_position`, so completing it unblocks **both** popups and
AnchoredLayout.

**Verified gap (REPL probe, 2026-06-27).** The forward path is sound *in
principle* — at the root a reference should map completely forward to the output
domain — but it is **not implemented across the widget layer**:

- ✅ **Layout tier already forwards.** `Horizontal`/`Vertical`/`Grid`/`Flow`/
  `Stack`/`Constraint` layouts delegate a `children[i]/…` reference down via
  `_children_forward`.
- ❌ **Widget tier returns `nothing`.** Every widget container (`Composite`,
  `Shell`, `SplitPane`, `TabbedPane`, `ScrollPane`) and every leaf (`Button`,
  `Select`, `Checkbox`, `Label`, `Text`) stubs `map_reference_forward` to
  `nothing`, so the chain dies the moment it reaches a widget and no coordinate
  surfaces. (The focus ring / text cursor are drawn by each widget reading its
  *own* selection at print time, which is why this forward path was never
  needed before.)

**The work (two conventions):**

- **Leaf widgets** — given a reference that targets the widget, return a
  forwarded reference that resolves to the widget's own output `GraphicsCanvas`
  (so `x/y/w/h` are readable). A shared convention (likely via the projection
  macro / a default) rather than per-leaf boilerplate.
- **Widget containers** — delegate into the addressed child, the same way the
  layout tier's `_children_forward` already does. Do `Composite` and `Shell`
  first (the containers a `WidgetSelect` actually sits in); defer
  `SplitPane`/`TabbedPane`/`ScrollPane` until a popup is nested in one.
- **Receiver helper** — `resolve_anchor_rect(root_iomap, anchor_ref) -> (x,y,w,h)`:
  `map_reference_forward`, then walk the returned graphics reference accumulating
  canvas offsets to an absolute window-relative rect. Return the *graphics*
  reference and accumulate by walking the output tree (matching the existing
  `_children_forward` convention and anchored-layout's "resolve to a canvas, read
  position cells"), rather than having each container try to compute absolute
  coords itself — it only knows its child's *relative* offset.

**Tests:** a reference to a leaf widget inside `Shell`→…→`Composite`→layout
resolves, at the root iomap, to that widget's absolute `(x, y, w, h)` matching
its rendered position; an unresolvable reference returns `nothing`.

## Step 2 — Anchored placement on top of the resolved rect

With Step 2.0 resolving an anchor reference to an absolute rect, placement is the
thin **minimal** slice of `anchored-layout.md`; defer the collision-avoiding
engine.

- The popup-open op carries `(anchor_ref, placement, offset)` — *not* absolute
  coordinates. The receiver resolves `anchor_ref` to a rect (Step 2.0) and then
  `anchor_below(rect; gap)` / `anchor_at(point)` compute the popup origin,
  clamped to bounds.
- Window-space conversion: the resolved rect is window-relative; for a child
  popup window add the source window's screen origin. (If a backend can't give a
  reliable parent-window origin, the popup opens relative to the parent — a
  backend detail, not a placement-logic one.)
- **Out of scope:** flip-to-opposite-side, perpendicular fallback, multi-popup
  stacking — those stay `anchored-layout.md`. Note the limitation in code.

**Tests:** an anchor `(ref, :below, gap)` whose resolved rect is `(x,y,w,h)` gives
popup origin `≈ (x, y+h+gap)`, clamped near an edge.

## Step 3 — `WidgetSelect` dropdown

Make the select interactive, the first end-to-end popup over the window route.

- **Document.** Add `options::CellVector` (and an optional open marker);
  `value` stays the displayed/selected entry.
- **Reader (new — drop `@_printer_only`).** `MousePress` on the closed box →
  `open_popup(content = a menu/list of the options; anchor = (self_ref, :below,
  gap); auto_dismiss=true)` — the op carries the *anchor reference* to the select,
  not absolute coords; the receiver resolves it via Step 2.0. The option list is
  an ordinary widget subtree rendered as the popup window's content. Picking an
  option emits `ReplaceReferencedValue(self, "value", option)` **and**
  `CloseWindowOperation` (a `CompoundOperation`; the WindowManager must unpack the
  compound to catch the close — see below).
- **Op bubbling (verified).** `prepend_steps_to_op` returns unknown op types and
  identity-rooted `ReplaceReferencedValue` unchanged (the `else` branch,
  `OperationRerooting.jl:73`), so an `OpenWindowOperation` from the deep select
  reader bubbles up to the WindowManager untouched, and the option click's
  identity-rooted value-write round-trips to the select. **One required add:** the
  WindowManager reader must unpack a `CompoundOperation` to apply Open/Close ops
  nested in it (today it only matches a top-level Open/Close).
- **Printer.** Unchanged closed state; the open list lives in the popup window,
  not the select's own canvas.
- **Re-rooting.** The option list's reader ops target the popup window's content
  subtree; re-root them back to the select via the open op's recorded reference,
  the way container readers re-root child ops (`prepend_steps_to_op`).

**Tests:** clicking the select opens the option-list window; clicking an option
round-trips `value` and closes; clicking elsewhere (focus-lost) closes without
changing value; `Esc` closes.

## Step 4 — `WidgetMenu` open-on-click + context menu

- `WidgetMenu` gains a click-to-open path: a trigger (a `WidgetButton`/menu-bar
  entry, Stage 4) emits `open_popup(menu, anchor_below(trigger_rect))`. The
  menu's existing inline-item printer becomes the popup window's content; a menu
  item click emits its action + `CloseWindowOperation`.
- **Context menu:** a right-click (`MousePress(:right, …)`) on a widget that
  declares a context menu emits `open_popup(menu, anchor_at(pointer))`.
- Menu items reuse Stage-1 `enabled` (disabled items don't dismiss/activate) and
  Stage-2 selection (arrow-key menu navigation can ride selection later, routed
  to the popup window while it holds focus).

**Tests:** a click opens the menu as a popup window; an item click runs its
action and closes; outside-click (focus-lost) / Esc close; a right-click opens a
context menu at the pointer.

## Step 5 — `WidgetDialog` (modal) + convenience dialogs

- **`WidgetDialog`** document: `title`, `content`, `buttons::CellVector` (of
  `WidgetButton`). Opened as a **modal** popup window (`open_popup(...,
  modal=true)`) centered on screen, over a full-screen semi-transparent
  **backdrop window** at a lower z (or the dialog window's own full-bleed scrim
  behind a centered card).
- **Modality is a WindowManager concern.** While a modal window is open,
  `WindowManager` tracks its id and **drops envelopes routed to any other
  window** — base content receives no events without any per-widget swallowing.
  This reuses the existing `window_id` routing rather than fighting it.
- **Dismissal.** `Esc` closes; backdrop-click closes (configurable for "must
  choose"); a button's action closes via `CloseWindowOperation`. A modal window
  ignores focus-lost auto-dismiss (it is dismissed by an explicit choice, not by
  clicking away).
- **Convenience.** `WidgetMessageBox(title, message; buttons)` and
  `WidgetInputDialog(title, prompt; value)` built on `WidgetDialog` + existing
  `WidgetText`/`WidgetButton`.

**Tests:** opening a dialog dims the base (backdrop window) and centers the card;
`Esc` and backdrop-click close; a button action closes and fires; while modal, an
envelope targeting the base window is dropped (does not reach base widgets).

## Step 6 — Example, sweep, docs

- A `widget_popup` example: a select + a "menu" button + a "show dialog" button
  in a `VerticalLayout`, with one popup pre-opened (an extra `WindowDocument` in
  the example's `ScreenDocument`) so the popup renders in the sweep/screenshot.
  Register + export + add to the `examples` list (as for `widget_disabled` /
  `widget_focus`).
- Document the popup model in
  [documentation/document/widget.md](../../documentation/document/widget.md): the
  window route (popups are `WindowDocument`s via `OpenWindowOperation`), the
  dismissal events (`WindowCloseRequest` / `WindowFocusLost` → `CloseWindowOperation`),
  the `auto_dismiss` / `modal` flags, and how this relates to the tooltip float.

---

## Risks / watch-outs

- **Focus-lost coverage per backend.** Outside-click auto-dismiss depends on the
  backend delivering focus-lost. SDL has it (sub-event 12); the web `blur` is the
  analogue. If a backend can't, dismissal falls back to Esc + an explicit
  click-catcher. Don't assume every backend wires it on day one.
- **The main window must not self-close.** Focus-lost arrives for *any* window,
  including the main one when a popup takes focus. Gate auto-dismiss on the
  `auto_dismiss` flag so only popups close on focus-lost.
- **Event re-rooting into the popup content.** The popup content is a detached
  subtree hosted in a separate `WindowDocument`; its reader ops must be re-rooted
  to wherever the popup content is addressed, exactly as container readers
  re-root child ops via `prepend_steps_to_op`. Get the popup's reference path
  right.
- **Modal routing in WindowManager.** "Drop envelopes to non-modal windows while
  a modal is open" must still let the modal window's own events through — track
  the modal id and compare against `env.window_id`, allowing only that window
  (and its backdrop) through.
- **Placement is anchored-layout, resolved by a receiver.** The trigger reader
  must **not** try to compute its own absolute coords (it only has local ones);
  it carries an *anchor reference* + relative offset, and the receiver forward-
  maps + accumulates offsets (Step 2.0). The placement *policy* is minimal — no
  flip/collision avoidance, near an edge it clamps (may overlap the trigger).
  Acceptable for v1; full behavior is `anchored-layout.md`. Comment the limitation.
- **Don't duplicate compositing.** Resist re-introducing an in-window
  `StackLayout` overlay path alongside the window route — one mechanism (windows)
  for every float keeps the inspector/tooltip/popup story uniform.

## Step status

- [x] Step 1 — `WindowCloseRequest` → `CloseWindowOperation` branch in
      WindowManager (native close button works for every window); tested in
      `TooltipTest.jl`. **Deferred to Step 3:** `WindowFocusLost` event (SDL +
      web) + `auto_dismiss` flag + `open_popup` helper — coupled, and consumer-less
      until the first popup, so they land with the dropdown.
- [ ] Step 2.0 — **prerequisite:** complete widget-layer `map_reference_forward`
      to graphics coordinates (leaf convention + `Composite`/`Shell`; defer
      `SplitPane`/`TabbedPane`/`ScrollPane`) + `resolve_anchor_rect` receiver
      helper. Verified gap: layout tier forwards, all widget projectors return
      `nothing`. Reusable — also unblocks `anchored-layout.md` Phase 4.
- [ ] Step 2 — anchored placement on the resolved rect (`anchor_below` /
      `anchor_at`, clamp); op carries `(anchor_ref, placement, offset)`, not coords
- [ ] Step 3 — `WidgetSelect` dropdown (options + open-popup + pick→value+close;
      WindowManager unpacks `CompoundOperation` for nested Open/Close);
      **also lands `WindowFocusLost` + `auto_dismiss` + `open_popup` from Step 1**
- [ ] Step 4 — `WidgetMenu` open-on-click + right-click context menu
- [ ] Step 5 — `WidgetDialog` modal (backdrop window + centered card + buttons,
      modality enforced by WindowManager) + MessageBox/InputDialog
- [ ] Step 6 — `widget_popup` example, sweep, docs

## Relationship to other plans

- [anchored-layout.md](anchored-layout.md) — **shared foundation, not just
  adjacent.** Step 2.0 (forward-mapping a reference to a graphics rect) is exactly
  that plan's Phase 4 `resolve_target_position`; doing it here unblocks
  AnchoredLayout too. Step 2 then takes only the minimal placement slice; the full
  collision-avoiding engine stays that plan's scope.
- [tooltip.md](tooltip.md) — the WindowManager float precedent this plan
  generalizes: tooltips open/close a window via operations already; popups add
  the interactive dismissal (close/focus-lost) on top of the same route.
- [multiple-windows.md](../done/multiple-windows.md) — the WindowManager /
  `ScreenDocument` multi-window substrate popups ride on.
- [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) — Stage 4 (Actions, menu
  bar, context menus, shortcuts) builds directly on this popup layer.
