# SDL backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [screen.md](../../platform/screen/screen.md), [style.md](../../platform/style/style.md)

`ProjecturedSDL` holds `SdlBackend`, which draws native windows with SDL2 and SDL_ttf, and the offscreen renderer behind `write_image` and `record_video`. `default_backend()` picks it first when it is loaded. This document says how it implements the interface of [devices-and-backends.md](../../kernel/devices-and-backends.md), how its windows follow the screen document, and what its caches and its repaint do.

## How it works

### Windows follow the screen document

The backend has no call that opens or closes a window. `write_to_devices!(backend, devices, screen::ScreenDocument)` compares the native windows with the `WindowDocument`s of the screen. It closes a window whose id is gone, opens one for a new id, and updates the title, the size and the position of the others. Then it paints the `content` of each, which must be a `GraphicsCanvas`. `windows` maps an id to its `SdlWindowResources`, and `window_ids` maps the SDL window number back to the id, so each event carries the id of its window. The resources keep the last values applied, so an unchanged title or size makes no SDL call. [screen.md](../../platform/screen/screen.md) describes the document side.

**A window that says a `maximum_size` fits what it holds.** Before it makes or resizes the native window, the reconciler reads the `w` and the `h` of the printed canvas, clamps them between the `minimum_size` and the `maximum_size` of the window, and writes them into the `WindowDocument`. It also keeps such a window inside the work area, which is the size that the `Display` of the backend holds: `initialize_backend!` and `configure_devices!` read it, and an SDL display event reads it again, so a frame asks SDL nothing. A tooltip also goes beside the pointer rather than under it: a tooltip under the pointer covers the thing it is about, and the next move of the pointer closes it. A popup stays under the pointer, because the pointer goes into it to choose. A window whose maximum is `(0, 0)` keeps the size it asks for, and that includes the first window.

**A window that the reconciler opens is painted before it is shown.** It is made with `SDL_WINDOW_HIDDEN`, painted, and then shown. A window shown before its first frame holds an undefined back buffer, which the compositor draws black, so a tooltip flashed black and filled in after. The paint that follows the show covers the whole window, because a driver is free to drop a present made while the window is hidden. `open_native_windows!` still opens the first window shown, because a hidden window gets no answer from the window manager about its size.

**A popup never takes the focus.** A window of style `:popup` is made borderless, above the other windows, out of the taskbar, and with `SDL_WINDOW_POPUP_MENU`. On X11 the window manager then does not manage the window. A managed window gets the focus when it opens, and the window manager can take the focus back at once: on GNOME Shell a menu in a `:floating` window loses the focus in the same poll that gives it, and the loss of focus closes the menu. A `:tooltip` window is made with `SDL_WINDOW_TOOLTIP` for the same reason.

The editor calls `open_native_windows!` before the first print. It opens every window, waits up to 250 ms until the size that the window manager grants holds still for 20 ms, and writes that size into the `WindowDocument`. So the document is laid out once, at the real size, and not again when the answer of the window manager arrives as a resize.

**A window takes the place that the window manager gives it.** A window manager can put a window elsewhere than it asked to be, and a person can move it. At each frame the reconciler reads the place of each native window, and when the window is not where the backend last put it and the `WindowDocument` asks for no other place, it writes that place into the `x` and the `y` of the document. A popup opens at the screen origin of its window plus its own position, so it opens at the window and not where the window was first asked to be.

### Draw text

The backend draws a text where a [`FontFileMeasure`](../../platform/style/style.md) lays it out: `compute_placed_glyphs(text, font)` gives the file and the pen position of each glyph, and the backend draws each glyph at that position, in its own font file. It opens every font with `TTF_HINTING_LIGHT_SUBPIXEL`, light hinting that fits a glyph to the pixel rows only, so the ink keeps the width of the advance the layout gave it. A character that the font lacks draws from the file that `find_glyph_font_file` of the style slice names.

On a cache miss, `_render_text_surface` rasterizes each glyph of the text and composes them into one surface, with the pen origin of each glyph on the device pixel nearest to its pen position; the baseline of the surface is the row where the tallest glyph's ascent lands. Font handles are in a module cache keyed by file and device size. The composed surface becomes a texture, kept in a second module cache by renderer, text, font, logical size, device size and colour, so a static document that scrolls does not rasterize, upload and destroy every span on every frame. `_render_element!` places that texture so that its baseline lands on `y` plus the ascent that `compute_text_extent` gives the text: the baseline the layout computed. The cache is emptied at 16384 entries, and the textures of a renderer go when the renderer is destroyed.

