# SDL backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../kernel/devices-and-backends.md), [screen.md](../screen/screen.md), [style.md](../style/style.md)

`ProjecturedSdl` holds `SdlBackend`, which draws native windows with SDL2 and SDL_ttf, and the offscreen renderer behind `write_image` and `record_video`. `default_backend()` picks it first when it is loaded. This document says how it implements the interface of [devices-and-backends.md](../kernel/devices-and-backends.md), how its windows follow the screen document, and what its caches and its repaint do.

## How it works

### Windows follow the screen document

The backend has no call that opens or closes a window. `write_to_devices(backend, devices, screen::ScreenDocument)` compares the native windows with the `WindowDocument`s of the screen. It closes a window whose id is gone, opens one for a new id, and updates the title, the size and the position of the others. Then it paints the `content` of each, which must be a `GraphicsCanvas`. `windows` maps an id to its `SdlWindowResources`, and `window_ids` maps the SDL window number back to the id, so each event carries the id of its window. The resources keep the last values applied, so an unchanged title or size makes no SDL call. [screen.md](../screen/screen.md) describes the document side.

The editor calls `open_native_windows!` before the first print. It opens every window, waits up to 250 ms until the size that the window manager grants holds still for 20 ms, and writes that size into the `WindowDocument`. So the document is laid out once, at the real size, and not again when the answer of the window manager arrives as a resize.

### Measure and draw text

`measure_text(::SdlBackend, text, font)` measures with SDL_ttf at the device size and divides by `_DISPLAY_SCALE`, so the result is in logical pixels. It splits the text into runs by font: a character that the font lacks goes to the file that `find_glyph_font_file` of `ProjecturedStyle` names, which is the file that `measure_truetype_text` uses too. `measure_sdl_text(text, font)` is the same measure as a plain function. It is exported because a projection takes its measure by value, as in `TextToGraphics(measure = measure_sdl_text)`, and a generic can not go there.

Font handles are in a module cache keyed by file and size. A drawn text is a texture, and a second module cache keeps it by renderer, text, font, size and colour. Without it, a static document that scrolls rasterizes, uploads and destroys every span on every frame. The cache is emptied at 16384 entries, and the textures of a renderer go when the renderer is destroyed.

### Paint a window

Each graphics type has a painter, and a nested canvas recurses with the sum of the offsets. A window paints into an offscreen target that is `PROJECTURED_SUPERSAMPLE` times the device size, 2 by default, and the copy to the window scales it down, which smooths the edges.

With `partial_render = true`, the backend walks the canvas before it paints. It finds the smallest rectangle that covers every graphic whose cell is not up to date. It tests `is_cell_up_to_date` before it reads a value, because a read computes the value again. For each changed unit it adds the bounds that the unit had at the last paint, which `dirty_bounds` keeps by `objectid`, so a moved or removed element clears its old pixels. It repaints only that rectangle into the kept target, and a frame with no change paints nothing. The back buffer of the window was shown some frames ago, and the EGL or GLX buffer age says how many. So the copy to the window covers the damage rectangles of that many frames, and an unknown age copies all. `debug_dirty = true` draws the repainted rectangle in red.

`partial_render` defaults to the environment variable `PROJECTURED_PARTIAL_RENDER`, and that defaults to off. So `SdlBackend()` repaints the whole window on each frame unless the variable is set.

### Events in

`read_from_devices` polls SDL and returns one `WindowInput`:

| SDL event | Event |
| --- | --- |
| `SDL_KEYDOWN`, `SDL_KEYUP` | `KeyDown`, `KeyUp`, through `sdl_keysym_to_symbol` |
| `SDL_TEXTINPUT` | `KeyPress`, through `sdl_to_keypress` |
| mouse button down, up | `MouseDown`, `MouseUp` |
| mouse motion | `MouseMove`, coalesced |
| mouse wheel | `MouseScroll` |
| window close, window resize | `WindowClose`, `WindowResize` |
| `SDL_QUIT` | `WindowQuit` on the id `:none` |

Escape is an ordinary `KeyDown`. The backend makes no `MousePress`: the `GestureRecognizer` of the editor builds a click from a down and an up. A run of motion events gives only its newest sample. An event that ends the run waits in `pending_input` for the next call, so a click never comes before the motion that led to it. Motion with no button held gives at most one sample in 30 ms, and a held sample is kept, so the last position of a pointer that stops arrives. `pending_input` and `pending_motion` are fields of the backend, so two backends in one process never share an event.

