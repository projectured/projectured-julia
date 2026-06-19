# Web (JavaScript) backend

## Goal

Add a `WebBackend <: Backend` that runs the editor inside a web server. The
editor (document, projection pipeline, reactive cells, REPL loop) stays on the
server in Julia. Browser clients are thin terminals: they capture raw mouse and
keyboard events, ship them to the server, and receive a list of **drawing
primitives** to paint. The **final rendering step happens in the browser** on an
HTML `<canvas>` 2D context.

Crucially, this is a *drop-in* backend. `run!` already takes the backend as an
argument:

```julia
run!(backend::Backend, projection, document; mcp=false)
```

So launching over the web is just `run!(WebBackend(; port=8080), composed, screen)`
instead of `run!(SdlBackend(), composed, screen)`. Nothing in the editor loop,
projection pipeline, or domains changes.

## The contract a backend must satisfy

From `api/Backend.jl` and `api/Device.jl`, driven by `editor/Editor.jl`:

- `init!(::Backend)` — start up (here: SDL_ttf for metrics + the HTTP/WS server).
- `quit!(::Backend)` — tear down (stop the server, drop the connection).
- `measure_text(::Backend, text, font) -> (w, h)` in **logical** pixels.
- `read_from_devices(backend, devices) -> EventEnvelope | nothing` —
  **non-blocking**; returns the next pending input event or `nothing`.
- `write_to_devices(backend, devices, screen::ScreenDocument)` — reconcile the
  output against the desired window set and paint.

`measure_text` is load-bearing: the layout pipeline (`TextToGraphics`,
word-wrapping, caret placement, hit-test bands) calls it *synchronously during
printing* on the server, long before any primitive reaches the browser. The
server must measure glyphs the same way the browser will render them.

The SDL backend (`backend/Sdl.jl`) is the reference implementation for all five.

## Architecture

```
┌─────────────────────── Julia server process ───────────────────────┐
│  run!(WebBackend, projection, document)                             │
│     │  editor REPL loop (unchanged)                                 │
│     ▼                                                               │
│  read! ─ read_from_devices ◄── inbound Channel{EventEnvelope}       │
│  eval! ─ evaluate_operation                                         │
│  print!─ projection_print ── measure_text (sdl_measure_text)        │
│     └── write_to_devices ── serialize draw-list ──► conn outbox     │
│                                                                     │
│  HTTP.jl server (async tasks):                                      │
│    • GET /            → index.html                                  │
│    • GET /client.js   → client renderer                            │
│    • GET /fonts.json  → list of served font basenames              │
│    • GET /font/<name> → a TTF/OTF from font/                        │
│    • WS  /ws          → recv events → inbound; send frames ◄ outbox │
└─────────────────────────────────────────────────────────────────────┘
                          ▲  events            │  draw-lists (JSON)
                          ▼                    │
┌──────────────────────── Browser client ────────────────────────────┐
│  client.js: one popup (window.open) per WindowDocument; a <canvas>  │
│  2D renderer (the final paint); capture mouse/keyboard/resize →     │
│  JSON → WS; load served fonts via FontFace before first paint.      │
└─────────────────────────────────────────────────────────────────────┘
```

## Concurrency model

The editor loop is synchronous, single-threaded, cooperative (`sleep(0.01)` each
frame yields to `@async` tasks — same pattern the MCP server relies on). The
HTTP/WebSocket server runs on `@async` tasks in the same process.

- The (single) connection's **receive task** reads WS frames, decodes each into
  an `EventEnvelope`, and `put!`s it on `inbound::Channel{Any}`.
- `read_from_devices` is non-blocking: `isready(inbound) ? take!(inbound) :
  nothing`. It mirrors SDL's `pending_events` drain plus per-event
  classification, performing the same server-side synthesis SDL does:
  - **MousePress** on a button-up matching a recent down (same button, <5px,
    <0.3s) — reuse SDL's `last_down_*` fields verbatim.
  - **MouseMove only while a button is held** (client pre-filters; guard kept).
  - **Escape / window close → QuitEvent / WindowCloseRequest**.
- `write_to_devices` serializes the draw-list and pushes it to the connection's
  **outbox** (capacity-1, coalescing — newest frame wins); a **send task**
  drains the outbox to the socket. To avoid network spam at 100 Hz, a frame
  identical to the last one sent is skipped.

No locks needed beyond `Channel` (cooperative scheduling). All SDL-style state
(`last_down_*`, the window registry) lives on the `WebBackend` struct.

## Text measurement & font fidelity

The server lays out text before the browser sees it, so server metrics must
match browser rendering, or carets/highlights/word-wrap misalign.

**Decision (v1): reuse headless SDL_ttf** via `sdl_measure_text`. The example
pipelines already bake `TextToGraphics(measure=sdl_measure_text)` into the
projection, so SDL_ttf must be initialised to print *at all*, regardless of
backend. `WebBackend.init!` therefore runs `SDL_Init(SDL_INIT_VIDEO)` +
`TTF_Init()` (no window is created) and reuses `sdl_measure_text`. The browser
renders the same TTFs (served from `font/`), so metrics match closely.