`_compute_text_texture_box` finds the rectangle the texture covers, from the geometry of each glyph with no render, and `_extend_drawn_bounds!` adds it to the dirty rectangle of a partial repaint and to the size of `write_image`: the texture can reach past the box of the text, left of `x` by a negative left bearing and above its top by a glyph that rises above the ascent of its font.

### Paint a window

Each graphics type has a painter, and a nested canvas recurses with the sum of the offsets. The painters get the four edges of the clip, `_ClipEdges`. A canvas with a layout and elements that do not overlap draws only the elements between the edges: a `CellVector` starts at the element that `compute_first_visible_index` finds, and the render stops at the first element past the far edge. The render reads no content of an element that it does not draw, so a tree of many rows computes the rows on the screen. A window paints into an offscreen target that is `supersample` times the device size, 2 by default, and the copy to the window scales it down, which smooths the edges.

With `partial_render = true`, the backend walks the canvas before it paints. It finds a set of rectangles that covers every graphic that changed, and a graphic changes in one of three ways:

- **Its content changed.** A canvas whose element list, or a slot of it, is not up to date, a list node whose value or spine is not up to date, or a leaf whose own cell is not up to date and that draws something else. The walk tests `is_cell_up_to_date` before it reads a value, because a read computes the value again. Propagation is write-driven, so a cell is stale also when its new value is the same: a paint records a signature of each leaf, the hash of the values of its cells, and a stale leaf with the same signature and bounds is not painted. The chevron of each folder in a tree reads the set of open folders, and only the one that toggled changes.
- **It moved, or it was resized.** The walk compares the origin of each canvas, and the box, the content and the transform of each viewport, by value with what the last paint used. Propagation is write-driven, so the origin of a paragraph below an edit is computed again from the heights above it, and it is stale whether or not a height changed. A paragraph at the same place does not repaint, and one that moved does.
- **It came into view, or it left it.** A graphic that the walk has no record of is painted. A graphic that was painted and now lies past the layout early-stop is not drawn, and its old place is cleared.

A canvas whose element list changed is not painted whole. A paint records the placement keys of the elements that each canvas draws. The walk reads the new list in a second phase, after it has tested every cell of the frame, because a list can read the size of other graphics and compute their cells. It takes each element of the new list by its key: a new element is painted, a moved one at its old and new place, a kept one only when it draws something else, and the elements that the canvas drew before and does not draw now are cleared. A read of the list can have computed the cells below it, so under that canvas the walk does not trust a stale cell: it compares every leaf by its signature, every canvas by the keys it draws, and it paints a text list again. Where elements can overlap, the order draws too, so a kept element that has another place in the order is painted again. A container records its bounds from the records of what it draws, so the first phase queues that record after the lists below it. A leaf whose values can change in place and keep their hash, such as a pointer or an array of 32768 or more elements, which `hash` samples, has no signature and is painted whenever it is stale. So a folder that opens in the navigator paints its chevron, its new rows and the rows that move down, and no row above it. A rectangle with a transparent fill and no visible border, such as the hit target of a widget, gives no rectangle.

For each changed unit the walk adds the bounds that the unit had at the last paint, which `dirty_bounds` keeps, so a moved or removed element clears its old pixels. A unit is painted whole, so the walk also records the place and the bounds of everything inside it that the render reaches: the first change inside it then knows what it covered. A recording reads the new values, and a read computes a stale cell again, so the walk has two phases: it finds every change first, and it runs the recordings after, in the order it met them. A recording then cannot hide a change that the walk has still to test, as the box of a container that measures its children would. A record is keyed by the placement of a graphic, its `objectid` mixed with the key of the container that holds it, because one graphic can be drawn at more than one place: the regions of a table share its rules and bands. The walk passes the same origins and edges as the render, and a viewport gives both of them its content place from one function, `_compute_viewport_content_place`. The walk starts a laid-out canvas at the same element as the render. Its search tests each element before it reads it: a stale slot on the path of the search makes the canvas one unit, and a stale leaf keeps the test from before the read, so only the leaf repaints. The records of graphics that are gone stay until a full paint. When there are twice as many as the last full paint recorded, and 10000 more, the backend forgets them and paints the whole window once. The rectangles of a frame are a set: a rectangle that another one covers completely is dropped, and rectangles that only overlap are both kept. So a change in a paragraph and a change in the status bar at the bottom repaint two small boxes, and not the box that spans both. Each rectangle is painted into the kept target under its own clip, which costs one walk of the render for each, so a region of more than 32 rectangles is painted as the one rectangle that covers it. A paragraph that grows by a line gives two rectangles for itself and two for each paragraph below it that moves. A frame with no change paints nothing. The back buffer of the window was shown some frames ago, and the EGL or GLX buffer age says how many. So the copy to the window covers the rectangles of that many frames, and an unknown age copies all. The clip of a viewport runs after every recording, because a recording inside it adds the rectangles it clips. A viewport keeps the clips of the viewports inside its content, also those that the second phase finds, and runs them before its own. `debug_dirty = true` outlines the repainted rectangles in red, as the outline of their union: each edge of a rectangle is drawn only where it lies on the boundary of the union, so rectangles that overlap or touch show as one shape with no line inside (`_compute_union_outline`).

