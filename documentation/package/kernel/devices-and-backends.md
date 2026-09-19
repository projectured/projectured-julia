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
[device/Device.jl](../../../source/kernel/device/Device.jl). There are three backends: the
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
| `Screen` | `device/Screen.jl` | Output surface — native windows are reconciled on demand against the projection-output `ScreenDocument` |
| `Keyboard` | `device/Keyboard.jl` | Input — polled for `KeyPress(char::Char)` (character input) and `KeyDown(key::Symbol, modifiers::ModifierKeys)` (navigation) events, defined in `event/KeyboardEvent.jl` |
| `Mouse` | `device/Mouse.jl` | Input — polled for `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll` events, defined in `event/MouseEvent.jl` |

Each is a stateless singleton struct. The editor holds a `Vector{Device}`
that is passed to every backend call.

### Backend-agnostic events

Projection readers only see these events, never SDL-specific structs:

```julia
KeyPress('a')                          # character input
KeyDown(:left, ModifierKeys())            # arrow key, no modifiers
KeyDown(:return, ModifierKeys(ctrl=true)) # Ctrl-Enter
MousePress(:left, 132, 47)             # left button at pixel (132, 47)
MouseMove(120, 90)                     # cursor moved to (120, 90)
MouseScroll(0, 1, 200, 300)            # wheel scrolled (dx, dy) at (200, 300)
WindowQuit()                            # the window was closed
```

This vocabulary is what insulates a `TextToGraphics.read_intent` (which
maps the `:left`/`:right` `KeyDown` keys to a `ReplaceSelectionOperation`) from
any specific backend.

Escape is an ordinary `KeyDown(:escape, …)`, not a quit. A backend reports what
happened and attaches no meaning, so it must not turn one key into a quit before
any reader has seen it. A dialog, an insertion and the command palette all bind
Escape, and a quit the backend issues directly leaves no reader able to stop it.
The editor loop quits on an unmodified
Escape that the pipeline did not handle, in the same place it recognises the
readability zoom (`read!` in [editor/EditorModule.jl](../../../source/kernel/editor/EditorModule.jl)).

## Backends

```julia
abstract type Backend end

# Backend interface (backend/BackendInterface.jl) — all dispatched on the concrete backend
initialize_backend!(::Backend)                    # set up libraries, allocate caches
quit_backend!(::Backend)                    # release everything
measure_text(::Backend, text, font) # (px_width, px_height)
read_from_devices(::Backend, devices)           # poll → WindowInput
write_to_devices(::Backend, devices, document)  # render the output
wait_for_input(::Backend, devices, timeout_seconds)  # block until input, a wake, or the timeout
wake_backend!(::Backend)                        # end a wait, from any task or thread
```

The wait is where the editor sleeps between frames, and the wake is how a
producer on another task ends the sleep. The defaults in
`BackendDefaults.jl` are one 10 ms poll slice and a no-op, so a backend that
answers neither behaves exactly as the loop did when it slept.

There is no `open_window!`/`close_window!`: native windows are reconciled on
demand inside `write_to_devices` whenever it sees a new `ScreenDocument` output.

There are three backends: `SdlBackend` (native graphics), `ConsoleBackend`
(terminal), and `WebBackend` (browser, over HTTP + WebSocket).

### SdlBackend

`SdlBackend` (in [package/ProjecturedSdl/src/ProjecturedSdl.jl](../../../package/ProjecturedSdl/src/ProjecturedSdl.jl)) implements
all of the above with SDL2 + SDL_ttf. Highlights:

- A font measurement cache shared across all windows.
- `sdl_to_keypress` maps SDL keysyms + modifier bits to `KeyPress`/`KeyDown`.
- Mouse events are mapped inline in `read_from_devices` (there is no
  `sdl_to_mouse` function) to the `Mouse*` structs.
