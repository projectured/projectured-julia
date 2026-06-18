# Devices and Backends

ProjecturEd separates the **what** of I/O (a `Device`) from the **how**
(a `Backend`). A `Device` describes a logical input or output channel; a
`Backend` provides the platform-specific machinery to drive it. This split
makes it possible to add a new backend (terminal, web, JetBrains plugin, …)
without rewriting projection code, and to add a new device (e.g. a touch
panel) without modifying existing backends beyond the device's own
dispatch.

The abstract interfaces live in
[api/Backend.jl](../program/src/api/Backend.jl) and
[api/Device.jl](../program/src/api/Device.jl). There are two backends today: the
SDL2 graphics backend and a terminal `ConsoleBackend` (see below).

## Devices

| Device | Defined in | Purpose |
|---|---|---|
| `Screen` | `device/Screen.jl` | Output surface — native windows are reconciled on demand against the projection-output `ScreenDocument` |
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
QuitEvent()                            # window close or Escape
```

This vocabulary is what insulates a `TextToGraphics.projection_read` (which
maps the `:left`/`:right` `KeyDown` keys to a `ReplaceSelectionOperation`) from
any specific backend.

## Backends

```julia
abstract type Backend end

# Backend interface (api/Backend.jl)
init!(::Backend)                    # set up libraries, allocate caches
quit!(::Backend)                    # release everything
measure_text(::Backend, text, font) # (px_width, px_height)

# Device I/O interface (api/Device.jl) — driven by the backend
read_from_devices(::Backend, devices)           # poll → EventEnvelope
write_to_devices(::Backend, devices, document)  # render the output
```

There is no `open_window!`/`close_window!`: native windows are reconciled on
demand inside `write_to_devices` whenever it sees a new `ScreenDocument` output.

There are two backends: `SdlBackend` (graphics) and `ConsoleBackend` (terminal).

### SdlBackend

`SdlBackend` (in [backend/Sdl.jl](../program/src/backend/Sdl.jl)) implements
all of the above with SDL2 + SDL_ttf. Highlights:

- A font measurement cache shared across all windows.
- `sdl_to_keypress` maps SDL keysyms + modifier bits to `KeyPress`/`KeyDown`.
- Mouse events are mapped inline in `read_from_devices` (there is no
  `sdl_to_mouse` function) to the `Mouse*` structs.
- `sdl_render_canvas` walks a `GraphicsCanvas` (and its nested
  `GraphicsViewport`/`GraphicsImage`/`GraphicsFence` children) and issues
  SDL draw calls.

### ConsoleBackend

`ConsoleBackend` (in [backend/Console.jl](../program/src/backend/Console.jl))
renders the **Text domain** straight to a terminal. Crucially it consumes a
`TextText` directly and skips `TextToGraphics`: its pipeline is
`JsonToSyntax → SyntaxToText` (no graphics step), so `write_to_devices` receives
a `TextText` rather than a `ScreenDocument`. Highlights:

- `write_to_devices` flattens the spans to a character stream, preserving each
  span's `font_color`/`fill_color` as 24-bit ANSI SGR codes (set `ansi=false`
  for plain output). The selection is reverse-video highlighted.
- `read_from_devices` polls `backend.input` (default `stdin`) non-blockingly and
  translates terminal bytes — printable chars, `ESC[` arrow/Home/End/Delete
  sequences, Enter/Backspace/Tab, Ctrl-Space, Ctrl-C — into the same
  `KeyDown`/`KeyPress`/`QuitEvent` vocabulary the readers already use, wrapped in
  an `EventEnvelope(:console, …)`. `init!`/`quit!` toggle the terminal's raw mode.
- Because the console has no screen/window layer, the pipeline supplies its own
  envelope-unwrapping seam — `EnvelopeUnwrappingProjection`
  ([projection/higherorder/EnvelopeUnwrapping.jl](../program/src/projection/higherorder/EnvelopeUnwrapping.jl))
  — that strips the `EventEnvelope` off the gesture before the readers run. (In
  the SDL pipeline `ScreenToScreen` does this.)
- **Limitation:** character-level text editing (cursor left/right, insertion,
  backspace/delete) lives in `TextToGraphics` and is therefore unavailable;
  the console drives the geometry-free subset — structural tree navigation
  (`Home` + arrows) and the `Ctrl+Space` mode toggle.

Run it with `run_console_example()` (one-shot) or
`run_console_example(interactive=true)` (read-eval-print loop).

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

1. Subtype `Device` in `program/src/device/`.
2. Add backend methods: `read_from_device(::SdlBackend, ::YourDevice)` and
   if relevant `write_to_device(::SdlBackend, ::YourDevice, document)`.
3. Add the device to the `Vector{Device}` built by the `run!(backend, projection,
   document)` bootstrap in `editor/Editor.jl` (`Device[Screen(), Keyboard(), Mouse()]`).
4. If it emits novel events, declare backend-agnostic event structs alongside
   the device so projection readers can match on them.

## Adding a new backend

1. Subtype `Backend` in `program/src/backend/`.
2. Implement the `Backend` interface (`init!`, `quit!`, `measure_text`) and the
   `Device` I/O functions (`read_from_devices`, `write_to_devices`).
3. Translate native events into the existing backend-agnostic event types
   so projection code does not need to change.
4. Provide a `measure_text` callback for projections that need it.

The fact that every event projection-level is a `KeyPress`/`KeyDown`/`Mouse*`/`QuitEvent`
is the contract that keeps backends interchangeable.
