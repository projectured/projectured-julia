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
[api/Device.jl](../program/src/api/Device.jl). The only current backend is
SDL2.

## Devices

| Device | Defined in | Purpose |
|---|---|---|
| `Window` | `device/Window.jl` | Output surface — has title, width, height, background colour, and a backend-managed `handle` |
| `Keyboard` | `device/Keyboard.jl` | Input — emits `KeyPress(key::Symbol, ctrl::Bool)` |
| `Mouse` | `device/Mouse.jl` | Input — emits `MouseClick`, `MouseMove`, `MouseScroll` |

Each is a singleton-like struct (a `Window` carries config; `Keyboard` and
`Mouse` have no state of their own). The editor holds a `Vector{Device}`
that is passed to every backend call.

### Backend-agnostic events

Projection readers only see these events, never SDL-specific structs:

```julia
KeyPress(:left, false)          # arrow key, no Ctrl
KeyPress(:return, true)         # Ctrl-Enter
MouseClick(:left, 132, 47)      # left button at pixel (132, 47)
MouseMove(120, 90)              # cursor moved to (120, 90)
MouseScroll(0, 1, 200, 300)     # wheel scrolled (dx, dy) at (200, 300)
QuitEvent()                     # window close or Escape
```

This vocabulary is what insulates a `TextToGraphics.projection_read` (which
maps `:left`/`:right` to a `ReplaceSelectionOperation`) from any specific
backend.

## Backends

```julia
abstract type Backend end

init!(::Backend)                    # set up libraries, allocate caches
quit!(::Backend)                    # release everything
open_window!(::Backend, window)     # create the native window/renderer
close_window!(::Backend, window)    # destroy them
measure_text(::Backend, text, font) # (px_width, px_height)
read_from_devices(::Backend, devices)  # poll → backend-agnostic event
write_to_devices(::Backend, devices, document)  # render the canvas
```

`SdlBackend` (in [backend/Sdl.jl](../program/src/backend/Sdl.jl)) implements
all of the above with SDL2 + SDL_ttf. Highlights:

- A font measurement cache shared across all windows.
- `sdl_to_keypress` maps SDL keysyms + modifier bits to `KeyPress`.
- `sdl_to_mouse` maps SDL mouse events to the three `Mouse*` structs.
- `sdl_render_canvas` walks a `GraphicsCanvas` (and its nested
  `GraphicsViewport`/`GraphicsImage`/`GraphicsFence` children) and issues
  SDL draw calls.

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
3. Add the device to the `Vector{Device}` in `ApplicationModule.application`.
4. If it emits novel events, declare backend-agnostic event structs alongside
   the device so projection readers can match on them.

## Adding a new backend

1. Subtype `Backend` in `program/src/backend/`.
2. Implement `init!`, `quit!`, `open_window!`, `close_window!`,
   `measure_text`, `read_from_devices`, `write_to_devices`.
3. Translate native events into the existing backend-agnostic event types
   so projection code does not need to change.
4. Provide a `measure_text` callback for projections that need it.

The fact that every event projection-level is a `KeyPress`/`Mouse*`/`QuitEvent`
is the contract that keeps backends interchangeable.
