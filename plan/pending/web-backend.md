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

From [api/Backend.jl](../../program/src/api/Backend.jl) and
[api/Device.jl](../../program/src/api/Device.jl), driven by
[editor/Editor.jl](../../program/src/editor/Editor.jl):

- `init!(::Backend)` — start up (here: start the HTTP/WebSocket server).
- `quit!(::Backend)` — tear down (stop the server, drop connections).
- `measure_text(::Backend, text, font) -> (w, h)` in **logical** pixels.
- `read_from_devices(backend, devices) -> EventEnvelope | nothing` —
  **non-blocking**; returns the next pending input event or `nothing`.
- `write_to_devices(backend, devices, screen::ScreenDocument)` — reconcile the
  output against the desired window set and paint.

`measure_text` is the load-bearing one (see "Text measurement" below): the
layout pipeline (`TextToGraphics`, word-wrapping, caret placement, hit-test
bands) calls it *synchronously during printing* on the server, long before any
primitive reaches the browser. The server must measure glyphs the same way the
browser will render them.

The SDL backend ([backend/Sdl.jl](../../program/src/backend/Sdl.jl)) is the
reference implementation for all five.

## Architecture

```
┌─────────────────────── Julia server process ───────────────────────┐
│  run!(WebBackend, projection, document)                             │
│     │                                                               │
│     │  editor REPL loop (unchanged)                                 │
│     ▼                                                               │
│  read! ─ read_from_devices ◄── inbound Channel{EventEnvelope}       │
│  eval! ─ evaluate_operation                                         │
│  print!─ projection_print ── measure_text (FreeType metrics)        │
│     └── write_to_devices ── serialize draw-list ──► per-conn queue  │
│                                                                     │
│  HTTP.jl server (async tasks):                                      │
│    • GET /            → index.html + client.js + fonts              │
│    • WS  /ws          → recv: events  → inbound Channel             │
│                          send: draw-lists from per-conn queue       │
└─────────────────────────────────────────────────────────────────────┘
                          ▲  events            │  draw-lists (JSON)
                          │                    ▼
┌──────────────────────── Browser client ────────────────────────────┐
│  client.js:                                                         │
│    • <canvas> per window; 2D context renderer (the final paint)     │
│    • capture mouse/keyboard/resize → JSON → WS                      │
│    • @font-face / FontFace for the same TTFs the server measures    │
└─────────────────────────────────────────────────────────────────────┘
```

## Concurrency model

The editor loop is synchronous, single-threaded, cooperative (`sleep(0.01)` each
frame yields to `@async` tasks — same pattern the MCP server relies on). The
HTTP/WebSocket server runs on `@async` tasks in the same process.

- The (single) connection's **receive task** reads WS frames, decodes each into
  an `EventEnvelope`, and `put!`s it on `inbound::Channel{Any}`.
- `read_from_devices` is non-blocking: `isready(inbound) ? take!(inbound) : nothing`.
  It mirrors SDL's `pending_events` drain plus per-event classification, and
  performs the same server-side synthesis SDL does:
  - **MousePress** synthesis on a button-up that matches a recent down (same
    button, <5px move, <0.3s) — reuse SDL's `last_down_*` fields verbatim.
  - **MouseMove only while a button is held** (avoid flooding) — the client can
    pre-filter, but keep the guard server-side too.
  - **Escape / window close → QuitEvent / WindowCloseRequest**.
- `write_to_devices` serializes the draw-list and pushes it to each connection's
  outbound queue; a per-connection **send task** drains the queue to the socket.

No locks needed beyond `Channel` (cooperative scheduling). Keep all SDL-style
state (`last_down_button/x/y/time`, the window registry) on the `WebBackend`
struct.

## `WebBackend` struct (sketch)

```julia
mutable struct WebBackend <: Backend
    port::Int
    server::Any                       # HTTP.Servers.Server handle
    inbound::Channel{Any}             # EventEnvelopes from the single client
    conn::Union{WebConn,Nothing}      # the one live WS connection (see below)
    # MousePress synthesis state (mirrors SdlBackend)
    last_down_button::Symbol
    last_down_x::Int; last_down_y::Int; last_down_time::Float64
    # Window reconciliation (mirrors SdlBackend.windows): last-sent metadata per
    # WindowDocument.id, so write_to_devices can diff title/size/style/bg.
    windows::Dict{Symbol, WebWindowState}
end
```

**One client per editor** (decision): `conn` is a single connection, not a
vector. A second WS upgrade while `conn` is live is rejected (HTTP 409 / close
frame). `WebConn` holds the WS socket + an outbound `Channel{String}` + the send
task handle.

