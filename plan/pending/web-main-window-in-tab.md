# Web: render the main window in the entered tab (no Launch button)

## Goal

When a user navigates to the web backend URL (e.g. `http://127.0.0.1:8080`),
the **main (first) editor window must appear immediately in that same browser
tab** — no "Launch" button to click, and **no popup for the main window**. The
tab where the URL was entered becomes the main window's paint surface.

Additional windows (a second `run_web_example(["json","xml"])` window, tooltips,
floating windows) remain browser popups, since `window.open` is the only way to
get a second OS-level window — but those are out of the critical path for the
common single-window case.

## Current behavior (and why the button/popups exist)

[package/web/assets/index.html](../../package/web/assets/index.html) serves a
*host* page: a disabled **"Launch editor windows"** button plus status text. The
tab itself never paints the editor.

[package/web/assets/client.js](../../package/web/assets/client.js) flow:

1. Load fonts, open the WebSocket, enable the Launch button on `ws.onopen`.
2. Server sends `{type:"update", full:[…], patches:[…], close:[…]}`. A `launched`
   flag gates painting — until Launch is clicked, `full` windows are only stored
   in `windowsMeta`, never painted (`handleUpdate`).
3. On the Launch **click** (a user gesture), `launched=true` and every window —
   including `:main` — is opened as a popup via `openPopup` → `window.open("",
   id, features)`, each with its own `<canvas>` + event wiring.

The Launch click exists **only** to satisfy the browser rule that `window.open`
requires a transient user activation. Because *every* window (including the main
one) is a popup, the entered tab is never used as a paint surface.

Server side ([package/web/src/ProjecturedWeb.jl](../../package/web/src/ProjecturedWeb.jl)):
`_window_meta` emits each `WindowDocument`'s id/title/x/y/w/h/bg/style/draw;
`write_to_devices` sends `full` on first paint / `force_full` / resize and
`patch` (clipped dirty rect) otherwise. Patches route by `window` id. The editor,
projection pipeline, and `ScreenDocument`/`WindowDocument` model are unchanged by
this plan.

The "main" window: `ScreenDocument.windows` is an ordered `CellVector` of
`WindowDocument`s (order preserved, default id `:main`). We treat the **first
window in list order** as the primary/in-tab window.

## Desired behavior

- Navigate to the URL → fonts load → WS connects → the **primary window paints
  directly into the tab's `<canvas>`** as soon as its first `full` arrives. No
  click, no popup.
- The tab's canvas fills the viewport; resizing the tab re-lays-out the editor to
  fit (as popups do today).
- Keyboard/mouse/scroll/resize from the tab route to the primary window id.
- Refreshing the tab cleanly reconnects and rebinds the canvas.
- Non-primary windows open as popups, **lazily on the next user gesture in the
  tab** (a WS-message-driven `window.open` is blocked by the browser, so it is
  queued and flushed on the first mousedown/keydown). Single-window examples
  never exercise this path.

## Design

### 1. Server: mark the primary window — `ProjecturedWeb.jl`

Add a `primary` boolean to each `full` window so the client placement is
deterministic (not a guess about array order).

- In `write_to_devices`, the primary window is `wins[1]` (first in list order).
  Pass `primary = (w === first(wins))` (equivalently `w.id == wins[1].id`) into
  `_window_meta`.
- `_window_meta(w, draw; primary=false)` adds `"primary" => primary` to the dict.
- Only `full` carries `primary` (placement is decided at first full paint);
  `patch` is unchanged and keeps routing by `window` id.

This is the only server change. The flag is additive and backward compatible —
if absent the client falls back to "first window seen = tab" (see §3).

### 2. Page: a canvas host instead of a Launch button — `index.html`

Replace the Launch button + status host with a full-viewport `<canvas id="main">`
plus a small overlay used only for connection states.

```html
<body>
  <canvas id="main"></canvas>
  <div id="overlay">Connecting…</div>   <!-- hidden once the primary paints -->
  <script src="/client.js"></script>
</body>
```

