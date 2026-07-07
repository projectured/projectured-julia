# Devices and Backends

ProjecturEd separates the **what** of I/O (a `Device`) from the **how**
(a `Backend`). A `Device` describes a logical input or output channel; a
`Backend` provides the platform-specific machinery to drive it. This split
makes it possible to add a new backend (terminal, web, JetBrains plugin, …)
without rewriting projection code, and to add a new device (e.g. a touch
panel) without modifying existing backends beyond the device's own
dispatch.

The abstract interfaces live in
[backend/Backend.jl](../package/kernel/main/backend/Backend.jl) and
[device/Device.jl](../package/kernel/main/device/Device.jl). There are three backends: the
SDL2 graphics backend (default; native windows), a terminal `ConsoleBackend`, and
a `WebBackend` that runs the editor in an HTTP + WebSocket server and renders in
the browser (all described below).

Every backend is a drop-in: `run_editor!` takes the backend as an argument, so switching
is just e.g. `run_editor!(WebBackend(), projection, document)` instead of
`run_editor!(SdlBackend(), projection, document)` — nothing in the editor loop,
projection pipeline, or domains changes.

## Devices

| Device | Defined in | Purpose |
|---|---|---|
| `Screen` | `device/ScreenDevice.jl` | Output surface — native windows are reconciled on demand against the projection-output `ScreenDocument` |
| `Keyboard` | `device/Keyboard.jl` | Input — emits `KeyPress(char::Char)` for character input and `KeyDown(key::Symbol, modifiers::Modifiers)` for navigation |
| `Mouse` | `device/Mouse.jl` | Input — emits `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll` |

Each is a stateless singleton struct. The editor holds a `Vector{Device}`
that is passed to every backend call.

### Backend-agnostic events

Projection readers only see these events, never SDL-specific structs:

```julia
KeyPress('a')                          # character input
KeyDown(:left, Modifiers())            # arrow key, no modifiers
KeyDown(:return, Modifiers(ctrl=true)) # Ctrl-Enter
MousePress(:left, 132, 47)             # left button at pixel (132, 47)
MouseMove(120, 90)                     # cursor moved to (120, 90)
MouseScroll(0, 1, 200, 300)            # wheel scrolled (dx, dy) at (200, 300)
WindowQuit()                            # window close or Escape
```

This vocabulary is what insulates a `TextToGraphics.read_intent` (which
maps the `:left`/`:right` `KeyDown` keys to a `ReplaceSelectionOperation`) from
any specific backend.

## Backends

```julia
abstract type Backend end

# Backend interface (api/BackendApi.jl)
initialize_backend!(::Backend)                    # set up libraries, allocate caches
quit_backend!(::Backend)                    # release everything
measure_text(::Backend, text, font) # (px_width, px_height)

# Device I/O interface (api/DeviceApi.jl) — driven by the backend
read_from_devices(::Backend, devices)           # poll → EventEnvelope
write_to_devices(::Backend, devices, document)  # render the output
```

There is no `open_window!`/`close_window!`: native windows are reconciled on
demand inside `write_to_devices` whenever it sees a new `ScreenDocument` output.

There are three backends: `SdlBackend` (native graphics), `ConsoleBackend`
(terminal), and `WebBackend` (browser, over HTTP + WebSocket).

### SdlBackend

`SdlBackend` (in [backend/Sdl.jl](../package/sdl/main/ProjecturedSdl.jl)) implements
all of the above with SDL2 + SDL_ttf. Highlights:

- A font measurement cache shared across all windows.
- `sdl_to_keypress` maps SDL keysyms + modifier bits to `KeyPress`/`KeyDown`.
- Mouse events are mapped inline in `read_from_devices` (there is no
  `sdl_to_mouse` function) to the `Mouse*` structs.
- `sdl_render_canvas` walks a `GraphicsCanvas` (and its nested
  `GraphicsViewport`/`GraphicsImage`/`GraphicsFence` children) and issues
  SDL draw calls.

### ConsoleBackend

`ConsoleBackend` (in [backend/Console.jl](../package/visual/main/backend/Console.jl))
renders the **Text domain** straight to a terminal. Crucially it consumes a
`TextText` directly and skips `TextToGraphics`: its pipeline is
`JsonToSyntax → SyntaxToText` (no graphics step), so `write_to_devices` receives
a `TextText` rather than a `ScreenDocument`. Highlights:

- `write_to_devices` flattens the spans to a character stream, preserving each
  span's `font_color`/`fill_color` as 24-bit ANSI SGR codes (set `ansi=false`
  for plain output). The selection is shown as inverse-video span colors baked
  in by the `SelectionInverting` projection at the end of the console pipeline,
  so the backend itself just emits each span's colors.
