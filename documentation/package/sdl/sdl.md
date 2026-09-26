# SDL backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../kernel/devices-and-backends.md), [screen.md](../screen/screen.md), [style.md](../style/style.md)

`ProjecturedSdl` holds `SdlBackend`, which draws native windows with SDL2 and SDL_ttf, and the offscreen renderer behind `write_image` and `record_video`. `default_backend()` picks it first when it is loaded. This document says how it implements the interface of [devices-and-backends.md](../kernel/devices-and-backends.md), how its windows follow the screen document, and what its caches and its repaint do.

## How it works

### Windows follow the screen document

The backend has no call that opens or closes a window. `write_to_devices(backend, devices, screen::ScreenDocument)` compares the native windows with the `WindowDocument`s of the screen. It closes a window whose id is gone, opens one for a new id, and updates the title, the size and the position of the others. Then it paints the `content` of each, which must be a `GraphicsCanvas`. `windows` maps an id to its `SdlWindowResources`, and `window_ids` maps the SDL window number back to the id, so each event carries the id of its window. The resources keep the last values applied, so an unchanged title or size makes no SDL call. [screen.md](../screen/screen.md) describes the document side.

**A window that says a `maximum_size` fits what it holds.** Before it makes or resizes the native window, the reconciler reads the `w` and the `h` of the printed canvas, clamps them between the `minimum_size` and the `maximum_size` of the window, and writes them into the `WindowDocument`. It also keeps such a window inside the work area. A tooltip also goes beside the pointer rather than under it: a tooltip under the pointer covers the thing it is about, and the next move of the pointer closes it. A popup stays under the pointer, because the pointer goes into it to choose. A window whose maximum is `(0, 0)` keeps the size it asks for, and that includes the first window.

**A window that the reconciler opens is painted before it is shown.** It is made with `SDL_WINDOW_HIDDEN`, painted, and then shown. A window shown before its first frame holds an undefined back buffer, which the compositor draws black, so a tooltip flashed black and filled in after. The paint that follows the show covers the whole window, because a driver is free to drop a present made while the window is hidden. `open_native_windows!` still opens the first window shown, because a hidden window gets no answer from the window manager about its size.

**A popup never takes the focus.** A window of style `:popup` is made borderless, above the other windows, out of the taskbar, and with `SDL_WINDOW_POPUP_MENU`. On X11 the window manager then does not manage the window. A managed window gets the focus when it opens, and the window manager can take the focus back at once: on GNOME Shell a menu in a `:floating` window loses the focus in the same poll that gives it, and the loss of focus closes the menu. A `:tooltip` window is made with `SDL_WINDOW_TOOLTIP` for the same reason.

The editor calls `open_native_windows!` before the first print. It opens every window, waits up to 250 ms until the size that the window manager grants holds still for 20 ms, and writes that size into the `WindowDocument`. So the document is laid out once, at the real size, and not again when the answer of the window manager arrives as a resize.

**A window takes the place that the window manager gives it.** A window manager can put a window elsewhere than it asked to be, and a person can move it. At each frame the reconciler reads the place of each native window, and when the window is not where the backend last put it and the `WindowDocument` asks for no other place, it writes that place into the `x` and the `y` of the document. A popup opens at the screen origin of its window plus its own position, so it opens at the window and not where the window was first asked to be.

### Draw text

The backend draws a text where a [`FontFileMeasure`](../style/style.md) lays it out: `compute_placed_glyphs(text, font)` gives the file and the pen position of each glyph, and the backend draws each glyph at that position, in its own font file. It opens every font with `TTF_HINTING_LIGHT_SUBPIXEL`, light hinting that fits a glyph to the pixel rows only, so the ink keeps the width of the advance the layout gave it. A character that the font lacks draws from the file that `find_glyph_font_file` of `ProjecturedStyle` names.

On a cache miss, `_render_text_surface` rasterizes each glyph of the text and composes them into one surface, with the pen origin of each glyph on the device pixel nearest to its pen position; the baseline of the surface is the row where the tallest glyph's ascent lands. Font handles are in a module cache keyed by file and device size. The composed surface becomes a texture, kept in a second module cache by renderer, text, font, logical size, device size and colour, so a static document that scrolls does not rasterize, upload and destroy every span on every frame. `_render_element!` places that texture so that its baseline lands on `y` plus the ascent that `compute_text_extent` gives the text: the baseline the layout computed. The cache is emptied at 16384 entries, and the textures of a renderer go when the renderer is destroyed.

`_compute_text_texture_box` finds the rectangle the texture covers, from the geometry of each glyph with no render, and `_extend_drawn_bounds!` adds it to the dirty rectangle of a partial repaint and to the size of `write_image`: the texture can reach past the box of the text, left of `x` by a negative left bearing and above its top by a glyph that rises above the ascent of its font.

### Paint a window

Each graphics type has a painter, and a nested canvas recurses with the sum of the offsets. A window paints into an offscreen target that is `PROJECTURED_SUPERSAMPLE` times the device size, 2 by default, and the copy to the window scales it down, which smooths the edges.

With `partial_render = true`, the backend walks the canvas before it paints. It finds the smallest rectangle that covers every graphic that changed, and a graphic changes in one of three ways:

- **Its content changed.** A canvas whose element list, or a slot of it, is not up to date, a list node whose value or spine is not up to date, or a leaf whose own cell is not up to date. The walk tests `is_cell_up_to_date` before it reads a value, because a read computes the value again.
- **It moved, or it was resized.** The walk compares the origin of each canvas, and the box, the content and the transform of each viewport, by value with what the last paint used. Propagation is write-driven, so the origin of a paragraph below an edit is computed again from the heights above it, and it is stale whether or not a height changed. A paragraph at the same place does not repaint, and one that moved does.
- **It came into view, or it left it.** A graphic that the walk has no record of is painted. A graphic that was painted and now lies past the layout early-stop is not drawn, and its old place is cleared.