- `html,body{margin:0;height:100%;overflow:hidden;background:#000}` and
  `#main{display:block;width:100vw;height:100vh}` — same surface CSS the popups
  inject today.
- `#overlay` is an absolutely-positioned centered message; shown for
  `Connecting…` / `Disconnected.` / `Another client is already connected.` /
  `Loading fonts…`, hidden once the primary window has painted.

### 3. Client: bind the primary window to the page canvas — `client.js`

Remove the `launched` gate entirely and the Launch button handler.

- **Tab binding object** mirroring a popup's shape so the existing
  `paint`/`applyPatch`/`renderList` code is reused verbatim:
  `pageSurface = { win: window, canvas: #main, ctx, dpr }`.
- **`mainId`** (string | null): the id bound to the page canvas. Set on the first
  `full` window whose `primary === true`; if no window ever reports `primary`
  (older server), fall back to the first `full` window id seen. Persist across
  resyncs so the same id rebinds.
- **`handleUpdate`**: paint immediately (no `launched` check).
  - For a `full` window: if it is `mainId` (or becomes `mainId`), bind it to the
    page surface — `sizeCanvas(pageSurface)`, `wireEvents(id, pageSurface)` once,
    set `document.title`, `paint(pageSurface, meta)`, hide overlay, and send an
    initial `{type:"resize", window:id, w:innerWidth, h:innerHeight}` so the
    server re-lays-out to the real tab size (server default `WindowDocument` is
    2400×1600; the tab differs). Otherwise it is a popup window → `ensurePopup`
    (queued if blocked, see below).
  - For a `patch`: if `patch.window === mainId` apply to `pageSurface`, else to
    the popup.
  - For `close`: if it is `mainId`, the editor closed the main window — clear the
    canvas and show the overlay; otherwise close the popup.