- `read_from_devices` polls `backend.input` (default `stdin`) non-blockingly and
  translates terminal bytes — printable chars, `ESC[` arrow/Home/End/Delete
  sequences, Enter/Backspace/Tab, Ctrl-Space, Ctrl-C — into the same
  `KeyDown`/`KeyPress`/`WindowQuit` vocabulary the readers already use, wrapped in
  an `EventEnvelope(:console, …)`. `initialize_backend!`/`quit_backend!` toggle the terminal's raw mode.
- Because the console has no screen/window layer, the pipeline supplies its own
  envelope-unwrapping seam — `EnvelopeUnwrappingProjection`
  ([projection/higherorder/EnvelopeUnwrapping.jl](../package/kernel/main/projection/higherorder/EnvelopeUnwrapping.jl))
  — that strips the `EventEnvelope` off the gesture before the readers run. (In
  the SDL pipeline `ScreenToScreen` does this.)
- **Limitation:** character-level text editing (cursor left/right, insertion,
  backspace/delete) lives in `TextToGraphics` and is therefore unavailable;
  the console drives the geometry-free subset — structural tree navigation
  (`Home` + arrows) and the `Ctrl+Space` mode toggle.

Run it with `run_console_example()` (one-shot) or
`run_console_example(interactive=true)` (read-eval-print loop).
## Web backend

`WebBackend` ([backend/Web.jl](../package/web/main/ProjecturedWeb.jl)) runs the editor
inside an HTTP + WebSocket server and moves the **final rendering step into the
browser**. The Julia process keeps the document, projection pipeline, reactive
cells, and the read-eval-print loop; a connected JavaScript client
([package/web/assets/](../package/web/assets/)) is a thin terminal that captures raw mouse and
keyboard events and paints a JSON **draw-list** onto an HTML `<canvas>`.

```
 browser tab/popup (canvas) ─events─▶  WebSocket  ──▶  read_from_devices
        ▲                                                      │
        └──── draw-list (full / patch) ◀── write_to_devices ◀──┘
```

### Running it

```julia
run_web_example("json")          # serve on http://127.0.0.1:8080
run_web_example("json"; port=9000)
run_web_example(["json", "xml"]) # default window in-tab; the rest as popups
```

Then open `http://127.0.0.1:8080`: the **primary** (first) `WindowDocument`
renders directly in that tab immediately — no button to click. Any **additional**
`WindowDocument`s open as their own browser popups, but on the **first
interaction** in the tab (a click or key press), since a browser only opens
pop-ups in response to a user gesture. `run_web_example` accepts the same keyword
arguments as `run_example`; under the hood it is just
`run_example(...; backend=WebBackend(...))`.

### How it satisfies the interface

- **`measure_text` stays on the server.** The layout pipeline calls
  `measure_text` synchronously *while printing*, long before any primitive
  reaches the browser, so the server must measure glyphs the same way the browser
  renders them. `initialize_backend!` runs `SDL_Init` + `TTF_Init` (no window) and reuses
  `sdl_measure_text`; the same TTFs are served to the browser (`/font/<name>`,
  loaded via the `FontFace` API) so metrics line up. The browser handles HiDPI
  with `devicePixelRatio`, so the server stays in logical pixels.
- **`write_to_devices`** serializes the projection-output `ScreenDocument` into a
  per-window draw-list mirroring the SDL element set (`text`, `rect`, `line`,
  `circle`, `clip`=viewport, `group`=nested canvas, `image`; `GraphicsFence`
  skipped) and pushes it over the socket.
- **`read_from_devices`** is non-blocking: a receive task decodes the client's
  JSON events into the backend-agnostic vocabulary (`MouseDown`, `KeyPress`, …)
  wrapped in `EventEnvelope`s on a `Channel`; the editor drains it each frame.
  MousePress synthesis and motion-while-held filtering mirror the SDL backend.

### Wire protocol (JSON, both directions)

Server → client, one ordered message per frame:

```json
{ "type":"update",
  "full":    [ {"id":"json","title":"…","w":…,"h":…,"bg":[…],"draw":[ …primitives… ]} ],
  "patches": [ {"window":"json","clip":[x,y,w,h],"draw":[ …primitives… ]} ],
  "close":   ["someWindowId"] }
```

Client → server (raw browser key fields; the server maps them):

```json
{"type":"mousedown","window":"json","button":"left","x":40,"y":40,"mods":{…}}
{"type":"keydown","window":"json","key":"ArrowLeft","code":"ArrowLeft","mods":{…}}
{"type":"keypress","window":"json","char":"a","text":"a","mods":{…}}
{"type":"resize","window":"json","w":…,"h":…}   {"type":"resync"}   {"type":"quit"}
```