## Text measurement & font fidelity (the critical piece)

The server lays out text before the browser ever sees it, so server metrics
**must** match browser rendering pixel-for-pixel, or carets/highlights/word-wrap
will be misaligned.

Strategy:
1. **Measure server-side with the actual TTFs.** Use `FreeTypeAbstraction.jl`
   (or raw `FreeType.jl`) to compute string advance width + line height for a
   `StyleFont(filename, size)`. This removes the SDL/SDL_ttf dependency for
   metrics. (Alternative quick start: keep SDL_ttf headless purely for
   `TTF_SizeUTF8` — no window needed — and only swap to FreeType later.)
2. **Serve the same TTFs to the browser** from [font/](../../font/) and load
   them via the `FontFace` API; *await* `document.fonts.ready` before the first
   paint so measurements line up.
3. **Render text in the browser at the same logical px** the server measured.
   Set `ctx.font = "<size>px <family>"` with the family that maps to the served
   TTF. Pin `textBaseline = "top"` so `(x, y)` is the glyph box top-left, matching
   how `GraphicsText` positions (SDL blits the texture at the top-left too).
4. **HiDPI:** the server works entirely in logical pixels. The browser handles
   device pixels via `devicePixelRatio`: size the canvas backing store to
   `w*dpr × h*dpr` and `ctx.scale(dpr, dpr)`. This replaces SDL's
   `_DISPLAY_SCALE` / supersample machinery — leave `_DISPLAY_SCALE = 1.0` on the
   server for the web backend so layout stays in logical units.

Risk to validate early: browser canvas `measureText` width vs FreeType advance
width can differ by sub-pixel hinting/kerning. Mitigation: disable kerning-
dependent assumptions, test with the monospace fonts already used
(DejaVuSansMono, Liberation Mono), and add a calibration test that renders known
strings and compares widths. **Prototype this before building anything else.**

## Wire protocol

Two message directions over one WebSocket. JSON for v1 (readable, easy to debug);
a binary draw-list is a later optimization.

### Server → client: draw-list

`write_to_devices` walks the `ScreenDocument`. For each `WindowDocument` it emits
window metadata + a flat (or lightly nested) list of primitives serialized from
the `GraphicsCanvas` content. Mirror SDL's `_dispatch_render_elem!` element set:

| Julia type | JSON | Notes |
|---|---|---|
| `GraphicsText` | `{t:"text", x,y, s:"…", font:{f,sz}, c:[r,g,b,a]}` | baseline=top |
| `GraphicsRect` | `{t:"rect", x,y,w,h, c, radius:{tl,tr,br,bl}, border:{w,c}}` | rounded + inner border |
| `GraphicsLine` | `{t:"line", x1,y1,x2,y2, c, w}` | axis-aligned crisp; diagonal AA |
| `GraphicsCircle` | `{t:"circle", cx,cy,r, c, border:{w,c}}` | |
| `GraphicsViewport` | `{t:"clip", x,y,w,h, content:[…]}` | `ctx.save/clip/restore` |
| `GraphicsCanvas` (nested) | `{t:"group", x,y, content:[…]}` | offset children |
| `GraphicsImage` | `{t:"image", x,y,w,h, src:"data:…"}` | see Images |
| `GraphicsFence` | — | skipped, exactly as in SDL |

Coordinates are logical pixels, already absolute-offset-accumulated the same way
`_render_canvas!` threads `ox/oy` (or send relative + `group` offsets and let the
client accumulate — pick one; client-side accumulation keeps payloads smaller).

Message envelope:
```json
{ "type":"frame",
  "windows":[ {"id":"main","title":"…","x":-1,"y":-1,"w":2400,"h":1600,
               "bg":[253,246,227,255],"style":"normal","draw":[ …primitives… ]} ] }
```

Window lifecycle messages: `{"type":"open"/"close"/"update", ...}` if we diff
windows; for v1 just resend the full `frame` and let the client reconcile
canvases by `id`.

### Client → server: input events

The client sends **raw** browser key fields (`key` + `code`); the server maps
them to the `Symbol` vocabulary (see Event mapping).