Browser side:
- Load each served font via the `FontFace` API and `await document.fonts.ready`
  before connecting the WebSocket, so glyphs are present at first paint.
- Render text at the same logical px the server measured; `ctx.font =
  "<size>px '<family>'"`, `textBaseline = "top"` so `(x, y)` is the glyph box
  top-left, matching how `GraphicsText` positions (SDL blits at top-left).
- HiDPI: the server stays in logical pixels (`_DISPLAY_SCALE = 1.0`). The
  browser sizes the canvas backing store to `w*dpr × h*dpr` and
  `ctx.scale(dpr, dpr)`, replacing SDL's display-scale/supersample machinery.

Revisit FreeTypeAbstraction only if SDL video init is undesirable on a truly
headless host.

## Wire protocol (JSON, both directions)

### Server → client: draw-list

`write_to_devices` walks the `ScreenDocument`. Each `WindowDocument` yields
window metadata + a draw-list serialized from the `GraphicsCanvas` content,
mirroring SDL's `_dispatch_render_elem!` element set. Offsets are kept nested
(groups/clips carry their offset; the client accumulates) so the structure
matches SDL's recursion exactly.

| Julia type | JSON |
|---|---|
| `GraphicsText` | `{t:"text", x,y, s, f, sz, c:[r,g,b,a]}` (baseline top) |
| `GraphicsRect` | `{t:"rect", x,y,w,h, c, rtl,rtr,rbr,rbl, bw, bc}` |
| `GraphicsLine` | `{t:"line", x1,y1,x2,y2, c, w}` |
| `GraphicsCircle` | `{t:"circle", cx,cy,r, c, bw, bc}` |
| `GraphicsViewport` | `{t:"clip", x,y,w,h, ox,oy, content:[…]}` |
| `GraphicsCanvas` (nested) | `{t:"group", x,y, content:[…]}` |
| `GraphicsImage` | `{t:"image", x,y,w,h, rgba|png}` (Ptr form skipped in v1) |
| `GraphicsFence` | skipped, as in SDL |

Frame envelope:
```json
{ "type":"frame",
  "windows":[ {"id":"main","title":"…","x":-1,"y":-1,"w":2400,"h":1600,
               "bg":[253,246,227,255],"style":"normal","draw":[ … ]} ] }
```
v1 resends the full frame; the client reconciles popups by `id` (open new ids,
close dropped ids).

### Client → server: input events

Client sends **raw** browser key fields (`key` + `code`); the server maps them.

```json
{"type":"mousedown","window":"main","button":"left","x":10,"y":20,"mods":{…}}
{"type":"keydown","window":"main","key":"ArrowLeft","code":"ArrowLeft","repeat":false,"mods":{…}}
{"type":"keypress","window":"main","char":"a","text":"a","mods":{…}}
{"type":"keyup", ...}  {"type":"mouseup", ...}  {"type":"mousemove", ...}
{"type":"scroll","window":"main","dx":0,"dy":-1,"x":…,"y":…,"mods":{…}}
{"type":"resize","window":"main","w":1280,"h":720}
{"type":"close","window":"main"}   {"type":"quit"}
```

`read_from_devices` decodes these into the existing vocabulary (`device/Mouse.jl`,
`device/Keyboard.jl`, `device/Modifiers.jl`) wrapped in `EventEnvelope`.

## Event mapping (server-side)

Key mapping is done **on the server** (`web_key_to_symbol`, mirroring
`sdl_keysym_to_symbol`): `"ArrowLeft"→:left`, `"Enter"→:return`,
`"Escape"→:escape`, `"Backspace"`, `"Delete"`, `"Tab"`, `" "→:space`,
`"Home"/"End"/"PageUp"/"PageDown"`, `"F1".."F12"`. For chord letters and
punctuation, the printable key under Ctrl maps to `:c/:x/:v/:n/:period/:slash/…`;
otherwise `:char`. Keeping the table in Julia makes it the single source of
truth alongside the SDL one.

- Buttons: `0→:left, 1→:middle, 2→:right`. Modifiers from `event.ctrlKey` etc.
- **Text input** = SDL's `SDL_TEXTINPUT` → `KeyPress(char, text, mods)`,
  produced from the browser `keypress` for printable chars only — never
  synthesized from `keydown` for control keys.
- Client `preventDefault`s keys the editor consumes (arrows, Tab, Ctrl-chords)
  and suppresses `contextmenu` so right-click reaches the editor.

## Multi-window mapping

**Decision: one native browser popup per `WindowDocument`** (`window.open`),
mirroring SDL's one-window-per-id model.

