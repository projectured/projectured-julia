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

## Step 2.0 — Widget-layer forward-mapping to graphics coordinates (prerequisite) ✅ partial

**Why this is here.** Placement is an *anchored-layout* problem, not a
screen-coordinate problem (decided with the user, 2026-06-27). The deep trigger
reader does **not** compute its own absolute position; instead the popup-open op
carries **what to anchor to** (a reference to the trigger) and **where, relative
to it** (an offset). A receiver maps the anchor **forward to the graphics domain**
via `map_reference_forward` — the existing mapper — and reads the resulting
coordinate. This is `anchored-layout.md`'s Phase 4 `resolve_target_position`, so
completing it unblocks **both** popups and AnchoredLayout.

**Design (corrected with the user, 2026-06-27): reuse `map_reference_forward`, no
new generic.** A first cut added a parallel `resolve_anchor_rect` generic; that
was reverted because it forced *every* wrapper (Sequential, Recursive, …) to
re-implement the composition `map_reference_forward` already does. The principle
is now documented on the mapper itself (`api/Projection.jl`):

- **The output domain may be coordinates.** A positioned widget's forward image
  is a `PointReference` (its top-left in the output canvas's frame), not a
  structural path.
- **Coordinates accumulate, paths stay paths.** A container shifts a
  `PointReference` child image by where it placed the child (entry offset + child
  canvas origin); a structural path image passes through unchanged. Distinguish by
  the *result*, never the child's type — so widgets nest in anything and vice
  versa.
- **No size in the reference.** The image is a *point*. The trigger bakes its own
  size into the relative offset (it knows its dimensions when it emits the open
  op), so "below the box" needs no rect.

**Verified gap (REPL probe).** Layout tier already forwarded via
`_children_forward`; every widget container and leaf stubbed `map_reference_forward`
to `nothing`. (`SequentialProjection.map_reference_forward` was also a no-op — the
one non-transparent wrapper — so the chain died there too.)

**Done (commit on this branch):**

- ✅ `SequentialProjection.map_reference_forward` composes through its steps
  (was a no-op; safe — stages wire their own `output.selection`, so nothing
  consumed it before).
- ✅ Widget leaf `WidgetButton` forward-maps the empty reference to
  `PointReference(0, 0)` (shared `_self_point`).
- ✅ Layouts (`_children_forward`) and `WidgetComposite` shift a `PointReference`
  result by the child's laid-out offset, via a shared `_forward_descend` /
  `_shift_child_image` (the `:children` vs `:elements` field is the only
  difference). `LayoutConstraint` needed no change (its output *is* its child's,
  so a point passes through). Paths pass through untouched — confirmed no
  regression (`test_printers` 162617/0, selection/nav/button/text/tooltip clean).
- ✅ `anchor_point(iomap, reference) -> (x, y) | nothing` — the single,
  non-recursive root helper that reads the resolved `PointReference`. Tested in
  `AnchorPointTest.jl` (8 assertions: buttons in a `VerticalLayout`, in a
  `WidgetComposite`, and a nested `layout > composite > button` — each matches the
  position walked from the output canvas tree; an unresolvable ref → `nothing`).

**Deferred (each lands with its consumer):**

- `WidgetSelect`'s mapper — folds into Step 3 when it drops `@_printer_only`
  (`_self_point`, one line).
- `Shell` (field-addressed: `content`/`menu_bar`/… with conditional entries, so
  not the indexed-field `_forward_descend` shape) and
  `SplitPane`/`TabbedPane`/`ScrollPane` (the last shifts by its scroll offset) —
  each gets its own self-contained method when a popup is anchored inside one.

## Step 2 — Anchored placement on top of the resolved point

With Step 2.0's `anchor_point` resolving an anchor reference to an absolute
point, placement is a thin slice: clamp + the trigger-supplied offset. Defer the
collision-avoiding engine to `anchored-layout.md`.

- The popup-open op carries `(anchor_ref, offset)` — *not* absolute coordinates.
  The receiver resolves `anchor_ref` to a point (Step 2.0) and adds `offset`.
  Because the image is a point, the trigger bakes its own size into `offset`
  (e.g. "below the box" = `(0, box_height + gap)`), so no rect is needed.
- Window-space conversion: the resolved point is window-relative; for a child
  popup window add the source window's screen origin. (If a backend can't give a
  reliable parent-window origin, the popup opens relative to the parent — a
  backend detail, not a placement-logic one.)