```json
{"type":"mousedown","window":"main","button":"left","x":10,"y":20,
 "mods":{"ctrl":false,"shift":false,"alt":false,"meta":false}}
{"type":"keydown","window":"main","key":"ArrowLeft","code":"ArrowLeft","repeat":false,"mods":{…}}
{"type":"keypress","window":"main","char":"a","text":"a","mods":{…}}
{"type":"keyup","window":"main","key":"…","code":"…","mods":{…}}
{"type":"mouseup", ...}  {"type":"mousemove", ...}
{"type":"scroll","window":"main","dx":0,"dy":-1,"x":…,"y":…,"mods":{…}}
{"type":"resize","window":"main","w":1280,"h":720}
{"type":"close","window":"main"}   {"type":"quit"}
```

`read_from_devices` decodes these into the existing vocabulary
([device/Mouse.jl](../../program/src/device/Mouse.jl),
[device/Keyboard.jl](../../program/src/device/Keyboard.jl),
[device/Modifiers.jl](../../program/src/device/Modifiers.jl)) wrapped in
`EventEnvelope(window_id, event)`.

## Event mapping (browser → vocabulary)

The hardest mapping is keys. SDL maps keysyms to a fixed `Symbol` vocabulary in
`sdl_keysym_to_symbol` (`:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
`:page_up/down`, `:backspace`, `:delete`, `:return`, `:tab`, `:escape`, `:space`,
`:f1…:f12`, the clipboard chord letters `:c/:x/:v/:n`, `:period`, `:slash`,
`:asterisk`, `:equals`, `:minus`, modifier-only keys, else `:char`). The web
client must produce the **same symbols** so `@event_case`/`@reference_case`
readers match unchanged.

- The client sends raw `KeyboardEvent.key`/`code`; the **server** maps it (a
  `web_key_to_symbol` mirroring `sdl_keysym_to_symbol`): `"ArrowLeft"→:left`,
  `"Enter"→:return`, `"Escape"→:escape`, `"Backspace"`, `"Delete"`, `"Tab"`,
  `" "→:space`, `"Home"/"End"/"PageUp"/"PageDown"`, `"F1".."F12"`. For the chord
  letters and punctuation, map the printable key under Ctrl to
  `:c/:x/:v/:n/:period/:slash/…`; otherwise `:char`. Keeping the table in Julia
  makes it the single source of truth alongside the SDL one.
- **Text input** = SDL's `SDL_TEXTINPUT` → `KeyPress(char, text, mods)`. Use the
  browser `beforeinput`/`input` on a hidden contenteditable, or `keypress` for
  printable chars. Do **not** synthesize `KeyPress` from `keydown` for control
  keys.
- Buttons: `0→:left, 1→:middle, 2→:right`. Modifiers from `event.ctrlKey` etc.
- `preventDefault` on keys the editor consumes (arrows, Tab, Ctrl-chords) so the
  browser doesn't scroll/navigate.
- `contextmenu` suppressed so right-click reaches the editor.

## Multi-window mapping

A `ScreenDocument` can hold several `WindowDocument`s (main + tooltip/floating;
see `style` in [document/Screen.jl](../../program/src/document/Screen.jl)).

**Decision: one native browser popup per `WindowDocument`** (via `window.open`),
mirroring SDL's one-native-window-per-id model directly.

- The first page load is the bootstrap/host page. When the server's `frame`
  message lists windows, the client opens a popup per `WindowDocument.id` it has
  not seen (`window.open("", id, "width=…,height=…,left=…,top=…")`), writes a
  `<canvas>` + the renderer into the popup's document, and tracks it by `id`.
- Each popup owns one canvas filling its viewport. Window metadata maps to popup
  features: `title` → `popup.document.title`; `w/h` → initial popup size;
  `x/y` → `left/top` (`-1` = let the browser place it). `style:"tooltip"/
  "floating"` → opened with minimal chrome / kept on top where the browser
  allows (popup feature support is limited; best-effort).
- Events carry the originating `id` as their `window` field (each popup's
  handlers close over their own id), so `EventEnvelope(window_id, event)` routes
  exactly as with SDL.
- Closing a popup (`beforeunload`) sends `{type:"close",window:id}` →
  `WindowCloseRequest`. A window dropping out of the `frame` list closes its
  popup. Closing the host page (or its `beforeunload`) sends `{type:"quit"}`.
- `WindowResizeEvent` comes from each popup's `resize` listener → `resize`
  message with that popup's id.

Caveat: browsers block `window.open` unless it descends from a user gesture, and
may suppress multi-popup bursts. The host page therefore opens popups in response
to a user click (e.g. a "Launch" button) and/or opens them lazily one per
subsequent gesture; document this limitation in the client.

## Images

`GraphicsImage.data` in SDL can be a raw SDL texture `Ptr` (not serializable), a
`(Vector{UInt8} RGBA, w, h)` tuple, or a bare RGBA `Vector{UInt8}`. For the web
backend:

- The `Ptr` path is SDL-specific and must not be produced under `WebBackend`.
  Route image decoding to the **decode-to-RGBA-buffer** path (the tuple form
  already exists, used by `_blit_rgba!`), then serialize as a `data:` URL
  (PNG-encode server-side, or send raw RGBA + size and `putImageData` client-side).
- `sdl_render_canvas` / `GraphicsCaching` (canvas→texture) has no web analog in
  v1; either disable caching under `WebBackend` or implement a canvas→PNG
  offscreen encode. Defer.

## Incremental rendering (phase 2)

SDL has elaborate dirty-rectangle partial repaint (`_collect_*_dirty!`,
`dirty_bounds`, `isuptodate` checks). v1 sends the **full draw-list every frame**
— simplest and correct. Phase 2 reuses the *same* dirty-walk machinery to send
only changed primitives/regions:
- Run the existing dirty-bounds analysis, serialize only primitives intersecting
  the dirty rect, and send a `{type:"patch", window, clip:[…], draw:[…]}` the
  client paints over a retained backing canvas.
- Or maintain a client-side scene graph keyed by stable element ids and diff.
This dovetails with the incremental-selection work already in flight.

## Dependencies & file layout

New Julia deps (add to [Project.toml](../../Project.toml)):
- `HTTP.jl` — server + WebSockets.
- `JSON3.jl` (or `JSON.jl`) — message (de)serialization.
- `FreeTypeAbstraction.jl` (or `FreeType.jl`) — text metrics without SDL.

New files:
- `program/src/backend/Web.jl` — `WebBackendModule`: the `WebBackend` struct,
  `init!/quit!/measure_text/read_from_devices/write_to_devices`, serialization,
  event decoding, the HTTP/WS handlers. Mirror the structure of `Sdl.jl`.
- `program/web/index.html`, `program/web/client.js` — the browser client
  (canvas renderer, event capture, font loading). Served by the Julia server.
- Wire-up in [Projectured.jl](../../program/src/Projectured.jl): `include`,
  `using .WebBackendModule`, export `WebBackend`.
- An example launcher (parallel to `run_example`) that calls
  `run!(WebBackend(...), composed, screen)`, or a `backend=:web` kwarg on the
  existing `run_example`.

Keep SDL the default; the web backend is additive and selected explicitly.

## Milestones

1. **Metrics spike.** FreeType `measure_text` for `StyleFont`; calibrate against
   browser `measureText` + canvas rendering for the mono fonts. Decide
   FreeType-vs-headless-SDL_ttf. *Gate: text widths match within tolerance.*
2. **Server skeleton.** `WebBackend`, HTTP server serving a static page + fonts,
   WS echo, `init!/quit!`, non-blocking `read_from_devices` from a Channel.
3. **One-way render.** `write_to_devices` serializes a single-window draw-list;
   client paints rects/lines/text/circles to canvas. Verify against an SDL
   screenshot of the same example (`print_example`/`write_example_image`).
4. **Input round-trip.** Client captures mouse+keyboard, server decodes to the
   event vocabulary (incl. MousePress synthesis, Esc→quit). A JSON example
   becomes interactive end-to-end.
5. **Viewport/clip, nested canvas, images, scroll, resize.** Full primitive
   coverage + `WindowResizeEvent`.
6. **Multi-window** (tooltip/floating), then **phase-2 incremental** draw-lists.

## Decisions

- **Multi-window presentation:** one native browser popup per `WindowDocument`
  via `window.open` (see Multi-window mapping above), mirroring SDL's
  one-window-per-id model.
- **Clients per editor:** exactly **one client per editor** for now. A second
  WS connection while one is live is rejected (or replaces the first — pick
  reject for v1). No collaborative/broadcast path; per-client selection is a
  much larger follow-up left out of scope.
- **Key-symbol mapping:** done **on the server**. The client sends the raw
  browser `key`/`code` (+ modifiers); `read_from_devices` maps it to the
  `Symbol` vocabulary, keeping `sdl_keysym_to_symbol`'s table as the single
  source of truth in Julia.
- **Transport encoding:** **JSON** (both directions). A binary draw-list is a
  later optimization only if payloads dominate.

## Open questions

- **Metrics backend:** FreeTypeAbstraction (clean, no SDL) vs headless SDL_ttf
  (reuses existing `_get_font`/`TTF_SizeUTF8`, faster to stand up). Resolve in
  milestone 1.
```
