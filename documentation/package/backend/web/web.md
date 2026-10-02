# Web backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [screen.md](../../platform/screen/screen.md), [style.md](../../platform/style/style.md)

`ProjecturedWeb` holds `WebBackend`, which runs the editor in an HTTP and WebSocket server and draws it in a browser. The Julia process keeps the document, the projections, the cells and the editor loop; a small JavaScript client sends the input and paints a draw list on an HTML canvas. This document says how the backend implements the interface of [devices-and-backends.md](../../kernel/devices-and-backends.md), what goes over the socket, and what it does not do yet.

## How it works

[The WebBackend section](../../kernel/devices-and-backends.md#webbackend) of the kernel guide shows the messages of the wire protocol in both directions. This section says how the code produces and reads them.

### The server

`initialize_backend!` starts `HTTP.listen!` on `host` and `port`, `127.0.0.1:8080` by default. A WebSocket upgrade goes to the socket handler, and any other request gets a static file: `/` or `/index.html`, `/client.js`, `/fonts.json` with the names of the font files, and `/font/<name>`. The handler takes only the base name of a font path, so a request can not read a file outside the font folder. The backend writes the URL with `println` to standard output and not with a log call. A binary that logs from `warn` up would hide an `@info`, and the URL is the only way to find the page.

`get_web_asset_directory(name)` returns `share/projectured/<name>` beside the executable of a built binary, and `asset/<name>` of the checkout in a Julia session. The client and the fonts come from there.

The backend holds one connection. A second WebSocket gets the message `{"type":"busy"}`, and the backend reads nothing from it. `quit_backend!` closes the connection and the server.

### Measure

A projection of the server measures text with a `FontFileMeasure()` of the style slice, so the backend needs no SDL; see [style.md](../../platform/style/style.md#measurement-without-a-display). The layout measures text while it prints, before the browser gets anything, so the server must measure. It serves the same font files, and the client loads them with the `FontFace` API, so the browser draws with the metrics that the layout used. `FontFileMeasure` measures at `font.size`: a font already scaled for its appearance, so a change of the font scale needs a new print from the server, not a relayout the measure discovers on its own. The pixel density of the display belongs to the browser, and the zoom of the editor goes to the browser in each update, so the server stays in logical pixels.

Each drawn text sends the ascent of its box (`b`), the pen offset of each character (`o`) from `compute_caret_offsets`, and its font and its fallback fonts as a CSS font family stack (`f`). The client sets `textBaseline = "alphabetic"` and draws each character alone at its own offset from the pen position, on the baseline `y + b`, so the browser's own kerning and ligatures never move a glyph.

### Draw

`write_to_devices(backend, devices, screen::ScreenDocument)` sends one message of type `update` for each frame that changed something, and nothing when no client is connected or nothing changed:

- **`zoom`** is the zoom of the `Display` in `devices`, or 1 with none. The `appearance` wrapper copies the zoom of the editor into that `Display`. The client draws each logical pixel as `devicePixelRatio × zoom` pixels of the page, divides each size and each pointer position that it sends by `zoom`, and multiplies the size and the place of a window that it opens by `zoom`. A new zoom makes the client send the new logical size of each window and a `resync`.
- **`full`** holds the whole draw list of a window. A window goes in full on its first paint, after a connection, after a `resync` from the client, after the queue overflowed, and after a new zoom.
- **`patches`** holds, for every other window, one clip rectangle and the primitives that cross it. `_collect_window_dirty` finds the rectangle from the cells that are not up to date, as the SDL backend does. `prev_bounds` keeps the last bounds of each unit, so a moved unit also clears its old place.
- **`close`** holds the ids of the windows that left the screen document.

After the `update` message, the backend sends `{"type": "pointer", "window": id, "cursor": css}` when the shape that [`find_pointer_shape`](../../platform/graphics/graphics.md#the-shape-of-the-pointer) finds changes, at the point and in the window of the last pointer event that the editor read. `cursor` is the CSS cursor of the shape:

| Shape | CSS cursor |
| --- | --- |
| `arrow` | `default` |
| `ibeam` | `text` |
| `double_arrow_horizontal` | `col-resize` |
| `double_arrow_vertical` | `row-resize` |
| `pointing_hand` | `pointer` |
| `open_hand` | `grab` |
| `closed_hand` | `grabbing` |
| `crossed_circle` | `not-allowed` |
| `hourglass` | `wait` |

A shape that the table does not name sends `default`. The client sets `canvas.style.cursor` of the window to `cursor` (`setPointerCursor` in `asset/web/client.js`). A press captures the pointer (`setPointerCapture`), so until the release the canvas gets the moves and the release, and shows its cursor, also outside the window.

The first `WindowDocument` is the primary one, and the client draws it in the page itself; every other window opens as a browser window. A browser opens a window only inside a user action, and a window that the editor opens by itself comes with none. So the client opens one spare browser window at a user action and gives it to the next window that arrives with no action. The serializer mirrors the painters of the SDL backend: `text`, `rect`, `line`, `circle`, `polyline`, `polygon`, `clip` for a viewport, `group` for a nested canvas, and `image`. A spline is cut into a polyline on the server. An image goes as base64 RGBA, and a `GraphicsFence` or an image held as an SDL texture is skipped. Any output other than a `ScreenDocument` raises an error.

The messages go through an ordered queue to a send task. A patch depends on the patches before it, so the queue never merges or drops one. A full frame makes the older messages useless, so it empties the queue first. A queue that is almost full is emptied too, and the next frame goes in full.

### Events in

The socket handler decodes each JSON message and puts a `WindowInput` into the channel `inbound`. `read_from_devices` takes one event from the channel, or returns `nothing`.

Each client message holds `t`: the time of its browser event in milliseconds since the Unix epoch, `performance.timeOrigin + event.timeStamp`, or the time of the send for a message with no browser event. The event gets `t / 1000`, on the clock of `time()`. A message with no `t` gets the time when it arrives.

| Client message | Event |
| --- | --- |
| `mousedown`, `mouseup` | `MouseDown`, `MouseUp` |
| `mousemove` | `MouseMove`: with a button held at once, with no button held at most once per animation frame |
| `scroll` | `MouseScroll` |
| `keydown`, `keyup` | `KeyDown`, `KeyUp`, through `convert_web_key_to_symbol` |
| `keypress` | `KeyPress` |
| `resize`, `close`, `blur` | `WindowResize`, `WindowClose`, `WindowDefocus` |
| `leave` (the `mouseleave` of a canvas) | `WindowLeave` |
| `quit` | `WindowQuit` |
| `resync` | no event; the next frame goes in full |

`convert_web_key_to_symbol` maps the `key` and `code` of a browser key event to the key symbols that `sdl_keysym_to_symbol` gives, so both backends speak one vocabulary. Escape is an ordinary key. The backend makes no `MouseClick`: a gesture tracking projection builds the click, as for SDL.

### Wait and wake

`wait_for_input` returns at once when an event waits in `inbound`. Else it waits on an autoreset `Base.Event`, with a `Timer` for the timeout. The socket handler notifies the event after it puts the event of a message into `inbound`, and `wake_backend!` notifies the same event, from any task or thread. A new connection, a `resync` and an overflow of the queue notify it too. Each of them needs a frame that sends every window in full, and an idle editor waits with no timeout. So an idle editor uses no processor time, and a browser that connects gets its first frame at once.

## How it fits

The code is the slice `WebModule`, in `source/backend/web/`: `WebModule.jl` holds its imports and its exports, and `ProjecturedWeb` includes that file and exports the same names.

`ProjecturedWeb` depends on the kernel and the platform, and on `HTTP`, `JSON3` and `Base64`. It needs no SDL. It registers nothing.

`default_backend()` in the [application slice](../../platform/application/application.md) picks `WebBackend` when `SdlBackend` is not loaded. The builder names it as the backend `web`, and a binary with both backends takes `--backend=web`. The test of a distribution starts the copied binary with `--backend=web` and reads the client and a font through this server; see [builder.md](../../tool/builder/builder.md).

## Design decisions

- **The server keeps everything but the paint.** The backend touches no projection and no domain: it reads the same `ScreenDocument` and writes the same events as the SDL backend. See [plan/done/web-backend.md](../../../../plan/done/web-backend.md).
- **The key map is on the server.** One table maps both the SDL and the browser keys to one vocabulary, so the two can not drift.
- **The first window is in the page.** A browser opens a window only inside a user action. A first window of its own would need a click before the editor shows anything. See [plan/done/web-main-window-in-tab.md](../../../../plan/done/web-main-window-in-tab.md).
- **A window of the editor is a window of the browser.** The client does not fold a second window into the page, as on the SDL backend.
- **The measure is SDL-free.** The server measures with the font files that the browser draws with.

## Usage

```julia
using ProjecturedWeb
run_example("json"; backend = WebBackend())                # http://127.0.0.1:8080
run_example("json"; backend = WebBackend(port = 9000))
run_example(["json", "xml"]; backend = WebBackend())       # the first in the page, the rest as windows
```

- Example: the gallery with `backend = WebBackend()`. The package has no example of its own.
- Test: `test_web_backend()` in `test/projectured/backend/WebTest.jl` decodes client messages into the queue, reads them, and checks the wait and the wake. One of its tests starts the server on a free port of 127.0.0.1, connects a WebSocket client and reads a static file. Another checks the `pointer` message: the CSS cursor it sends for the shape at the point of the last pointer event, and that an unchanged shape sends nothing. `test/tool/builder/BuilderTest.jl` checks that a build names the backend, and `test/projectured/editor/ApplicationTest.jl` checks the parse of `--backend=web`.

## Limits

- No test covers the draw list or the patches.
- One client for each editor, and the transport is JSON in both directions. [plan/done/web-backend.md](../../../../plan/done/web-backend.md) holds both as the choices of the first version.