- Clamp the final origin to bounds. **Out of scope:** flip-to-opposite-side,
  perpendicular fallback, multi-popup stacking — those stay `anchored-layout.md`.

**Tests:** an anchor `(ref, offset)` whose resolved point is `(x, y)` gives popup
origin `(x, y) + offset`, clamped near an edge.

## Step 3 — `WidgetSelect` dropdown

Make the select interactive, the first end-to-end popup over the window route.

**Anchor wiring (decided with the user): capture `ctx.reference` (A) + a
content-root resolver seam (X).** The select captures its own document path at
**print time** from `ctx.reference` (the printer already threads it; the original
Lisp version captured a single path on the iomap the same way) and stores it on
its iomap. No op re-rooting — the captured path is already content-root-relative.

**3a — dismissal foundation. ✅ Done (commit `5d00aaf`).** `WindowFocusLost` event
(SDL + web) + `auto_dismiss` flag on `WindowDocument`/`OpenWindowOperation` +
WindowManager closes only `auto_dismiss` windows on focus-lost + `_apply_window_ops`
unpacks a `CompoundOperation` (so an option click can write the value AND close in
one bundled op). Tested in `TooltipTest`.

**3b — anchor-relative open + resolver seam. ✅ Written, loads (uncommitted →
commit pending; behavior-tested via 3c).**

- `OpenPopupOperation(id, anchor::ReferencePath, dx, dy, w, h, auto_dismiss,
  content)` in kernel `Operation.jl` — carries the anchor reference + the
  trigger-baked offset, not absolute coords. (Kernel placement avoids a module
  cycle: the select reader creates it, the resolver needs `anchor_point`.)
- `WidgetPopupResolverProjection` (`projection/higherorder/WidgetPopupResolver.jl`)
  — a content-root seam (mirrors `HoverProbe`): intercepts an `OpenPopupOperation`
  bubbling up, resolves `anchor` via `anchor_point(content_iomap, anchor)`, and
  emits `OpenWindowOperation` at `point + (dx, dy)`. That op bubbles to the
  WindowManager, which opens the window. `prepend_steps_to_op` passes the
  `OpenPopupOperation` up unchanged (the captured anchor must NOT be re-rooted).

**3c — the select + option items. ✅ Done.**

- **`WidgetSelect`** (`document/Widget.jl`, `projection/primitive/WidgetToGraphics.jl`).
  Added an `options::CellVector` field. Custom `WidgetSelectToGraphicsCanvasIoMap`
  carries the captured `ctx.reference` (the anchor) + the rendered
  `control_width`/`control_height`. Dropped `@_printer_only`;
  `map_reference_forward = _self_point` (the deferred Step 2.0 leaf, one line),
  plus a `SimpleIoMap` no-op for the invisible case. Reader: a left `MousePress`
  on the box → `OpenPopupOperation(id=:widget_popup, anchor=iomap.anchor, dx=0,
  dy=control_height+gap, width=control_width, height=#options·control_height,
  content=VerticalLayout(options), auto_dismiss=true)`. No options / disabled ⇒
  inert. Printer's closed state unchanged.
- **`WidgetOption`** (new widget: document + `WidgetOptionToGraphicsCanvas`).
  Renders a flat label row; reader on a left `MousePress` →
  `CompoundOperation([ReplaceReferencedValue(select, "value", value),
  CloseWindowOperation(popup_id)])`. Carries the target select (identity) + value
  + label + popup id. Identity-rooted `ReplaceReferencedValue` passes
  `prepend_steps_to_op`/`_prefix_op` unchanged, so it round-trips to the real
  select; the WindowManager's 3a CompoundOperation unpacking applies the close and
  passes the value write upward to `evaluate_operation`.
- Option list = a `VerticalLayout` of `WidgetOption`s, built by the select reader;
  each option points back at the select object for the write.
- Registered `WidgetOption` in the `WidgetToGraphics` factory.

**Tests (3c, `WidgetSelectTest.jl`, `test_widget_select_dropdown`):** clicking the
select emits an anchor-relative `OpenPopupOperation` whose content is a
`VerticalLayout` of options; an empty/disabled select is inert; the
`WidgetPopupResolver` seam maps the anchor forward and turns the click into an
absolute `OpenWindowOperation` (style `:floating`, `auto_dismiss`); clicking an
option emits the value-write + close `CompoundOperation` and applying the write
updates `select.value`; a non-left click is a no-op. (Focus-lost / `Esc`
dismissal of the popup window is covered by `TooltipTest`'s WindowFocusLost /
WindowCloseRequest testsets.)