- `render_sdl_canvas` walks a `GraphicsCanvas` (and its nested
  `GraphicsViewport`/`GraphicsImage`/`GraphicsFence` children) and issues
  SDL draw calls.
- `wait_for_input` blocks in `SDL_WaitEventTimeout` with a NULL event
  pointer — SDL's look-only form, so everything stays queued for `read!` —
  in GC-safe slices with a `yield` between them. `wake_backend!` pushes a
  user event registered at `initialize_backend!`; `SDL_PushEvent` is SDL's
  documented thread-safe entry, and `_poll_window_input` skips the event
  like any other unknown type.

### ConsoleBackend

`ConsoleBackend` (in [source/console/Console.jl](../../../source/console/Console.jl))
renders the **Text domain** straight to a terminal. Crucially it consumes a
`TextBlock` directly and skips `TextToGraphics`: its pipeline is
`JsonToSyntax → SyntaxToText` (no graphics step), so `write_to_devices` receives
a `TextBlock` rather than a `ScreenDocument`. Highlights:

- `write_to_devices` flattens the spans to a character stream, preserving each
  span's `font_color`/`fill_color` as 24-bit ANSI SGR codes (set `ansi=false`
  for plain output). The selection is shown as inverse-video span colors baked
  in by the `SelectionInverting` projection at the end of the console pipeline,
  so the backend itself just emits each span's colors.
- `read_from_devices` polls `backend.input` (default `stdin`) non-blockingly and
  translates terminal bytes — printable chars, `ESC[` arrow/Home/End/Delete
  sequences, Enter/Backspace/Tab, Ctrl-Space, Ctrl-C — into the same
  `KeyDown`/`KeyPress`/`WindowQuit` vocabulary the readers already use, wrapped in
  an `WindowInput(:console, …)`. `initialize_backend!`/`quit_backend!` toggle the terminal's raw mode.
- `wait_for_input` waits on an autoreset gate a watcher task notifies: the
  watcher blocks on the TTY through libuv (`Base.wait_readnb`), a `Timer`
  bounds the wait, and `wake_backend!` notifies the gate directly. An
  `IOBuffer` input has no watcher and degrades to the default poll slice.
- Because the console has no screen/window layer, the pipeline supplies its own
  window-input-unwrapping seam — `WindowInputUnwrappingProjection`
  ([projection/higherorder/WindowInputUnwrapping.jl](../../../source/projection/higherorder/WindowInputUnwrapping.jl))
  — that strips the `WindowInput` off the gesture before the readers run. (In
  the SDL pipeline `ScreenToScreen` does this.)
- **Limitation:** character-level text editing (cursor left/right, insertion,
  backspace/delete) lives in `TextToGraphics` and is therefore unavailable;
  the console drives the geometry-free subset — structural tree navigation
  (`Home` + arrows) and the `Ctrl+Space` mode toggle.

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
 browser tab/popup (canvas) ─events─▶  WebSocket  ──▶  read_from_devices
        ▲                                                      │
        └──── draw-list (full / patch) ◀── write_to_devices ◀──┘
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

