# Devices and backends

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

ProjecturEd separates the **what** of I/O (a `Device`) from the **how**
(a `Backend`). A `Device` describes a logical input or output channel; a
`Backend` provides the platform-specific machinery to drive it. This split
makes it possible to add a new backend (terminal, web, JetBrains plugin, …)
without rewriting projection code, and to add a new device (e.g. a touch
panel) without modifying existing backends beyond the device's own
dispatch.

The abstract interfaces live in
[backend/BackendInterface.jl](../../../source/kernel/backend/BackendInterface.jl) and
[device/DeviceInterface.jl](../../../source/kernel/device/DeviceInterface.jl). There are four backends:
`SdlBackend` draws in native windows and is the default, `ConsoleBackend` draws
in a terminal, `WebBackend` runs the editor in an HTTP and WebSocket server and
draws in the browser, and `VideoBackend` draws the frames of a video file. The
test double `HeadlessBackend` keeps its output in memory. The section
[Backends](#backends) describes each one.

Every backend is a drop-in: `run_editor!` takes the backend as a keyword, so switching
is just e.g. `run_editor!(document, projection; backend = WebBackend())` instead of
`run_editor!(document, projection; backend = SdlBackend())` — nothing in the editor
loop, projection pipeline, or domains changes. With no `backend`, the one loaded
backend that draws windows runs the editor.

## Devices

| Device | Defined in | What it holds |
|---|---|---|
| `Display` | `device/Display.jl` | The usable size in logical pixels, the `density` of the hardware (the device pixels in one logical pixel), and the `zoom` of the editor |
| `Keyboard` | `device/Keyboard.jl` | The `layout` of the keys |
| `Mouse` | `device/Mouse.jl` | The `button_count`, and `has_scroll_wheel` |

A device holds the physical properties of its hardware, and it has no
behaviour. The editor holds a `Vector{Device}`. `make_editor` gives it to
`configure_devices!`, which fills the properties that the backend can find. The
events come from the backend, not from a device object: `KeyPress` and `KeyDown`
are in `event/KeyboardEvent.jl`, and the `Mouse*` events are in
`event/MouseEvent.jl`.

### The device pixel ratio

`get_device_pixel_ratio(display)` is `display.density * display.zoom`: the number
of device pixels that a backend draws for one logical pixel. Layout and events
work in logical pixels. The SDL backend keeps the `Display` that
`configure_devices!` gives it. It sizes its windows, rasterizes its text and
converts its input coordinates with the ratio of that `Display`. The zoom of an
editor is in its `Appearance`, and the `appearance` wrapper copies it into the
`Display` of the editor, so Ctrl+= and Ctrl+- change the zoom of one editor. The
web backend sends the `zoom` of its `Display` to the browser, which draws with it.
The console backend leaves the `Display` at its defaults.

### Backend-agnostic events

Projection readers only see these events, never SDL-specific structs:

```julia
KeyPress('a'; time = t)                           # character input
KeyDown(:left, ModifierKeys(); time = t)          # arrow key, no modifiers
KeyDown(:return, ModifierKeys(ctrl=true); time = t) # Ctrl-Enter
MouseClick(:left, 132, 47; time = t)              # left button at pixel (132, 47)
MouseMove(120, 90; time = t)                      # cursor moved to (120, 90)
MouseScroll(0, 1, 200, 300; time = t)             # wheel scrolled (dx, dy) at (200, 300)
WindowQuit(; time = t)                            # the user asked to quit the application
```

Every event holds `time`, the time of the input in seconds on the clock of
`time()`, and no constructor has a default for it. A backend gives the time of
the input from its own stamps: SDL converts the ticks of its events, the web page
sends the time of each browser event, and the console takes the time when it
reads the bytes. Code that makes an event from another event, such as a reader
that moves a pointer event into the space of a child, gives the time of that
event. A gesture tracking projection compares these times, so a slow frame between a
press and its release does not lose a click.

This vocabulary is what insulates a `TextToGraphics.read_intent` (which
maps the `:left`/`:right` `KeyDown` keys to a `ReplaceSelectionOperation`) from
any specific backend.

Escape is an ordinary `KeyDown(:escape, …)`, not a quit. A backend reports what
happened and attaches no meaning, so it must not turn one key into a quit before
any reader has seen it. A dialog, an insertion and the command palette all bind
Escape, and a quit the backend issues directly leaves no reader able to stop it.
The editor loop quits on an unmodified
Escape that the pipeline did not handle; `run_read_stage!` in
[editor/ReadEvaluatePrint.jl](../../../source/kernel/editor/ReadEvaluatePrint.jl)
recognises no other gesture itself.

## Backends

A backend subtypes `Backend` and adds a method of each generic of
[backend/BackendInterface.jl](../../../source/kernel/backend/BackendInterface.jl)
that it answers, for its own type:

```julia
abstract type Backend end

initialize_backend!(::Backend)                       # load libraries, allocate caches
configure_devices!(::Backend, devices)               # fill the properties of the devices
open_native_windows!(::Backend, document)            # open the windows before the first print
take_from_devices!(::Backend, devices)                # the next input, or nothing
write_to_devices!(::Backend, devices, document)       # show the output of a frame
wait_for_input(::Backend, devices, timeout_seconds)  # block until input, a wake or the timeout
wake_backend!(::Backend)                             # end a wait, from any task or thread
get_display_size(::Backend)                          # the usable size in logical pixels
find_system_colors(::Backend)                        # the colour settings of the system, or nothing
get_pointer_position(::Backend)                      # the global position of the pointer
quit_backend!(::Backend)                             # release everything
```

`make_editor` calls `initialize_backend!`, `configure_devices!` and
`open_native_windows!`, in that order, before the first print, and `play_live!`
calls them in the same order. `configure_devices!` fills the devices of the
editor in place. A backend that draws with a device keeps that device: the SDL
backend draws with the `Display` that it gets. `open_native_windows!` opens the
native window of each window of the document, and corrects the document to the
size that the window system gives. So the first layout has the final size. After
that, `write_to_devices!` reconciles the native windows with each new
`ScreenDocument`.

The wait is where the editor sleeps between frames, and the wake is how a
producer on another task ends the sleep. `timeout_seconds` must be above zero, and
`Inf` is legal. The defaults in `BackendDefaults.jl` are one 10 ms poll slice and
a no-op, so a backend that answers neither polls every 10 ms.

There are four backends and a test double:

| Backend | Package | Output | Input |
| --- | --- | --- | --- |
| `SdlBackend` | `ProjecturedSDL`, opt-in | native windows | the keyboard, the mouse and the windows |
| `WebBackend` | `ProjecturedWeb`, opt-in | a canvas in a browser page | the events that the page sends |
| `ConsoleBackend` | `ProjecturedConsole`, required | a terminal, for the text domain | the bytes of the terminal |
| `VideoBackend` | `ProjecturedVideo`, opt-in | the frames of a video file | a scripted timeline |
| `HeadlessBackend` | `ProjecturedKernelExample`, test double | a log of each output | a queue of scripted events |

Each generic has a method of its own in a backend (✓), or the backend uses the
default of `BackendDefaults.jl`. A generic with no default and no method raises a
`MethodError` (—).

| Generic | Default | SDL | Web | Console | Video | Headless |
| --- | --- | --- | --- | --- | --- | --- |
| `initialize_backend!` | — | ✓ | ✓ | ✓ raw mode | ✓ | ✓ no-op |
| `quit_backend!` | — | ✓ | ✓ | ✓ | ✓ | ✓ no-op |
| `take_from_devices!` | — | ✓ motion coalesced | ✓ | ✓ | ✓ timeline | ✓ queue |
| `write_to_devices!` | — | `ScreenDocument` | `ScreenDocument`, an error for another value | `TextBlock`, an error for another value | `ScreenDocument`, one window | any value |
| `wait_for_input` | a sleep of at most 10 ms | ✓ | ✓ | ✓ | ✓ at most one frame | default |
| `wake_backend!` | no-op | ✓ | ✓ | ✓ | default | default |
| `open_native_windows!` | no-op | ✓ | default | default | default | default |
| `configure_devices!` | no-op | ✓ keeps the `Display` | default | default | default | default |
| `get_display_size` | `(1280, 800)` | ✓ | default | default | ✓ the video size | default |
| `find_system_colors` | `nothing` | ✓ gsettings, the portal, the registry, defaults | default | default | default | ✓ the script |
| `get_pointer_position` | `(-1, -1)` | ✓ | default | default | ✓ the last pointer | default |
| `write_image` | — | ✓ | — | — | — | — |
| `record_video` | — | — | — | — | ✓ | — |
| `render_canvas` | — | an empty image | — | — | — | — |
| `decode_image` | — | ✓ | — | — | — | — |

### SdlBackend

`SdlBackend` (in [source/backend/sdl/SdlBackend.jl](../../../source/backend/sdl/SdlBackend.jl)) implements
all of the above with SDL2 + SDL_ttf; [sdl.md](../backend/sdl/sdl.md) is its design document. Highlights:

- A font measurement cache shared across all windows.
- `sdl_to_keydown` maps an SDL keysym and the modifier bits to a `KeyDown`, and
  `sdl_to_keypress` makes a `KeyPress` from an `SDL_TEXTINPUT` event.
- Mouse events are mapped inline in `take_from_devices!` (there is no
  `sdl_to_mouse` function) to the `Mouse*` structs.
- The painter walks a `GraphicsCanvas` (and its nested
  `GraphicsViewport`/`GraphicsImage`/`GraphicsFence` children) and issues
  SDL draw calls. `render_sdl_canvas` is a stub that returns an empty image.
- `wait_for_input` blocks in `SDL_WaitEventTimeout` with a NULL event
  pointer — SDL's look-only form, so everything stays queued for `run_read_stage!` —
  in GC-safe slices with a `yield` between them. `wake_backend!` pushes a
  user event registered at `initialize_backend!`; `SDL_PushEvent` is SDL's
  documented thread-safe entry, and `_poll_window_input` skips the event
  like any other unknown type.

### ConsoleBackend

`ConsoleBackend` (in [source/backend/console/ConsoleBackend.jl](../../../source/backend/console/ConsoleBackend.jl))
renders the **Text domain** straight to a terminal. Crucially it consumes a
`TextBlock` directly and skips `TextToGraphics`: its pipeline is
`JsonToSyntax → SyntaxToText` (no graphics step), so `write_to_devices!` receives
a `TextBlock` rather than a `ScreenDocument`. Highlights:

- `write_to_devices!` flattens the spans to a character stream, preserving each
  span's `font_color`/`fill_color` as 24-bit ANSI SGR codes (set `ansi=false`
  for plain output). The selection is shown as inverse-video span colors baked
  in by the `SelectionInverting` projection at the end of the console pipeline,
  so the backend itself just emits each span's colors.