**Not in 3c (→ Step 6):** a dedicated end-to-end `widget_popup` *example* needs the
screen/window-route example projection (WindowManager + `WidgetPopupResolver`
wrapping the content), which `make_widget_projection_example` does not yet wire.
The existing `widget_select` example gained `options` so the field is exercised,
but it renders the closed state only until Step 6 supplies the window-route
projection.

## Step 4 — `WidgetMenu` open-on-click + menu bar + context menu

**Direction (decided with the user, 2026-06-27): real menu bar first.** Survey of
the existing surface: `WidgetShell` already declares `menu_bar::WidgetMenu` (today
rendered as a non-interactive vertically-stacked band) and a dormant
`context_menu::WidgetMenu` (never rendered or triggered). `QMenuBar` is flagged ❌
in the gap analysis. A *menu-bar entry is just a clickable title that opens a
submenu* — so the building block is "a clickable thing that opens a `WidgetMenu`
popup", which the menu bar composes horizontally and a context menu reuses. The
shared `Action` (`QAction`) object is **deferred**: menu items take a plain
`action` callback for now (callbacks-now, Action-later).

**4a — clickable `WidgetMenuItem`.** `WidgetMenuItem` gains an optional
`action::Any` callback (same contract as `WidgetButton.action`, stored as a
primitive cell value via `setval!`). Item reader: a left click on an *enabled*
item → `CompoundOperation([InvokeWidgetActionOperation(item),
CloseWindowOperation(:widget_popup)])` (the close is a no-op for an inline menu);
disabled / non-left ⇒ inert. The `WidgetMenu` reader now routes `MousePress` to
the hit child via `_route_click_to_children` (it only routed scroll before).
Tested in `WidgetMenuTest.jl` (`test_widget_menu`).

**4b — submenu-opener + open-on-click. ✅ Done.** `WidgetMenuItem` gains an
optional `submenu::Any` field (default `nothing`). The item projection now carries
a custom `WidgetMenuItemToGraphicsCanvasIoMap` that captures `ctx.reference` (the
anchor) + the rendered item size at print time, and `map_reference_forward =
_self_point` (the Step 2.0 leaf) so a content-root resolver can anchor under it.
Item reader: a left click on an *enabled* item with a submenu → emits
`OpenPopupOperation(id=:widget_popup, anchor=self, dx=0, dy=item_height+gap,
content=submenu, auto_dismiss=true)` (reusing the 3c dropdown route), sized to the
submenu's rows; an item **without** a submenu keeps the 4a action+close behavior;
disabled / non-left ⇒ inert. Placement is "below, clamped" — flip/right-opening
for nested submenus is left to `anchored-layout.md`. Tested in `WidgetMenuTest.jl`
(submenu opens an anchor-relative popup; submenu takes precedence over an action;
disabled item inert; the `WidgetPopupResolver` seam maps the anchor forward to an
absolute `OpenWindowOperation`).

**4c — horizontal `menu_bar` in `WidgetShell`. ✅ Done** (chosen mechanism, with
the user: a horizontal-orientation flag on `WidgetMenu`, no new widget type).
`WidgetMenu` gains `orientation::Symbol` (default `:vertical`); its projection
lays items left-to-right when `:horizontal` (advancing by each item's rendered
width) and keeps the vertical stack otherwise. Crucially, the menu now **extends
`ctx.reference` per item** (`elements[i]`) and forward-maps `elements[i]` via the
shared `_forward_descend`, and `WidgetShell` **extends `ctx.reference` into
`menu_bar`** + gained a field-addressed `map_reference_forward` (descends the
leading field step to the child matched by identity, shifts via
`_shift_child_image`) — completing the Step 2.0 Shell deferral for the menu-bar
path. So a menu-bar entry's submenu anchor (`menu_bar.elements[i]`) resolves
through the shell. The `widget_shell` example's `menu_bar` is now `:horizontal`
with real File/Edit/Help submenus. Tested in `AnchorPointTest.jl` (horizontal menu
lays out left-to-right and forward-maps each entry; the same entry resolves
through a `WidgetShell`, vs the canvas-walked ground truth; `test_anchor_point`
17/17). The live click→popup needs Step 6's window-route example projection
(WindowManager + `WidgetPopupResolver` wrapping the shell).