Key mapping is done **on the server** (`web_key_to_symbol`, mirroring
`sdl_keysym_to_symbol`) so the `:left`/`:char`/… vocabulary has a single source
of truth.

### Incremental rendering (dirty-rect patches)

Rather than resend a whole window on every change, a reactive **dirty-walk**
(`_collect_canvas_dirty!` and friends) keyed on the cells' `is_up_to_date` flags
computes the smallest rectangle covering everything that changed since the last
paint, reusing SDL's bounds helpers. Per-window `prev_bounds` unions a unit's old
and new extent so moved/shrunk content clears its vacated pixels.
`_serialize_clipped` then emits only the primitives intersecting that rectangle.

- A window is sent in **`full`** on first paint, on (re)connect, after a resize,
  or on output-queue overflow (`force_full`); otherwise only a **`patch`** is
  sent. Idle frames send nothing.
- The client repaints a patch by clipping to its rect, clearing to the window
  background, and painting over the **retained** canvas. After binding the in-tab
  window (or (re)opening a popup) and after a resize it sends `{type:"resync"}`
  to request fresh full state.
- The savings track the projection's reactivity granularity: a change confined to
  one computed cell yields a tight patch with just that primitive; a change that
  re-projects the whole canvas (e.g. a json caret move) yields a whole-window
  patch — the same granularity SDL's dirty-rect would see.

### Constraints (v1)

One client per editor (a second WebSocket upgrade is rejected); JSON transport
both directions; the SDL-texture `Ptr` image form is skipped (decoded RGBA
buffers are sent as base64). SDL stays the default; the web backend is additive
and selected explicitly.

## File-export backends

The backends above (`SdlBackend`, `ConsoleBackend`, `WebBackend`) are
*interactive* — they drive live output and input devices. Output-only file
export lives alongside the backend layer but does **not** subtype
`Backend` — there are no devices or events, just a `GraphicsCanvas` turned into a
file:

- **`write_image`** ([backend/Sdl.jl](../package/sdl/main/ProjecturedSdl.jl)) rasterizes a
  canvas through an offscreen SDL software renderer to BMP/PNG.
- **`write_pdf`** ([backend/Pdf.jl](../package/visual/main/backend/Pdf.jl)) walks the same
  canvas and emits a **vector** PDF (paths + selectable text, embedded TrueType
  fonts, optional multi-page pagination). It is entirely SDL-free — it measures
  text from the embedded font metrics via `pdf_measure_text`, a drop-in for
  `sdl_measure_text`.

See [the graphics guide](document/graphics.md) for both APIs.

## Projections that need the backend

Some projections need to *measure* text to lay it out (`TextToGraphics`
and `WidgetToGraphics` both word-wrap based on glyph widths). They accept a
`measure::Function` argument so they stay backend-agnostic:

```julia
TextToGraphics(measure = (text, font) -> sdl_measure_text(backend, text, font))
```

Inject the backend's measurer when building the pipeline; the projection
itself never sees the backend type.

## Adding a new device

1. Subtype `Device` in `package/kernel/main/device/`.
2. Add backend methods: `read_from_device(::SdlBackend, ::YourDevice)` and
   if relevant `write_to_device(::SdlBackend, ::YourDevice, document)`.
3. Add the device to the `Vector{Device}` built by the `run_editor!(backend, projection,
   document)` bootstrap in `editor/Editor.jl` (`Device[Screen(), Keyboard(), Mouse()]`).
4. If it emits novel events, declare backend-agnostic event structs alongside
   the device so projection readers can match on them.

## Adding a new backend

1. Subtype `Backend` (defined in `package/kernel/main/backend/`) in your backend package.
2. Implement the `Backend` interface (`initialize_backend!`, `quit_backend!`, `measure_text`) and the
   `Device` I/O functions (`read_from_devices`, `write_to_devices`).
3. Translate native events into the existing backend-agnostic event types
   so projection code does not need to change.
4. Provide a `measure_text` callback for projections that need it.

The fact that every event projection-level is a `KeyPress`/`KeyDown`/`Mouse*`/`WindowQuit`
is the contract that keeps backends interchangeable.

[backend/Web.jl](../package/web/main/ProjecturedWeb.jl) is a worked second example: it
adds a whole new transport (HTTP + WebSocket, with the renderer living in a
browser) yet touches no projection or domain code, precisely because it speaks
the same event vocabulary and consumes the same `ScreenDocument` output as the
SDL backend.