- `take_from_devices!` polls `backend.input` (default `stdin`) non-blockingly and
  translates terminal bytes — printable chars, the `ESC [` sequences of the
  arrows, Home/End, Insert/Delete, Page Up/Down and the function keys with the
  modifiers of their xterm parameter, Enter/Backspace/Tab, Ctrl-Space, Ctrl-C,
  the Ctrl bytes of the letters (0x01 is Ctrl+A), Escape and the ESC-prefixed Alt
  chords — into the same
  `KeyDown`/`KeyPress`/`WindowQuit` vocabulary the readers already use, wrapped in
  an `WindowInput(:console, …)`. `initialize_backend!`/`quit_backend!` toggle the terminal's raw mode.
- `wait_for_input` waits on an autoreset gate a watcher task notifies: the
  watcher blocks on the TTY through libuv (`Base.wait_readnb`), a `Timer`
  bounds the wait, and `wake_backend!` notifies the gate directly. An
  `IOBuffer` input has no watcher and degrades to the default poll slice.
- Because the console has no screen/window layer, the pipeline supplies its own
  window-input-unwrapping seam — `WindowInputUnwrappingProjection`
  ([projection/higherorder/WindowInputUnwrapping.jl](../../../source/platform/projection/higherorder/WindowInputUnwrapping.jl))
  — that strips the `WindowInput` off the gesture before the readers run. (In
  the SDL pipeline `ScreenToScreen` does this.)