The offscreen renderer paints the same way for `VideoBackend(...; partial_render = true)`: its surface is the kept target, and `render_offscreen_changes!` paints only the rectangles of the walk. `write_offscreen_frame_with_overlay!` draws the pointer of the video and, with `debug_dirty`, the red outline on a copy of the frame, so neither enters the surface.

`partial_render`, `debug_dirty`, `debug_dirty_hold` and `supersample` are keywords of `SdlBackend`, on, off, 0 and 2 by default. The `RenderSettings` of an editor set them through `apply_settings!`, also while the editor runs, and the environment variables `PROJECTURED_PARTIAL_RENDER`, `PROJECTURED_DEBUG_DIRTY` and `PROJECTURED_SUPERSAMPLE` reach the backend through those settings (see [settings.md](../../platform/settings/settings.md)). A change of the mode or of the outline repaints each window in full at the next frame, and a new supersample factor makes the target of each window again.

The walk runs in both modes, because it also tells whether a frame differs from the one before. A window that shows such a frame gets a `DisplayUpdate`: `write_to_devices!` queues `WindowInput(id, DisplayUpdate(; time))` in `display_updates`, one for each window, `take_from_devices!` answers the queued updates before it polls SDL, and `wait_for_input` does not block while one waits. A frame with no change queues nothing, so the loop can sleep. A full frame still repaints and presents the whole window, whatever the walk found: the full mode does not depend on the walk to draw right, only to report.

A frame that changed a window can put another part under a pointer that does not move: a list scrolls, a popup opens or closes. So after a write in which a window showed a changed frame or closed, `write_to_devices!` also queues a `MouseMove` at the point where the pointer is now (`SDL_GetMouseState`), in the window that SDL reports under the pointer (`SDL_GetMouseFocus`), with the buttons that are held now. The move waits in `pending_motion`, after the `DisplayUpdate`, so a newer motion from SDL replaces it, and the rate limit of idle motion applies to it. Every reader reads it as it reads a move: the part under the pointer is found in the new frame, a cursor readout follows, and a part that the pointer left gets its leave. The next frame shows no new pixel when the move finds the same part, so the moves stop by themselves. A pointer on no window of the backend gives no move.

### The shape of the pointer