A browser opens a window only inside a transient user activation, and a window
the editor opens on a hover — a tooltip — has none. **The client solves that and
does not fold the window into the page**: on the first interaction in the tab it
opens one window and holds it empty, and gives it to the next window that arrives
without an activation. A gesture refills the reserve. A window is a window here
as it is on SDL, which is
[PAR-MANY-WINDOWS](../../rule/architecture-invariants.md#par-many-windows). Selecting the web backend is just passing
`backend=WebBackend(...)` to `run_example`, which otherwise takes the same
arguments; `WebBackend`'s constructor defaults `host`/`port`.

#### How it satisfies the interface

- **`measure_text` stays on the server.** The layout pipeline calls
  `measure_text` synchronously *while printing*, long before any primitive
  reaches the browser, so the server must measure glyphs the same way the browser
  renders them. `initialize_backend!` runs `SDL_Init` + `TTF_Init` (no window) and reuses
  `measure_sdl_text`; the same TTFs are served to the browser (`/font/<name>`,
  loaded via the `FontFace` API) so metrics line up. The browser handles HiDPI
  with `devicePixelRatio`, so the server stays in logical pixels.
- **`write_to_devices`** serializes the projection-output `ScreenDocument` into a
  per-window draw-list mirroring the SDL element set (`text`, `rect`, `line`,
  `circle`, `clip`=viewport, `group`=nested canvas, `image`; `GraphicsFence`
  skipped) and pushes it over the socket.
- **`read_from_devices`** is non-blocking: a receive task decodes the client's
  JSON events into the backend-agnostic vocabulary (`MouseDown`, `KeyPress`, …)
  wrapped in `WindowInput`s on a `Channel`; the editor drains it each frame.
  MousePress synthesis and motion-while-held filtering mirror the SDL backend.

#### Wire protocol (JSON, both directions)

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

Key mapping is done **on the server** (`convert_web_key_to_symbol`, mirroring
`sdl_keysym_to_symbol`) so the `:left`/`:char`/… vocabulary has a single source
of truth.

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

The backends above (`SdlBackend`, `ConsoleBackend`, `WebBackend`) are
*interactive* — they drive live output and input devices. Output-only file
export lives alongside the backend layer but does **not** subtype
`Backend` — there are no devices or events, just a `GraphicsCanvas` turned into a
file:

- **`write_image`** ([package/ProjecturedSdl/src/ProjecturedSdl.jl](../../../package/ProjecturedSdl/src/ProjecturedSdl.jl)) rasterizes a
  canvas through an offscreen SDL software renderer to BMP/PNG.
- **`write_pdf`** ([source/pdf/Pdf.jl](../../../source/pdf/Pdf.jl)) walks the same
  canvas and emits a **vector** PDF (paths + selectable text, embedded TrueType
  fonts, optional multi-page pagination). It is entirely SDL-free — it measures
  text from the embedded font metrics via `pdf_measure_text`, a drop-in for
  `measure_sdl_text`.
- **`record_video`** ([package/ProjecturedVideo/src/ProjecturedVideo.jl](../../../package/ProjecturedVideo/src/ProjecturedVideo.jl))
  renders a timed sequence of gestures or operations to an `.mp4` file, with no
  window: it rasterizes each frame through the same offscreen SDL renderer as
  `write_image`, then encodes the frames with `ffmpeg` (via `FFMPEG.jl`). It
  is a separate opt-in package because it is the only one that pulls in FFMPEG.

See [the graphics guide](../graphics/graphics.md) for the image and PDF APIs.

## Projections that need the backend

Some projections need to *measure* text to lay it out (`TextToGraphics`
and `WidgetToGraphics` both word-wrap based on glyph widths). They accept a
`measure::Function` argument so they stay backend-agnostic:

```julia
TextToGraphics(measure = (text, font) -> measure_sdl_text(backend, text, font))
```

Inject the backend's measurer when building the pipeline; the projection
itself never sees the backend type.

## Adding a new device

1. Subtype `Device` in `source/kernel/device/`.
2. Add backend methods: `read_from_device(::SdlBackend, ::YourDevice)` and
   if relevant `write_to_device(::SdlBackend, ::YourDevice, document)`.
3. Add the device to the `Vector{Device}` built by the `run_editor!(backend, projection,
   document)` bootstrap in `editor/EditorModule.jl` (`Device[Display(), Keyboard(), Mouse()]`).
4. If it emits novel events, declare backend-agnostic event structs in
   `source/kernel/event/` so projection readers can match on them.

## Adding a new backend

1. Subtype `Backend` (defined in `source/kernel/backend/`) in your backend package.
2. Implement the `Backend` interface (`initialize_backend!`, `quit_backend!`,
   `measure_text`, `read_from_devices`, `write_to_devices`).
3. Translate native events into the existing backend-agnostic event types
   so projection code does not need to change.
4. Provide a `measure_text` callback for projections that need it.

The fact that every event at the projection level is a `KeyPress`/`KeyDown`/`Mouse*`/`WindowQuit`
is the contract that keeps backends interchangeable.

---

# Internals

The remainder of this guide documents the kernel-internal module structure
behind the two abstractions: **devices** — the input event vocabulary, the
device types, and gesture recognition, spread across three layers (`event/`,
`device/`, `gesture/`) — and the **backend layer**. They are independent
siblings: the event/device/gesture layers name no backend type, and the two
abstractions only come together in a concrete implementation. Gesture
*bindings*, where a gesture acquires meaning against a document, are a
separate, much higher layer (`binding/`); see
[below](#gesture-bindings-a-separate-higher-layer).

## The event layer (layer 4)

Layer 4 of the kernel — **input events and the pattern language**. The layer
depends on nothing: an event is data, and carries no reference to the device
that produced it, nor to the document it will end up changing.

The layer lives in [source/kernel/event/](../../../source/kernel/event/):

```
EventModule.jl   (EventModule)        — the input event vocabulary, seven fragments:
        ├─ EventInterface.jl  — the Event/DeviceEvent/SyntheticEvent types and
        │                       the get_modifier_keys generic every event answers
        ├─ ModifierKeys.jl       — the Ctrl/Shift/Alt/Meta struct
        ├─ KeyboardEvent.jl   — KeyDown, KeyUp, KeyPress, KeyChord
        ├─ MouseEvent.jl      — MouseDown, MouseUp, MousePress, MouseMove,
        │                       MouseEnter, MouseLeave, MouseScroll
        ├─ WindowEvent.jl     — WindowQuit, WindowClose, WindowResize, WindowDefocus
        ├─ WindowInput.jl   — an event plus the id of the window it came from
        └─ EventDefaults.jl   — the get_modifier_keys fallback and the four
                                has_*_modifier_key predicates derived over it
EventPatternModule.jl  (EventPatternModule) — the event pattern language: the reified
                                        EventPattern, matches/describe, the
                                        @event_case macro, and the parser API
                                        @gestures is built on
```

### EventModule

Every concrete event subtypes either `DeviceEvent` (what a device reports —
`KeyDown`, `MouseDown`, `WindowClose`, …) or `SyntheticEvent` (derived from
several device events by whoever holds the state spanning them — `MousePress`
from a down/up pair, `KeyChord` from a key sequence, `MouseEnter`/`MouseLeave`
from motion crossing a boundary); both are `Event`s. `get_modifier_keys` (and
`has_ctrl_modifier_key`/`has_shift_modifier_key`/`has_alt_modifier_key`/`has_meta_modifier_key` on top of it) is defined once over
`Event`, so it works for mouse events as well as keyboard ones.
`WindowClose`, `WindowResize`, and `WindowDefocus` live here, not with the
concrete `ScreenDocument` in `visual` — a window event is report-only input
vocabulary, not a document type; the window *document* and its operations
(`OpenWindowOperation`, `CloseWindowOperation`, …) stay in `source/screen/`.

### EventPatternModule

One surface syntax for saying "this kind of event, with these field values
and these modifiers held", ridden by two consumers: an
[`EventPattern`](../../../source/kernel/event/EventPatternModule.jl) is
*data* answering `matches(pattern, event)` and `describe(pattern)` — the
per-event constructors (`KeyDownPattern`, `MousePressPattern`, …) name the
type and its most-constrained field, all producing the one generic
`EventPattern{E<:Event}` struct; [`@event_case`](../../../source/kernel/event/EventPatternModule.jl)
compiles a table of `pattern => result` rules straight to `isa`/field tests,
first match wins. Both ride on one parser — exported as a macro-authoring API
(`parse_event_rule`, `event_pattern_expr`, `event_field_bindings`) — so the
`@gestures` DSL in the binding layer reuses the surface syntax instead of
reimplementing it. The field table each pattern may bind is *derived* from
`EventModule`'s own exports, so a new event type is matchable the moment it
is exported, with no entry to add here.

### WindowInput

`WindowInput` wraps every event with the id of the window it came from. It
lives in `EventModule`, not in the concrete `ScreenModule` document,
because it is a protocol type consumed by the editor loop, the gesture
recognizer, and the window-input-unwrapping projection — a plain struct
declaration for a protocol type does not belong inside a concrete
document; keeping it here means the kernel has no edge onto `ScreenDocument`.

(This is the canonical statement of the `WindowInput`-placement rationale;
other package docs defer here rather than repeat it.)

## The device layer (layer 5)

Layer 5 of the kernel — **the input/output devices**: `Display`, `Keyboard`,
and `Mouse` under an abstract `Device`. Each carries its physical properties —
a screen's resolution and HiDPI scale, a mouse's button count and scroll wheel,
a keyboard's layout — but interprets nothing, so this layer names no document,
no operation, and no backend type, and has no imports of its own.

The layer lives in [source/kernel/device/](../../../source/kernel/device/):

```
DeviceModule.jl (DeviceModule) — the module: its docstring, exports, and fragments
        ├─ Device.jl    — the Device abstract supertype
        ├─ Keyboard.jl  — the Keyboard device
        ├─ Mouse.jl     — the Mouse device
        └─ Display.jl   — the Display device
```

The devices carry their physical properties but no behaviour. The batch I/O
that drives them — `read_from_devices` / `write_to_devices` — is declared one
layer up in the backend interface (see [Backends](#backends)) and dispatched on
the concrete backend, which also fills in the physical properties at start-up
via `configure_devices!`. That keeps the device and backend abstractions
independent siblings, bound only by a concrete implementation.

## The gesture layer (layer 6)

Layer 6 of the kernel — **recognising gestures in the event stream**:
combinations and sequences that only exist across several events (a click, a
multi-click, a key chord) become one synthesised event. Recognition is an
endofunction on the event stream — events in, events out — so this layer
names no document and no operation; what a gesture *means* is decided by
whoever binds it, in the `binding/` layer far above.

The layer lives in [source/kernel/gesture/](../../../source/kernel/gesture/) as
one module:

```
GestureRecognizerModule.jl (GestureRecognizerModule) — MousePress + KeyChord synthesis
```

`GestureRecognizer` is a stateful event → gesture recogniser:
`recognize_gesture!` consumes one `WindowInput`, updating click/multi-click
and chord-buffer state, and either returns the window input to forward, enqueues
a synthesised one (a completed click), or absorbs the event (a chord prefix,
still incomplete); `pop_gesture!` is the consumer-facing pull, draining any
pending synthesised gestures ahead of new raw input. A gesture is *only* a
combination of events — it carries no intent. Its only import is
`EventModule`.

## The backend layer (layer 7)

Layer 7 of the kernel — **rendering targets**. The layer carries the abstract
`Backend` type and the backend generics; the concrete backends live in opt-in
packages, and the dependency-free `HeadlessBackend` test double lives in
`ProjecturedKernelExample` (PAR-NO-TEST-DOUBLES-IN-MAIN keeps doubles out of `main`).

The layer lives in [source/kernel/backend/](../../../source/kernel/backend/):

```
BackendModule.jl    (BackendModule)         — the module: its docstring, exports, and fragments
BackendInterface.jl (BackendModule)         — Backend abstract + batch generics
BackendDefaults.jl  (BackendModule)         — the fallback behaviours the contract supplies itself
```

### BackendModule

Declares `Backend <: Any` and the backend generics `initialize_backend!`,
`quit_backend!`, `measure_text`, `read_from_devices`, `write_to_devices`,
`get_display_size`, `configure_devices!`, `open_native_windows!`, `write_image`,
`record_video`, `render_canvas`, `decode_image`, `get_pointer_position`. Concrete backends
(SDL, Web, Console, Headless, …) live in opt-in packages that subtype `Backend`
and add methods for their own `::MyBackend` type. A backend is constructed by
naming its type directly (`SdlBackend()`, `ConsoleBackend()`). Code that must
pick a backend without depending on its package uses
[`ProjecturedExample.default_backend`](../../../example/projectured/DefaultBackend.jl),
which matches a caller-supplied ordered list of type names (`:SdlBackend`, …)
against the loaded `Backend` subtypes by reflection — no coined `:kind` key and
no per-backend registration.

`BackendInterface.jl` is an **interface file** (PAR-INTERFACE-DECLARES-ONLY): it declares and never implements,
so every generic there is a bodiless `function f end`. The fallback behaviours
the contract supplies for itself sit beside it in `BackendDefaults.jl`, for the
capabilities a backend may not support: `get_pointer_position` answers `(-1, -1)`,
`get_display_size` answers `(1280, 800)`, `configure_devices!` is a no-op that
leaves the devices at their default properties, and `open_native_windows!` is a
no-op for a backend that has no native windows to open — each a legal answer
rather than a missing implementation. The batch generics deliberately have no
such fallback: an unimplemented `measure_text` or `write_image` must raise a
`MethodError` rather than fabricate a result.

No document is imported here. The batch I/O generics are duck-typed on the
`document` argument, so the layer stays document-free.

### The HeadlessBackend test double

The dependency-free in-memory `HeadlessBackend` — which logs every
`write_to_devices` document into `rendered` and pops scripted events on each
`read_from_devices` (`push_event!` enqueues them; `measure_text` returns a fixed
`(8 * length, 16)`) — is a **test double** for the `Backend` seam. By
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
`MousePress` does to a `JsonArray` needs `Document` and `Operation`. That
pulls gesture bindings up to layer 12 — `binding/` — above `document/`,
`reference/`, `selection/`, and `operation/`, rather than beside the
event/device/gesture layers above.

The layer lives in [source/kernel/binding/](../../../source/kernel/binding/):

```
GestureBindingModule.jl (GestureBindingModule)   — the aggregator
        ├─ GestureBinding.jl — GestureBinding, the per-document-type
        │                      registry, read_gesture / read_bound_gesture
        └─ Gestures.jl — the @gestures / @gesture_set authoring DSL
```

A `GestureBinding` is reified *data*: an `EventPattern` (what fires it, and
how it is described) + `operation(document, event) -> Operation | Nothing` +
an `applicable(document, selection) -> Bool` precondition + a human
`description` + a `domain` tag + an optional `name` — the same declaration both
fires the edit and can be listed to a user. [`@gestures`](../../../source/kernel/binding/Gestures.jl)
emits the `get_document_gesture_bindings_own` method holding a type's own
table; `get_document_gesture_bindings` walks it plus every supertype's.
`fire_gesture_bindings(bindings, target, selection, event)` is the one firing
loop — the first binding whose pattern matches, whose precondition holds, and
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
its `name` does, through `fire_named_gesture_binding(bindings, target, selection,
name)` — the counterpart that selects a binding by the name a user types instead
of by the event that fires it, and passes `nothing` for the event.

Write it in the pattern slot of the rule form that already exists:

```julia
@gestures JsonObject begin
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc, :key, :value)
    nothing       => "Move from value to key" => move_to_field(doc, :value, :key)
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
The command palette in the domain package lists these by name; see
[the gesturemap slice](../../../source/gesturehelp/CommandPalette.jl).

### Downward edges

- `..EventModule`, `..EventPatternModule` — the pattern a binding matches on.
- `..DocumentModule: Document` — the catch-all `read_gesture(::Document, …)`
  method.