- The console has no `TextToGraphics`, so it has only the geometry-free
  gestures: the `@gestures` table of `TextBlock` (character insert,
  Backspace, Delete, left and right), the tree navigation and the
  `Ctrl+Space` mode toggle. Visual up and down, and a mouse click, need the
  geometry and do not work. [console.md](../backend/console/console.md) is its design document.

Run it with `run_console_example()` (one-shot) or
`run_console_example(interactive=true)` (read-eval-print loop).

### WebBackend

`WebBackend` ([package/ProjecturedWeb/src/ProjecturedWeb.jl](../../../package/ProjecturedWeb/src/ProjecturedWeb.jl)) runs the editor
inside an HTTP + WebSocket server and moves the **final rendering step into the
browser**. The Julia process keeps the document, projection pipeline, reactive
cells, and the read-eval-print loop; a connected JavaScript client
([package/web/assets/](../../../asset/web/)) is a thin terminal that captures raw mouse and
keyboard events and paints a JSON **draw-list** onto an HTML `<canvas>`.

```
 browser tab/popup (canvas) ─events─▶  WebSocket  ──▶  take_from_devices!
        ▲                                                      │
        └──── draw-list (full / patch) ◀── write_to_devices! ◀──┘
```

#### Running it

```julia
using ProjecturedWeb               # brings WebBackend into scope
run_example("json"; backend=WebBackend())            # serve on http://127.0.0.1:8080
run_example("json"; backend=WebBackend(port=9000))
run_example(["json", "xml"]; backend=WebBackend())   # default window in-tab; the rest as popups
```

Then open `http://127.0.0.1:8080`: the **primary** (first) `WindowDocument`
renders directly in that tab immediately — no button to click. Every
**additional** `WindowDocument` opens as a browser window of its own.

A browser opens a window only inside a transient user activation. The client
does not fold a window into the page: on the first interaction in the tab it
opens one window and holds it empty, and gives it to the next window that arrives
without an activation. A gesture refills the reserve. A window is a window here
as it is on SDL, which is
[PAR-MANY-WINDOWS](../../rule/architecture-invariants.md#par-many-windows). The
page sends pointer motion only while a button is held, so a hover effect and a
tooltip do not happen in the browser ([web.md](../backend/web/web.md) states the limit).
Selecting the web backend is just passing
`backend=WebBackend(...)` to `run_example`, which otherwise takes the same
arguments; `WebBackend`'s constructor defaults `host`/`port`.

#### How it satisfies the interface

- **The measure stays on the server.** The layout pipeline measures text
  synchronously *while printing*, long before any primitive reaches the
  browser, so the server must measure glyphs the same way the browser renders
  them. `TextToGraphics` measures with a `FontFileMeasure()`, the pure-Julia
  TrueType measurer of the platform's style slice, so it needs no SDL; the same TTFs are served to the browser (`/font/<name>`,
  loaded via the `FontFace` API) so metrics line up. The browser draws each
  logical pixel as `devicePixelRatio × zoom` pixels, with the `zoom` of the
  `Display` that each update carries, and divides each size and each pointer
  position that it sends by `zoom`, so the server stays in logical pixels. A new
  zoom sends every window in full.