For each changed unit the walk adds the bounds that the unit had at the last paint, which `dirty_bounds` keeps, so a moved or removed element clears its old pixels. A unit is painted whole, so the walk also records the place and the bounds of everything inside it that the render reaches: the first change inside it then knows what it covered. A record is keyed by the placement of a graphic, its `objectid` mixed with the key of the container that holds it, because one graphic can be drawn at more than one place: the four regions of a frozen pane share their content. The walk passes the same origins and edges as the render, and a viewport gives both of them its content place from one function, `_get_viewport_content_place`. The records of graphics that are gone stay until a full paint. When there are twice as many as the last full paint recorded, and 10000 more, the backend forgets them and paints the whole window once. It repaints only the rectangle into the kept target, and a frame with no change paints nothing. The back buffer of the window was shown some frames ago, and the EGL or GLX buffer age says how many. So the copy to the window covers the damage rectangles of that many frames, and an unknown age copies all. `debug_dirty = true` draws the repainted rectangle in red.

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

- `AdjustZoomOperation` steps the `zoom` of the `Display` of the backend, and scales the logical size of each window the other way. The native window keeps its device size, and the content lays out again through the exact range that the window gives it, as on a resize.
- `AdjustFontZoomOperation` writes `_FONT_ZOOM` and sets `editor.iomap` to `nothing`, so the editor prints again. The widgets measure while `print_document` runs and keep constant sizes, so only a new print fits them to the new text size.

Both repaint every window in full.

### Offscreen

`write_image(document, projection, filename; …)` renders with an SDL software renderer to BMP or PNG, with the same two-pass size to the content as `write_pdf`. `GraphicsCanvasToImageFile` is the form for the end of a chain. `_open_offscreen_renderer`, `_emit_frames!` and `_close_offscreen_renderer` are the primitive that `record_video` uses; see [video.md](../video/video.md). `decode_image` loads an image file with SDL2_image, and `get_display_size` reads the usable bounds of the display, or the primary monitor from `xrandr` when SDL reports several monitors as one display.

`quit_backend!` frees the textures and the fonts before `SDL_Quit`. On macOS it sets the activation policy of the process back to Accessory. The first video initialisation registers the process as a foreground application, and `SDL_Quit` does not undo that. Without the reset, macOS shows a busy dock icon after the last window closes.

## How it fits

`ProjecturedSdl` depends on `ProjecturedCollection`, `ProjecturedGraphics`, `ProjecturedScreen`, `ProjecturedStyle` and the kernel, and on `SimpleDirectMediaLayer` and `SDL2_jll`. A package with a third-party dependency is a stem that a user names, so `using Projectured` does not load it. `ProjecturedRepl` loads it, and `ProjecturedVideo` depends on it. The builder names it as the backend `sdl` of a binary, the default when a build holds both backends.

`default_backend()` in `example/projectured/DefaultBackend.jl` returns an `SdlBackend` when the package is loaded. It registers nothing.

## Design decisions

- **The generic is the surface.** A caller reaches the backend through the generics of `BackendModule`: `render_canvas`, `decode_image`, `get_display_size`. The layout never asks the backend to measure text; it asks a `TextMeasure`.
- **The windows open before the first print.** A document laid out first is laid out at a size that the window never has. See [plan/done/native-window-size.md](../../../plan/done/native-window-size.md).
- **The repaint follows the reactive graph.** The cells that a change invalidated say which graphics changed, so the backend compares no pixels. See [plan/done/optimize-rendering-dirty-rect.md](../../../plan/done/optimize-rendering-dirty-rect.md).
- **The damage history follows the buffer age.** A swap chain of two or three buffers would otherwise show an old edit on the buffer that was not repainted.
- **The two zooms take two routes.** The uniform zoom needs no new print; the font zoom prints again, because the widgets keep the sizes that they measured.
- **The state of an editor is on its backend.** The pending input, the time of the rate limit of idle motion, the switches `partial_render` and `debug_dirty`, and the `Display` are fields of the backend, so two backends in one process keep them apart. The SDL session is still one for each process: one event queue, and one set of open fonts.

## Usage

```julia
run_editor!(SdlBackend(), projection, document)
backend = SdlBackend(; partial_render = true, debug_dirty = true)
write_image(document, projection, "snapshot.png")
projection = TextToGraphics(measure = FontFileMeasure())
```

- Examples: every gallery example runs on it by default. `example/sdl/LiveExamples.jl` plays a timeline in a window or records it with `record_video`. The screenshots under `asset/image/example/` come from `write_image`.
- Test: `test_sdl()` in `ProjecturedSdlTest` runs the layering guard, the dirty rectangle, the key symbols, the device configuration, the agreement of the font metrics with SDL_ttf (`test_sdl_font_metrics_agree`), the baseline of the drawn ink and the pen positions of each glyph (`test_sdl_text_baseline_ink`, `test_sdl_text_pen_positions`), the coalescing of input, the wait and the wake, the native windows, and `write_image`.

## Limits

- `render_canvas` returns an empty `GraphicsImage`: `render_sdl_canvas` draws nothing yet.
- The partial repaint is off by default.
- A change of the `style` of a window is recorded and not applied, because SDL can change only some window flags after the window exists.