The backend keeps the canvas that each window drew last in `drawn_canvases`, and sets the cursor of the system to the shape that [`find_pointer_shape`](../../platform/graphics/graphics.md#the-shape-of-the-pointer) finds there at the pointer. It sets the cursor at two times: at each motion in `take_from_devices!`, before the rate limit of idle motion holds the sample back, so the shape does not wait for a frame, and again after each frame in `write_to_devices!`, so a frame that moves a part under a pointer that does not move still gets the right shape. It sets the cursor of the system only when the shape changes, and keeps the shape it set in `pointer_shape`.

Each shape of `POINTER_SHAPES` but the open hand and the closed hand has a cursor of the system, made once and kept in `cursors`. SDL2 has no system cursor for the open hand and the closed hand, so the backend makes each one from a glyph of the Lucide font that shows it, `hand` and `grab`, 22 logical pixels, black with a white outline and the hot spot in the middle (`_make_glyph_cursor`). `quit_backend!` frees every cursor it made.

### Events in

`take_from_devices!` polls SDL and returns one `WindowInput`:

| SDL event | Event |
| --- | --- |
| `SDL_KEYDOWN`, `SDL_KEYUP` | `KeyDown`, `KeyUp`, through `sdl_keysym_to_symbol` |
| `SDL_TEXTINPUT` | `KeyPress`, through `sdl_to_keypress` |
| mouse button down, up | `MouseDown`, `MouseUp` |
| mouse motion | `MouseMove`, coalesced |
| mouse wheel | `MouseScroll` |
| window close, window resize | `WindowClose`, `WindowResize` |
| `SDL_QUIT` | `WindowQuit` on the id `:none` |
| window focus gained | nothing; a new query of the colour settings of the system, whose change comes later as `SystemColorsChange` on the id `:none` |

Escape is an ordinary `KeyDown`. The backend makes no `MouseClick`: a gesture tracking projection builds a click from a down and an up. A run of motion events gives only its newest sample. An event that ends the run waits in `pending_input` for the next call, so a click never comes before the motion that led to it. Motion with no button held gives at most one sample in 30 ms, and a held sample is kept, so the last position of a pointer that stops arrives. `pending_input` and `pending_motion` are fields of the backend, so two backends in one process never share an event.

The held buttons and the modifiers of an event are those at its place in the queue, not at the time of the poll. A motion takes its held buttons from its own `state` mask. The backend keeps the modifiers of the last key event that it read, which `initialize_backend!` seeds from `SDL_GetModState`, and a mouse event and a text event take their modifiers from it. So a Ctrl key that goes up after a click leaves Ctrl on the click, and the last motion of a drag holds its button when the release waits behind it in the queue.

### The colour settings of the system

`find_system_colors` asks the operating system for its mode, its contrast and its accent, and waits at most half a second; the `appearance` wrapper calls it before the first print. Each system answers in its own way:

- **Linux:** on a GNOME desktop, and on a desktop that `XDG_CURRENT_DESKTOP` does not name, `gsettings` gives `color-scheme`, the high contrast of `org.gnome.desktop.a11y.interface` and `accent-color`, at once. Another desktop, or no answer of `gsettings`, asks the settings portal with `gdbus call … Settings.ReadAll`.
- **Windows:** the registry value `AppsUseLightTheme`, `SystemParametersInfoW(SPI_GETHIGHCONTRAST)` and `DwmGetColorizationColor`.
- **macOS:** `defaults read` of `AppleInterfaceStyle`, of `increaseContrast` and of `AppleAccentColor`.

An accent that the system names, as GNOME and macOS do, gives the step 9 colour of the hue of the default palette that the name means; a grey accent gives none. Each command runs with a limit, and a command that does not end in time is stopped: a call to the portal can wait for seconds where D-Bus does not answer. When a window gets the focus, the backend asks again in a task, with a limit of one second. A different answer waits in `system_colors_change`, a wake ends the wait of the editor, and `take_from_devices!` gives it as one `SystemColorsChange`.

### Wait and wake

`wait_for_input` blocks in `SDL_WaitEventTimeout` with a null event pointer, the form that removes nothing from the queue. It blocks in slices that let the garbage collector run: 10 ms with one thread, 100 ms with more. A `yield` between the slices gives the MCP server and the assistant on the same thread their turn. `wake_backend!` pushes a user event that `initialize_backend!` registered, through `SDL_PushEvent`, which SDL documents as safe from any thread. `take_from_devices!` skips that event.

### Zoom

The keys of the zoom and of the six scales are bindings of the `appearance`
wrapper of `build_editor`, an `AppearanceDocument` around the content; an editor
built with no `Appearance` has no zoom keys. [style.md](../../platform/style/style.md#the-zoom-and-the-scales)
describes the two kinds of change they reach.

- `AdjustZoomOperation` steps the `zoom` of the `Appearance` and copies it into
  the `zoom` of the `Display` of the backend, which scales the logical size of
  each window the other way. The native window keeps its device size, and the
  content lays out again through the exact range that the window gives it, as
  on a resize.
- `AdjustScaleOperation` steps one of the six scales, such as the font scale. A
  scale reaches no cell of the view, so `AppearanceManagingProjection` sets
  `editor.iomap` to `nothing` through `InvalidateProjectionOperation`, and the
  editor prints again.

Both repaint every window in full.

### Offscreen

`write_image(document, projection, filename; …)` renders with an SDL software renderer to BMP or PNG, with the same two-pass size to the content as `write_pdf`. `GraphicsCanvasToImageFile` is the form for the end of a chain. The offscreen renderer is public, because `ProjecturedVideo` records with it: `open_offscreen_renderer(width, height; supersample, scale)` answers a handle that holds the logical size, `write_offscreen_frames!(renderer, canvas; background, folder, frame, count)` writes the frames of a canvas, `make_offscreen_paint_state` and `render_offscreen_changes!` paint only what changed, `write_offscreen_frame_with_overlay!` and `write_offscreen_picture_with_overlay!` draw an overlay on a copy of the picture, and `close_offscreen_renderer` frees it; see [video.md](../video/video.md). `decode_image` loads an image file with SDL2_image, and `get_display_size` reads the usable bounds of the display, or the primary monitor from `xrandr` when SDL reports several monitors as one display.

`quit_backend!` frees the textures and the fonts before `SDL_Quit`. On macOS it sets the activation policy of the process back to Accessory. The first video initialisation registers the process as a foreground application, and `SDL_Quit` does not undo that. Without the reset, macOS shows a busy dock icon after the last window closes.

## How it fits

The code is the slice `SdlModule`, in `source/backend/sdl/`: `SdlModule.jl` holds its imports and its exports, and `ProjecturedSDL` includes that file and exports the same names.

`ProjecturedSDL` depends on the kernel and the platform, and on `SimpleDirectMediaLayer` and `SDL2_jll`. It declares the triggers `Projectured` and `SimpleDirectMediaLayer` with the default `auto`, so AutoIntegration loads it when both are loaded; see [autointegration.md](../../autointegration/autointegration.md). `using ProjecturedSDL` alone always loads it. It re-exports the essential names of `ProjecturedPlatform.EssentialsModule`; see [essentials.md](../../platform/essentials/essentials.md). `ProjecturedREPL` loads it, and `ProjecturedVideo` depends on it. The builder names it as the backend `sdl` of a binary, the default when a build holds both backends.

`default_backend()` in the [application slice](../../platform/application/application.md) returns an `SdlBackend` when the package is loaded. It registers nothing.

## Design decisions

- **The generic is the surface.** A caller reaches the backend through the generics of `BackendModule`: `render_canvas`, `decode_image`, `get_display_size`. The layout never asks the backend to measure text; it asks a `TextMeasure`.
- **The windows open before the first print.** A document laid out first is laid out at a size that the window never has. See [plan/done/native-window-size.md](../../../../plan/done/native-window-size.md).
- **The repaint follows the reactive graph.** The cells that a change invalidated say which graphics changed, so the backend compares no pixels. See [plan/done/optimize-rendering-dirty-rect.md](../../../../plan/done/optimize-rendering-dirty-rect.md).
- **The damage history follows the buffer age.** A swap chain of two or three buffers would otherwise show an old edit on the buffer that was not repainted.
- **The zoom and the scales take two routes.** The zoom needs no new print, since the backend reads the `zoom` of the `Display` while it draws; a scale prints again, because the widgets keep the sizes that they measured.
- **Xlib finds its locale data in its artifact.** The `__init__` of `ProjecturedSDL` sets `XLOCALEDIR` to the locale folder of `Xorg_libX11_jll`, unless the user set it. The build of that JLL names a folder that exists only on the machine that built it; without the data `XSupportsLocale` is false, and SDL gives a window no title, so X11 shows no `WM_NAME` and no `_NET_WM_NAME`.
- **The colours of the system are asked at the focus.** A person changes the setting of the system in another window, so the focus that comes back is the time to ask again. A listener for each system would know the change at once, but needs a D-Bus connection, a window procedure or an Objective-C notification. See section 12.16 of [plan/pending/one-coherent-color-set.md](../../../../plan/pending/one-coherent-color-set.md).
- **Video starts only when it does not run.** `initialize_backend!`, `get_display_size`, `decode_image`, `write_image` and the offscreen renderer start SDL video through one guard. SDL counts the starts of video in one byte: after 256 starts the count is zero again, and the next start quits video first, which destroys every window and sends no event.
- **The state of an editor is on its backend.** The pending input, the time of the rate limit of idle motion, the switches `partial_render` and `debug_dirty`, and the `Display` are fields of the backend, so two backends in one process keep them apart. The SDL session is still one for each process: one event queue, and one set of open fonts.

## Usage

```julia
run_editor!(document, projection; backend = SdlBackend())
backend = SdlBackend(; debug_dirty = true)
write_image(document, projection, "snapshot.png")
projection = TextToGraphics(measure = FontFileMeasure())
```

- Examples: every gallery example runs on it by default. `example/backend/sdl/LiveExamples.jl` plays a timeline in a window or records it with `record_video`. The screenshots under `asset/image/example/` come from `write_image`.
- Test: `test_sdl()` in `ProjecturedSDLTest` runs the layering guard, the dirty rectangle, the key symbols, the device configuration, the agreement of the font metrics with SDL_ttf (`test_sdl_font_metrics_agree`), the baseline of the drawn ink and the pen positions of each glyph (`test_sdl_text_baseline_ink`, `test_sdl_text_pen_positions`), the coalescing of input, the wait and the wake, the native windows, `write_image`, and `test_sdl_pointer_shape()`, which reads the shape that the backend chooses for a motion pushed onto the real SDL queue.

## Limits

- `render_canvas` returns an empty `GraphicsImage`: `render_sdl_canvas` draws nothing yet.
- The partial repaint is off by default.
- A change of the `style` of a window is recorded and not applied, because SDL can change only some window flags after the window exists.
- The pointer shows no hourglass while a frame is long: the thread that runs the frame is the only one that SDL lets change the cursor.