- **`write_to_devices!`** serializes the projection-output `ScreenDocument` into a
  per-window draw-list mirroring the SDL element set (`text`, `rect`, `line`,
  `circle`, `clip`=viewport, `group`=nested canvas, `image`; `GraphicsFence`
  skipped) and pushes it over the socket.
- **`take_from_devices!`** is non-blocking: a receive task decodes the client's
  JSON events into the backend-agnostic vocabulary (`MouseDown`, `KeyPress`, …)
  wrapped in `WindowInput`s on a `Channel`; the editor drains it each frame.
  The backend makes no `MouseClick`: a gesture tracking projection makes
  it from a `MouseDown` and a `MouseUp`, as for SDL. [web.md](../backend/web/web.md) is
  its design document.
- **`wait_for_input`** blocks on an autoreset gate until the receive task puts
  an event into the channel, `wake_backend!` is called, or the timeout ends. A
  new connection and a `resync` notify the gate too, because the next frame
  must send every window in full.

#### Wire protocol (JSON, both directions)

Server → client, one ordered message per frame:

```json
{ "type":"update",
  "zoom":    1.5,
  "full":    [ {"id":"json","title":"…","w":…,"h":…,"bg":[…],"draw":[ …primitives… ]} ],
  "patches": [ {"window":"json","clip":[x,y,w,h],"draw":[ …primitives… ]} ],
  "close":   ["someWindowId"] }
```

Client → server (raw browser key fields; the server maps them):

```json
{"type":"mousedown","window":"json","button":"left","x":40,"y":40,"mods":{…},"t":…}
{"type":"keydown","window":"json","key":"ArrowLeft","code":"ArrowLeft","mods":{…},"t":…}
{"type":"keypress","window":"json","char":"a","text":"a","mods":{…},"t":…}
{"type":"resize","window":"json","w":…,"h":…}   {"type":"resync"}   {"type":"quit"}
```

The server maps the keys (`convert_web_key_to_symbol`) to the names of the event
layer. A letter key has the name of its lower-case letter, as in the SDL and the
console backends. The page names the left, the middle and the right button, and
it sends no `mousedown` and no `mouseup` for a side button; the server also drops
a message with another button name. A wheel turn away from the user sends a
positive `dy`, as SDL does.

#### Incremental rendering (dirty-rect patches)

Rather than resend a whole window on every change, a reactive **dirty-walk**
(`_collect_canvas_dirty!` and friends) keyed on the cells' `is_cell_up_to_date` flags
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

#### Constraints (v1)

One client per editor (a second WebSocket upgrade is rejected); JSON transport
both directions; the SDL-texture `Ptr` image form is skipped (decoded RGBA
buffers are sent as base64). SDL stays the default; the web backend is additive
and selected explicitly.

[package/ProjecturedWeb/src/ProjecturedWeb.jl](../../../package/ProjecturedWeb/src/ProjecturedWeb.jl) is a worked second example: it
adds a whole new transport (HTTP + WebSocket, with the renderer living in a
browser) yet touches no projection or domain code, precisely because it speaks
the same event vocabulary and consumes the same `ScreenDocument` output as the
SDL backend.

## File-export backends

The backends above drive output and input. The file export below does not
subtype `Backend`: it has no devices and no events, and it turns a
`GraphicsCanvas` into a file.

- **`write_image`** ([source/backend/sdl/SdlBackend.jl](../../../source/backend/sdl/SdlBackend.jl)) rasterizes a
  canvas through an offscreen SDL software renderer to BMP/PNG.
- **`write_pdf`** ([source/backend/pdf/PdfWriter.jl](../../../source/backend/pdf/PdfWriter.jl)) walks the same
  canvas and emits a **vector** PDF (paths + selectable text, embedded TrueType
  fonts, optional multi-page pagination). It is entirely SDL-free — it measures
  text from the font files, with a `FontFileMeasure()`.
- **`record_video`** ([package/ProjecturedVideo/src/ProjecturedVideo.jl](../../../package/ProjecturedVideo/src/ProjecturedVideo.jl))
  renders a timed sequence of gestures or operations to an `.mp4` file, with no
  window: it rasterizes each frame through the same offscreen SDL renderer as
  `write_image`, then encodes the frames with `ffmpeg` (via `FFMPEG.jl`). It
  is a separate opt-in package because it is the only one that pulls in FFMPEG.
  The same package holds `VideoBackend`, a `Backend` over the same renderer,
  which plays a scripted timeline through the `run_editor!` loop.