**4d — context menu. ✅ Done.** A `WidgetContextMenu(child, menu)` wrapper (a
transparent single-child wrapper, modelled on `WidgetText`) renders `child`
unchanged and captures its own `ctx.reference` as the anchor
(`map_reference_forward = _self_point`, backward prepends `.child`). A **right**
click emits `OpenPopupOperation(anchor=self, dx=localX, dy=localY, content=menu)`
— the local click coordinates are the offset, so the resolver places the menu at
the pointer, reusing the whole 3c path with no pointer injection. Every other
event routes to `child` (its op re-rooted through `.child`). A disabled wrapper or
one with no menu ignores the right click. Registered in the `WidgetToGraphics`
factory. Tested in `WidgetContextMenuTest.jl` (21 assertions): right-click opens
the menu at the pointer; left-click reaches the child (its button action fires);
disabled / no-menu inert; the `WidgetPopupResolver` seam maps it to an absolute
`OpenWindowOperation` at the pointer. The dormant `WidgetShell.context_menu` field
can adopt this wrapper later. **Note:** the live click→popup window still needs
Step 6's window-route example projection (WindowManager + `WidgetPopupResolver`).

- Menu items reuse Stage-1 `enabled` (disabled items don't dismiss/activate) and
  Stage-2 selection (arrow-key menu navigation can ride selection later, routed
  to the popup window while it holds focus).

**Tests:** ✅ 4a + 4b (`test_widget_menu`, 29). ✅ 4c (`test_anchor_point`, 17 —
horizontal menu lays out + forward-maps; entry resolves through a `WidgetShell`).
✅ 4d (`test_widget_context_menu`, 21 — right-click opens at the pointer; left-click
reaches the child; resolver → absolute `OpenWindowOperation`). The live
click→popup-window flow (focus-lost / Esc dismissal of a real popup window) is
exercised once Step 6 wires the window-route example projection.

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
- [~] Step 2.0 — widget-layer `map_reference_forward` → graphics coords, reusing
      the existing mapper (no new generic). **Done:** Sequential composition,
      `WidgetButton` leaf point, layout + `Composite` offset accumulation,
      `anchor_point` helper, `AnchorPointTest` (8/8). **Deferred to consumers:**
      `WidgetSelect` mapper (Step 3), `Shell`/`SplitPane`/`TabbedPane`/`ScrollPane`.
      Principle documented on `map_reference_forward`. Also unblocks `anchored-layout.md`.
- [ ] Step 2 — anchored placement on the resolved point (`anchor_point` + clamp);
      op carries `(anchor_ref, offset)`, not coords; trigger bakes its size into offset
- [x] Step 3 — `WidgetSelect` dropdown. **3a ✅** (focus-lost + `auto_dismiss` +
      CompoundOperation unpacking, committed). **3b ✅** (anchor wiring = capture
      `ctx.reference` + `OpenPopupOperation` + `WidgetPopupResolver` seam →
      `OpenWindowOperation` via `anchor_point`). **3c ✅** (`WidgetSelect`
      options/iomap/reader/`_self_point`, new `WidgetOption` widget + projection,
      option-list, `WidgetSelectTest.jl`). The interactive `widget_popup` *example*
      (window-route example projection) is deferred to Step 6.
- [x] Step 4 — `WidgetMenu` open-on-click + right-click context menu. **4a ✅**
      (clickable `WidgetMenuItem` with `action`). **4b ✅** (optional `submenu`;
      submenu-opener emits `OpenPopupOperation` anchored below itself via the 3c
      route; `WidgetMenuItemToGraphicsCanvasIoMap` captures the anchor + size;
      `map_reference_forward = _self_point`; `test_widget_menu` 29/29). **4c ✅**
      (`WidgetMenu.orientation` horizontal flag; menu + `WidgetShell` extend
      `ctx.reference` and forward-map `elements[i]` / `.menu_bar`, completing the
      Step 2.0 Shell deferral; `widget_shell` example menu bar now horizontal with
      submenus; `test_anchor_point` 17/17). **4d ✅** (`WidgetContextMenu` wrapper;
      right-click → `OpenPopupOperation` at the pointer via a local-offset anchor;
      left-click routes to the child; `test_widget_context_menu` 21/21). The live
      menu-bar / context-menu click→popup window needs Step 6's window-route
      example projection (WindowManager + `WidgetPopupResolver`).
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