- The first page load is the bootstrap/host page (with a "Launch" button to
  satisfy the browser's user-gesture requirement for `window.open`). When a
  `frame` lists windows, the client opens a popup per unseen
  `WindowDocument.id`, injects a `<canvas>` + renderer, and tracks it by id.
- Window metadata → popup: `title` → `document.title`; `w/h` → initial size;
  `x/y` → `left/top` (`-1` = browser default). `style:"tooltip"/"floating"` →
  best-effort minimal-chrome / on-top.
- Each popup's handlers close over its id, so events carry the right `window`
  field and `EventEnvelope(window_id, event)` routes as with SDL.
- Popup `beforeunload` → `{type:"close",window:id}` → `WindowCloseRequest`;
  a window leaving the `frame` list closes its popup; host-page unload →
  `{type:"quit"}`.
- `WindowResizeEvent` from each popup's `resize` listener.

Caveat: browsers block `window.open` without a user gesture and may suppress
multi-popup bursts — documented in the client; popups are opened from a gesture.

## Images

`GraphicsImage.data` can be an SDL texture `Ptr` (not serializable), a
`(Vector{UInt8} RGBA, w, h)` tuple, or a bare RGBA buffer. Web backend: the
`Ptr` path is skipped (v1); decoded-buffer forms are serialized as raw RGBA +
size (client `putImageData`) or a `data:` PNG. `sdl_render_canvas` /
`GraphicsCaching` has no web analog yet — deferred.

## Incremental rendering (phase 2) — implemented

SDL has dirty-rectangle partial repaint. v1 sent the full draw-list per frame.
Phase 2 (implemented) sends only changed regions.

The base worktree's SDL backend predates SDL's own dirty-rect machinery, so the
web backend implements its own reactive dirty-walk in `Web.jl`
(`_collect_canvas_dirty!` / `_collect_listnode_dirty!` / `_collect_elem_dirty!`),
keyed on the cells' `isuptodate` flags and reusing SDL's pure bounds helpers
(`_bounds_elem!`, `_accumulate_bounds!`, imported). It computes the smallest
rectangle covering everything that changed since the last paint; `prev_bounds`
(per window, keyed by `objectid`) unions a unit's previous painted extent with
its new one so moved/shrunk content clears its vacated pixels. A stale
computed-container cell (canvas `elements`, `CellVector` backing, `ListNode`
spine) marks a whole subtree dirty (reflow); a leaf's own stale field cell is a
tight unit.

`_serialize_clipped` then emits only the primitives whose absolute bounds
intersect the dirty rect (recursing groups/viewports, dropping empty ones), so a
patch carries just that region.

Protocol is now a single coalescible-but-ordered message per frame:
`{type:"update", full:[window…], patches:[{window,clip,draw}…], close:[id…]}`.
A window is sent in `full` on first paint, on (re)connect, after a resize, or on
queue-overflow (`force_full`); otherwise only a `patch` is sent. The client
repaints a patch by clipping to `clip`, clearing it to the window background, and
painting the patch's primitives over the retained canvas. Because patches are
order-sensitive, the outbox is a FIFO (never coalesced); on near-overflow the
backend falls back to a full resend rather than dropping a patch. The client
sends `{type:"resync"}` after (re)opening popups (launch, resize) to request
guaranteed-fresh full state.

## Dependencies & file layout

Deps already present in `program/Project.toml`: `HTTP` (server + WebSockets,
`HTTP.WebSockets`), `JSON3` (messages), `SimpleDirectMediaLayer` (metrics). No
new deps for v1.

New files:
- `program/src/backend/Web.jl` — `WebBackendModule`: the `WebBackend` struct,
  `init!/quit!/measure_text/read_from_devices/write_to_devices`, serialization,
  event decoding, key mapping, HTTP/WS handlers. Mirrors `Sdl.jl`'s structure.
- `program/web/index.html`, `program/web/client.js` — browser client.
- Wire-up in `Projectured.jl`: include, `using .WebBackendModule`, export
  `WebBackend`.
- `run_web_example` launcher in `example/src/Examples.jl`, reusing the same
  composed projection + `ScreenDocument` as `run_example`.

SDL stays the default; the web backend is additive and selected explicitly.

## Milestones

1. **Server skeleton.** `WebBackend`, HTTP server serving page/fonts, WS,
   `init!/quit!`, non-blocking `read_from_devices`. ✅ implemented
2. **One-way render.** `write_to_devices` serializes a draw-list; client paints
   rect/line/text/circle/clip/group. ✅ implemented
3. **Input round-trip.** Client captures mouse+keyboard; server decodes (incl.
   MousePress synthesis, Esc→quit). ✅ implemented
4. **Images, resize, multi-window popups.** ✅ implemented (images: buffer forms)
5. **Phase-2 incremental draw-lists.** ✅ implemented (reactive dirty-walk + clipped patches)

## Decisions

- **Multi-window:** one native browser popup per `WindowDocument` (`window.open`).
- **Clients per editor:** exactly one; a second WS upgrade is rejected.
- **Key-symbol mapping:** on the server (single source of truth).
- **Transport:** JSON both directions.
- **Metrics:** headless SDL_ttf (`sdl_measure_text`); no new deps.