See [the graphics guide](../platform/graphics/graphics.md) for the image and PDF APIs.

## Projections that measure text

Some projections need to lay out text (`TextToGraphics`, `WordWrapping` and
`WidgetToGraphics` among them). They take a `measure::TextMeasure` argument, from
the platform's style slice, so they stay backend-agnostic:

```julia
TextToGraphics(measure = FontFileMeasure())
```

`FontFileMeasure()` reads the font files, as every backend draws them, so the
projection never asks the backend to measure. A test passes a `FixedMeasure`
instead.

## Adding a new device

1. Subtype `Device` in `source/kernel/device/`. Make it a mutable struct with a
   keyword constructor whose defaults describe common hardware.
2. If a backend can find the properties of the hardware, fill them in its
   `configure_devices!`.
3. Add the device to `_make_default_devices()` in `editor/EditorLoop.jl`
   (`Device[Display(), Keyboard(), Mouse()]`), the default `devices` of
   `make_editor` and of `build_editor`.
4. If it emits novel events, declare backend-agnostic event structs in
   `source/kernel/event/` so projection readers can match on them.

## Adding a new backend

1. Subtype `Backend` (defined in `source/kernel/backend/`) in your backend package.
2. Add a method of `initialize_backend!`, `quit_backend!`, `take_from_devices!`
   and `write_to_devices!`, which have no default.
3. If the platform can block until input arrives, add a method of
   `wait_for_input` and of `wake_backend!`. If the backend has native windows,
   add a method of `open_native_windows!`. If it can find the properties of the
   hardware, add a method of `configure_devices!`.
4. Translate native events into the existing backend-agnostic event types
   so projection code does not need to change. A letter key has the name of its
   lower-case letter, a button that the event layer does not name makes no
   event, and a positive `dy` of a `MouseScroll` is a wheel turn away from the
   user.
5. Draw each glyph where a `TextMeasure` places it, so the ink lands where the
   layout put it.

The fact that every event at the projection level is a `KeyPress`/`KeyDown`/`Mouse*`/`WindowQuit`
is the contract that keeps backends interchangeable.

---

# Internals