### Wait and wake

`wait_for_input` blocks in `SDL_WaitEventTimeout` with a null event pointer, the form that removes nothing from the queue. It blocks in slices that let the garbage collector run: 10 ms with one thread, 100 ms with more. A `yield` between the slices gives the MCP server and the assistant on the same thread their turn. `wake_backend!` pushes a user event that `initialize_backend!` registered, through `SDL_PushEvent`, which SDL documents as safe from any thread. `read_from_devices` skips that event.

### Zoom

The editor recognises Ctrl+=, Ctrl+- and Ctrl+0 for the uniform zoom, and the same keys with Alt for the font zoom. This backend evaluates the two operations; [style.md](../style/style.md#two-zoom-settings) describes the two settings.

- `AdjustZoomOperation` changes `_DISPLAY_SCALE` and scales the logical size of each window the other way. The native window keeps its device size, and the content lays out again through the available size, as on a resize.
- `AdjustFontZoomOperation` writes `_FONT_ZOOM` and sets `editor.iomap` to `nothing`, so the editor prints again. The widgets measure while `print_document` runs and keep constant sizes, so only a new print fits them to the new text size.

Both repaint every window in full.

### Offscreen

`write_image(document, projection, filename; …)` renders with an SDL software renderer to BMP or PNG, with the same two-pass size to the content as `write_pdf`. `GraphicsCanvasToImageFile` is the form for the end of a chain. `_open_offscreen_renderer`, `_emit_frames!` and `_close_offscreen_renderer` are the primitive that `record_video` uses; see [video.md](../video/video.md). `decode_image` loads an image file with SDL2_image, and `get_display_size` reads the usable bounds of the display, or the primary monitor from `xrandr` when SDL reports several monitors as one display.

`quit_backend!` frees the textures and the fonts before `SDL_Quit`. On macOS it sets the activation policy of the process back to Accessory. The first video initialisation registers the process as a foreground application, and `SDL_Quit` does not undo that. Without the reset, macOS shows a busy dock icon after the last window closes.

## How it fits

`ProjecturedSdl` depends on `ProjecturedCollection`, `ProjecturedGraphics`, `ProjecturedScreen`, `ProjecturedStyle` and the kernel, and on `SimpleDirectMediaLayer` and `SDL2_jll`. A package with a third-party dependency is a stem that a user names, so `using Projectured` does not load it. `ProjecturedRepl` loads it, and `ProjecturedVideo` depends on it. The builder names it as the backend `sdl` of a binary, the default when a build holds both backends.

`default_backend()` in `example/projectured/DefaultBackend.jl` returns an `SdlBackend` when the package is loaded. It registers nothing.

## Design decisions

- **The generic is the surface.** A caller reaches the backend through the generics of `BackendModule`: `render_canvas`, `decode_image`, `get_display_size`. The helpers stay inside; `measure_sdl_text` is the one exported helper, because it goes by value.
- **The windows open before the first print.** A document laid out first is laid out at a size that the window never has. See `plan/done/native-window-size.md`.
- **The repaint follows the reactive graph.** The cells that a change invalidated say which graphics changed, so the backend compares no pixels. See `plan/done/optimize-rendering-dirty-rect.md`.
- **The damage history follows the buffer age.** A swap chain of two or three buffers would otherwise show an old edit on the buffer that was not repainted.
- **The two zooms take two routes.** The uniform zoom needs no new print; the font zoom prints again, because the widgets keep the sizes that they measured.
- **The input state is on the backend.** Two backends in one process have separate queues.

## Usage

```julia
run_editor!(SdlBackend(), projection, document)
backend = SdlBackend(; partial_render = true, debug_dirty = true)
write_image(document, projection, "snapshot.png")
projection = TextToGraphics(measure = measure_sdl_text)
```

- Examples: every gallery example runs on it by default. `example/sdl/LiveExamples.jl` plays a timeline in a window or records it with `record_video`. The screenshots under `asset/image/example/` come from `write_image`.
- Test: `test_sdl()` in `ProjecturedSdlTest` runs the layering guard, the dirty rectangle, the key symbols, the device configuration, the font fallback, the coalescing of input, the wait and the wake, the native windows, and `write_image`.

## Limits

- `render_canvas` returns an empty `GraphicsImage`: `render_sdl_canvas` draws nothing yet.
- The partial repaint is off by default.
- A change of the `style` of a window is recorded and not applied, because SDL can change only some window flags after the window exists.