- **Event wiring for the tab**: reuse `wireEvents`, but bind key listeners on
  `document` (the page canvas can't take focus like a popup body) for
  `keydown/keyup/keypress`, and mouse/scroll on the canvas — exactly the popup
  wiring, with `win = window` and `doc = document`.
- **Resize**: a top-level `window.addEventListener("resize", …)` →
  `sizeCanvas(pageSurface)`, repaint retained `windowsMeta.get(mainId)`, then
  `send({type:"resize", window:mainId, w:innerWidth, h:innerHeight})` and
  `send({type:"resync"})` — same recovery the popups do.
- **Secondary popups, lazy on gesture**: keep a `pendingPopups` array. `ensurePopup`
  tries `window.open`; if it returns `null` (blocked — the usual case from a WS
  message), push the meta to `pendingPopups`. On the first user gesture in the
  page canvas (mousedown/keydown), flush `pendingPopups` (each is now opened
  under a transient activation). Popups otherwise behave exactly as today.
- **Boot**: `loadFonts()` → `connect()`; on `ws.onopen` just set overlay to
  `Connecting…`→hide on first paint (no button to enable). `busy`/`onclose`/
  `onerror` set the overlay text.
- **Reconnect**: on `ws.onclose`, reset `mainId`, `pageSurface` wiring guard,
  `windowsMeta`, `popups`, and `pendingPopups` so a reconnect (the server forces
  full on connect via `_reset_for_full!`) rebinds cleanly. Show `Disconnected.`
  and optionally auto-retry `connect()` after a short delay (nice-to-have).
- **`beforeunload`**: unchanged — close popups, `send({type:"quit"})`.

### 4. Docs & launcher text

Drop "click *Launch*" wording now that the editor appears immediately:

- `run_web_example` docstring in
  [package/example/src/Examples.jl](../../package/example/src/Examples.jl):
  "open `http://host:port`; the main window appears in that tab. Additional
  windows open as popups on first interaction."
- [documentation/devices-and-backends.md](../../documentation/devices-and-backends.md)
  (≈ lines 134–142), [documentation/debugging.md](../../documentation/debugging.md)
  (≈ line 54), and [README.md](../../README.md) (≈ line 198) — remove "and click
  **Launch**".

## Wire protocol delta

Only one additive field, on `full` entries:

```json
{ "type":"update",
  "full":[ {"id":"main","primary":true,"title":"…","x":-1,"y":-1,
            "w":2400,"h":1600,"bg":[…],"style":"normal","draw":[…]} ],
  "patches":[…], "close":[…] }
```

`patch` and `close` are unchanged. Client→server messages are unchanged (the tab
sends with `window: mainId`, exactly as a popup did with its own id).

## Files to change

- [package/web/src/ProjecturedWeb.jl](../../package/web/src/ProjecturedWeb.jl) —
  `_window_meta` gains `primary`; `write_to_devices` computes/passes it.
- [package/web/assets/index.html](../../package/web/assets/index.html) — canvas +
  overlay instead of the Launch button.
- [package/web/assets/client.js](../../package/web/assets/client.js) — remove
  `launched` gate/button; bind primary → page canvas; lazy secondary popups;
  tab resize; reconnect reset.
- [package/example/src/Examples.jl](../../package/example/src/Examples.jl) and the
  three docs above — wording.

## Milestones

1. **Server primary flag.** Add `primary` to `_window_meta`; compute in
   `write_to_devices`. (commit)
2. **In-tab primary window.** Rework `index.html` (canvas+overlay) and `client.js`
   to bind the primary window to the page canvas, paint immediately, wire events,
   handle tab resize, and clean reconnect. Single-window examples now open with no
   click. (commit)
3. **Lazy secondary popups.** `pendingPopups` queue flushed on first gesture, so
   `run_web_example(["json","xml"])` and tooltips still work without a Launch
   button. (commit)
4. **Docs & launcher wording.** Drop "click Launch". (commit)

## Edge cases

- **Initial size mismatch.** Server `WindowDocument` defaults to 2400×1600; the
  tab is smaller. Send `resize` with real `innerWidth/innerHeight` right after
  binding so the server re-lays-out (mirrors popup-open behavior). The first
  `full` may paint at the default size for one frame, then snap to the resync —
  acceptable; could be smoothed by deferring first paint until after the resize
  round-trip if it flickers.
- **HiDPI.** `pageSurface` uses the same `sizeCanvas` (`w*dpr × h*dpr`,
  `ctx.scale(dpr,dpr)`) as popups.
- **Refresh / reconnect.** WS drop clears `backend.conn` server-side; the new
  connection is accepted and `_reset_for_full!` re-sends everything full. Client
  resets `mainId` etc. on `onclose` so it rebinds.
- **Second client (`busy`).** Opening the URL in a second tab still gets the
  `busy` rejection (one client per editor) → overlay message. Unchanged.
- **Main window closed by the editor.** If a `close` names `mainId`, the tab
  clears and shows the overlay rather than trying to close the OS tab.

## Decisions

- **Primary = first window in `screen.windows` (list order)**, conveyed by a
  server `primary:true` flag; client falls back to "first window seen" if the
  flag is absent. Rationale: deterministic, no reliance on id naming, minimal
  server change.
- **Reuse the popup render/event code for the tab** by giving the page a
  popup-shaped surface object (`{win:window, canvas, ctx, dpr}`), so `paint`,
  `applyPatch`, `wireEvents`, and `sizeCanvas` are shared, not forked.
- **Secondary windows stay popups, opened lazily on the next gesture** — the
  browser blocks `window.open` from a WS message, and the user only asked for the
  *main* window to be button-free.

## Out of scope / possible follow-ups

- Escape currently maps to `QuitEvent` server-side (`_decode_and_enqueue!`),
  which would quit the editor from the tab. Pre-existing; revisit whether an
  in-tab editor should reserve Escape for editing instead of quitting.
- A single-window "no popups at all" mode (render extra windows as tabs/panes
  inside the page) — larger redesign, not needed here.
- Auto-reconnect/backoff on `onclose` is a nice-to-have, not required.