The remainder of this guide documents the kernel-internal module structure
behind the three abstractions: **devices** — the input event vocabulary, the
device types, and the gesture vocabulary, spread across three layers
(`event/`, `device/`, `gesture/`) — and the **backend layer**. They are
independent siblings: the event/device/gesture layers name no backend type,
and the two abstractions only come together in a concrete implementation.
Gesture recognition — a click, a double click, a key chord, a dwell — is the
gesture layer (`gesture/`); see
[Where gestures are recognized](#where-gestures-are-recognized) below. Gesture
*bindings*, where a gesture acquires meaning against a document, are a
separate, much higher layer (`binding/`); see
[below](#gesture-bindings-a-separate-higher-layer).

## The event layer (layer 6)

Layer 6 of the kernel — **input events**. The layer depends on nothing: an
event is data, and carries no reference to the device that produced it, nor to
the document it will end up changing. The layer names no gesture: the gesture
layer above finds the gestures that several events make, and holds the
pattern language that matches both.

The layer lives in [source/kernel/event/](../../../source/kernel/event/):

```
EventModule.jl (EventModule) — the module: its docstring, exports, and nine fragments
        ├─ EventInterface.jl — Event, and get_modifier_keys and get_event_time, the
        │                      generics that every input answers
        ├─ ModifierKeys.jl   — the Ctrl, Shift, Alt and Meta keys that an event holds
        ├─ KeyboardEvent.jl  — KeyDown, KeyUp, KeyPress
        ├─ MouseEvent.jl     — MouseButtons, and MouseDown, MouseUp, MouseMove,
        │                      MouseScroll
        ├─ WindowEvent.jl    — WindowQuit, WindowClose, WindowResize, WindowDefocus,
        │                      WindowLeave
        ├─ TimerEvent.jl     — TimerExpire, the event of a timer that a reader set
        ├─ DisplayEvent.jl   — DisplayUpdate, a display shows a new frame of a window
        ├─ SystemEvent.jl    — SystemColors, the colour settings of the operating
        │                      system, and SystemColorsChange, their change
        ├─ WindowInput.jl    — an event or a gesture and the id of the window it
        │                      came from
        └─ EventDefaults.jl  — the fallbacks of get_modifier_keys and
                               get_event_time, and the four has_*_modifier_key
                               predicates over get_modifier_keys
```

### The events

An `Event` is a record of what a device reports — `KeyDown`, `MouseDown`,
`WindowClose`, … An event is plain data: its fields hold symbols, numbers,
characters, modifier keys and the time of the input, and it holds no
reference to the source that made it, or to the document it will end up
changing. Every event answers two generics. `get_event_time` returns the time
of the input. `get_modifier_keys` returns the modifier keys, and
`has_ctrl_modifier_key`, `has_shift_modifier_key`, `has_alt_modifier_key` and
`has_meta_modifier_key` read it. These functions are defined once over `Event`,
so they work for mouse events as well as keyboard ones. The gesture layer gives
them methods for `Gesture` too, so a caller that holds either kind reads them the
same way.

`WindowQuit` is a request to quit the whole application. `WindowClose` is a
request to close one window. `WindowClose`, `WindowResize`, and `WindowDefocus`
live here, not with the concrete `ScreenDocument` of the screen package: a window
event is report-only input vocabulary, not a document type. The window
*document* and its operations (`OpenWindowOperation`, `CloseWindowOperation`, …)
stay in `source/platform/screen/`.

### WindowInput

`WindowInput{E}` wraps an input with the id of the window it came from. An
event source makes one with an event; the recognition of gestures makes one
with a gesture; the field is named `event` for both kinds, and the type is
generic over it, so this layer names no gesture. It lives in `EventModule`,
not in the concrete `ScreenModule` document, because it is a protocol type
consumed by the editor loop, the recognitions of the gesture layer, and the
window-input-unwrapping projection — a plain struct declaration for a
protocol type does not belong inside a concrete document; keeping it here
means the kernel has no edge onto `ScreenDocument`.

(This is the canonical statement of the `WindowInput`-placement rationale;
other package docs defer here rather than repeat it.)

## The device layer (layer 7)

Layer 7 of the kernel — **the input/output devices**: `Display`, `Keyboard`,
and `Mouse` under an abstract `Device`. Each holds its physical properties: the
size, the density and the zoom of a display, the buttons and the scroll wheel of a
mouse, and the layout of a keyboard. A device interprets nothing, so this layer
names no document, no operation and no backend type, and has no imports of its
own. Its one function is `get_device_pixel_ratio`.

The layer lives in [source/kernel/device/](../../../source/kernel/device/):

```
DeviceModule.jl (DeviceModule) — the module: its docstring, exports, and fragments
        ├─ DeviceInterface.jl — the Device abstract supertype
        ├─ Keyboard.jl        — the Keyboard device
        ├─ Mouse.jl           — the Mouse device
        └─ Display.jl         — the Display device and get_device_pixel_ratio
```

The devices carry their physical properties but no behaviour. The batch I/O
that drives them — `take_from_devices!` / `write_to_devices!` — is declared
higher, in the backend interface (see [Backends](#backends)), and dispatched on
the concrete backend, which also fills in the physical properties at start-up
via `configure_devices!`. That keeps the device and backend abstractions
independent siblings, bound only by a concrete implementation.

## Where gestures are recognized

Layer 8 of the kernel, `gesture/`, holds **the gestures, the pattern language
and the recognitions**. A gesture is a pattern that several events make — a
click with its count, a key chord, a mouse dwell — and the code that holds the
state across the events makes it. A gesture is not an event: the two are
separate type trees, and a place that takes either takes `Union{Event,Gesture}`.

The layer lives in [source/kernel/gesture/](../../../source/kernel/gesture/):

```
GestureModule.jl        (GestureModule) — the aggregator, eight fragments:
        ├─ GestureInterface.jl   — Gesture, and the methods of get_modifier_keys
        │                          and get_event_time for a gesture
        ├─ MouseGesture.jl       — MouseClick, MouseDwell
        ├─ KeyboardGesture.jl    — KeyChord
        ├─ GesturePattern.jl     — the pattern language: GesturePattern, the
        │                          parser, and @gesture_case
        ├─ GestureRecognition.jl — GestureRecognition, make_recognition_state,
        │                          recognize, RecognitionStep, make_standard_recognitions
        ├─ ClickRecognition.jl   — ClickRecognition
        ├─ ChordRecognition.jl   — ChordRecognition
        └─ DwellRecognition.jl   — DwellRecognition
```

**The pattern language.** One surface syntax says "this kind of event or
gesture, with these field values and these modifiers held". It has two forms. A
[`GesturePattern`](../../../source/kernel/gesture/GesturePattern.jl) is *data*:
`matches_gesture_pattern(pattern, input)` tests an input, and
`describe_gesture_pattern(pattern)` writes the input for a person. The per-kind
constructors (`KeyDownPattern`, `MouseClickPattern`, …) name the type and its
most-constrained field, and all of them make the one generic
`GesturePattern{E<:Union{Event,Gesture}}` struct.
[`@gesture_case`](../../../source/kernel/gesture/GesturePattern.jl) compiles a
table of `pattern => result` rules straight to `isa`/field tests, and the first
match wins.

Both forms use one parser. The module exports it as an API for a macro writer:
`GesturePatternRule`, `parse_gesture_pattern_rule`, `build_gesture_pattern_expr`
and `build_gesture_field_bindings`. So the `@gestures` DSL in the binding layer
uses the same syntax and does not implement it again. The name of an event or
gesture type in a pattern resolves in the module where the pattern is written,
and then in `GestureModule`. So an event or gesture type of another package is
matchable in that package, with no entry to add here.

**The recognitions.** A `GestureRecognition` is a pure rule:
`make_recognition_state(recognition)` gives its first, immutable state, and
`recognize(recognition, state, input, window)` reads one input — an event or a
gesture, with the id of the window it came from — and answers a
`RecognitionStep`: the next state, the inputs that follow (the gesture the
input completes, or inputs it kept and gives back), a deadline or `nothing`,
and whether it holds the input from the recognitions after it.
`make_standard_recognitions()` lists the three standard recognitions in order:
`ChordRecognition`, `ClickRecognition`, `DwellRecognition`. A package adds a
gesture with a gesture type and a recognition; see
[gesturetracking.md](../platform/gesturetracking/gesturetracking.md) for the full
protocol.

`run_read_stage!` gives the projection each input of the backend: a `WindowInput` with
an event or a gesture and a window id, or a due timer, a `TimerExpire`. The
editor recognizes no gesture. `GestureTrackingProjection`, in the platform's
gesturetracking slice, runs the recognitions over the inputs,
and a host wraps the document of the editor in its `GestureTrackingState`. An
editor whose projection has no gesture tracker gets events and no gestures.
The meaning of a gesture is decided where it is bound, in the `binding/` layer.

## The backend layer (layer 9)

Layer 9 of the kernel — **the seam to a platform**: the life of a backend, one
input at a time, the output of each frame, the wait between frames, a few
queries, and the output to a file. The layer carries the abstract `Backend` type
and the backend generics. The SDL, web and video backends live in opt-in
packages, and the console backend is a package of its own, not opt-in. The dependency-free
`HeadlessBackend` test double lives in `ProjecturedKernelExample`
(PAR-NO-TEST-DOUBLES-IN-MAIN keeps doubles out of `main`).

The layer lives in [source/kernel/backend/](../../../source/kernel/backend/):

```
BackendModule.jl    (BackendModule)         — the module: its docstring, exports, and fragments
BackendInterface.jl (BackendModule)         — Backend abstract + batch generics
BackendDefaults.jl  (BackendModule)         — the fallback behaviours the contract supplies itself
```

### BackendModule

Declares `Backend <: Any` and the backend generics `initialize_backend!`,
`quit_backend!`, `write_to_devices!`, `open_native_windows!`, `take_from_devices!`,
`wait_for_input`, `wake_backend!`, `get_pointer_position`, `get_display_size`,
`find_system_colors`, `configure_devices!`, `write_image`, `record_video`, `render_canvas` and
`decode_image`. A concrete backend lives in a package above the kernel, subtypes
`Backend` and adds methods for its own `::MyBackend` type (see the tables in
[Backends](#backends)). A backend is constructed by
naming its type directly (`SdlBackend()`, `ConsoleBackend()`). Code that must
pick a backend without depending on its package uses
[`default_backend`](../platform/application/application.md),
which matches a caller-supplied ordered list of type names (`:SdlBackend`, …)
against the loaded `Backend` subtypes by reflection — no coined `:kind` key and
no per-backend registration.

`BackendInterface.jl` is an **interface file** (PAR-INTERFACE-DECLARES-ONLY): it declares and never implements,
so every generic there is a bodiless `function f end`. The fallback behaviours
the contract supplies for itself sit beside it in `BackendDefaults.jl`, for the
capabilities a backend can lack: `get_pointer_position` answers `(-1, -1)`,
`get_display_size` answers `(1280, 800)`, `find_system_colors` answers `nothing`
(the backend can not find the colour settings of the system),
`configure_devices!` is a no-op that
leaves the devices at their default properties, `open_native_windows!` is a
no-op for a backend that has no native windows to open, `wait_for_input` sleeps
for at most 10 ms, and `wake_backend!` is a no-op. Each is a legal answer rather
than a missing implementation. The batch generics deliberately have no
such fallback: an unimplemented `write_to_devices!` or `write_image` must raise a
`MethodError` rather than fabricate a result.

No document is imported here. The batch I/O generics are duck-typed on the
`document` argument, so the layer stays document-free.

### The HeadlessBackend test double

The dependency-free in-memory `HeadlessBackend` — which logs every
`write_to_devices!` document into `rendered` and pops scripted events on each
`take_from_devices!` (`push_event!` enqueues them) — is a **test double** for the `Backend` seam. By
PAR-NO-TEST-DOUBLES-IN-MAIN it lives in `ProjecturedKernelExample`, not here, so
no double is reachable from a production build; the kernel editor tests import it
from there to drive the loop without any real backend.

### Downward edges

`BackendModule` declares bodiless generics and imports nothing — the backend
layer has no downward edges. No document, reference, operation, projection,
agent, or editor.

## Gesture bindings: a separate, higher layer

Recognising a gesture and giving it *meaning* are different heights: a
gesture is a combination of events and carries no intent, but deciding what a
`MouseClick` does to a `JsonArray` needs `Document` and `Operation`. That
pulls gesture bindings up to layer 15 — `binding/` — above `document/`,
`reference/`, `selection/`, and `operation/`, rather than beside the
event/device/gesture layers below.

The layer lives in [source/kernel/binding/](../../../source/kernel/binding/):

```
GestureBindingModule.jl (GestureBindingModule)   — the aggregator
        ├─ GestureBindingInterface.jl — the contract: read_gesture, and the two
        │                               tables that other packages add bindings to
        │                               (get_document_gesture_bindings_own,
        │                               get_instance_gesture_bindings)
        ├─ GestureBinding.jl — GestureBinding, the per-document-type registry,
        │                      fire_gesture_bindings / fire_named_gesture_binding,
        │                      read_bound_gesture, and the catch-all read_gesture
        └─ Gestures.jl — the @gestures / @gesture_set authoring DSL
```

A `GestureBinding` is reified *data*: an `GesturePattern` (what fires it, and
how it is described) + `operation(document, event) -> Operation | Nothing` +
an `applicable(document, selection) -> Bool` precondition + a human
`description` + a `domain` tag + an optional `name` — the same declaration both
fires the edit and can be listed to a user. [`@gestures`](../../../source/kernel/binding/Gestures.jl)
emits the `get_document_gesture_bindings_own` method holding a type's own
table; `collect_document_gesture_bindings` walks it plus every supertype's.
`fire_gesture_bindings(bindings, target, event; selection, claimed = nothing)` is
the one firing loop — the first binding whose pattern matches, whose precondition holds, and
whose operation returns non-`nothing`, wins — shared by
`read_bound_gesture(target, event[, selection])` (the catch-all behind
`read_gesture(::Document, event)`) and the projection layer's own
gesture-binding reader, so *what fires* cannot drift from what a listing
shows. `read_bound_gesture`'s optional third argument covers a target whose
selection comes from elsewhere (e.g. a node addressed by path inside its
enclosing document), so one entry point serves both.

#### Asking what is available

`fire_gesture_bindings` answers one more thing than an event: the `CollectIntents`
payload. Given it, the same table produces an `Intent` per rule — each carrying the
operation that rule would build right now — wrapped in a
`CollectedIntentsOperation`. An `Intent` with no operation is a rule that cannot
fire: its precondition failed, or it needs the keystroke that carries its argument.

That is the whole of "is this available?". There is no separate predicate to
consult and no second traversal to keep in step: the answer is the built operation
itself.

Because it shares the same dispatch as an ordinary gesture, every
`@gestures`-declared document and every projection that delegates to
`read_projection_gesture` answers it with no code of its own. And because `CollectedIntentsOperation` is an ordinary `Operation`, every
container reroots the operations inside it on the way up — so a collection that
arrives at the top of a chain is expressed in the top document's vocabulary, and a
caller runs a row by applying it.

#### A rule with no gesture

The pattern is optional. A binding whose `pattern` is `nothing` has no gesture at
all: no key and no click reaches it, and `fire_gesture_bindings` skips it. Only
its `name` does, through `fire_named_gesture_binding(bindings, target, name;
selection)` — the counterpart that selects a binding by the name a user types instead
of by the event that fires it, and passes `nothing` for the event.

Write it in the pattern slot of the rule form that already exists:

```julia
@gestures JsonObject begin
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc; from = :key, to = :value)
    nothing       => "Move from value to key" => move_to_field(doc; from = :value, to = :key)
end
```

The author writes in the pattern slot exactly what the field holds, so a reader
of the table sees the absence of a gesture and has no second surface to learn.
Three rules follow from the shape. A `nothing` rule must carry a description,
because the description is the name and there is no pattern to derive one from. A
`nothing` rule binds no pattern variable, so its body reads `doc` and `sel` only.
`override(nothing)` is an error, because override claims a key and there is none.

`name` is filled in by `@gestures`, and only when the author wrote a description
**and** the rule reads no event. A rule that binds a pattern variable — JSON's
`when(KeyPress(c), isdigit(c))` — has no name, because a name carries no event to
read `c` from. A rule with no description has none either: its description is the
gesture rendering (`"Ctrl+K"`), which is not a command name.

This is what puts an operation in front of a user without spending a key on it.
The command palette of the `gesturehelp` slice of the platform lists these by
name; see [CommandPalette.jl](../../../source/platform/gesturehelp/CommandPalette.jl).

### Downward edges

- `..EventModule` — the events that a binding reads.
- `..GestureModule` — the pattern a binding matches on, and the parser of the
  pattern syntax that `@gestures` uses.
- `..IntentModule` — `Intent`, `CollectIntents` and `CollectedIntentsOperation`,
  the answer to a request for everything that is available.
- `..SelectionModule` — `get_selection`, the selection of a target that comes
  with no selection of its own.
- `..DocumentModule` — `Document`, the type of the catch-all
  `read_gesture(::Document, …)` method.
