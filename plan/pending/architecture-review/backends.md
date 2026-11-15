# Architecture review: the backends (SDL, web, PDF, video, console)

Commit 3a9b4fae4. Reviewer area key: backends.

## Scope

Paths: `source/backend/{sdl,web,pdf,video,console}`, `source/kernel/{backend,device}`, and, as users of the seam, `source/platform/{screen,graphics,display}`.

Read in full (about 6 600 lines of code):

- `source/kernel/backend/*` and `source/kernel/device/*` (421 lines), `source/kernel/event/KeyboardEvent.jl`, `source/kernel/editor/BackendChoice.jl`.
- `source/backend/web/WebBackend.jl` (1 154), `source/backend/pdf/PdfWriter.jl` (879), `source/backend/video/VideoBackend.jl` (620) and `VideoRecording.jl` (219), `source/backend/console/ConsoleBackend.jl` (548), the five module files.
- `source/backend/sdl/SdlHeldFrames.jl` (369), `SdlWorkload.jl` (125), `SdlModule.jl`.
- `source/platform/graphics/GraphicsDocument.jl` (1 306), `PointerShape.jl` (122), `source/platform/screen/ScreenDocument.jl` (334), `RenderSettings.jl`, `PartPicture.jl`, `source/platform/application/DefaultBackend.jl`.

`source/backend/sdl/SdlBackend.jl` has 6 464 lines. I read about 3 950 of them: lines 1–1468 (state, keys, windows, density, text, viewport), 2129–2360 (the render of a canvas), 2455–2700, 4524–5253 (the paint of a window, the offscreen renderer, `write_image`), 5368–6093 (wait, input, windows, pointer shape) and 6186–6464 (fit, place, zoom, devices). Of the rest I read the list of all definitions and samples of the painters (1605–2128) and of the walk for what changed (2655–2700, 3640–3692, 3912–3962), and I searched the range 2314–4256 for calls of SDL.

Sampled: `ScreenToScreen.jl` (22–165), `WindowScene.jl` (150–215), `WindowManaging.jl` (263–280), `EditorDisplay.jl` (1–60), `DisplayWorkload.jl` (1–120), `SystemColorQuery.jl` (1–60 and its definitions), `GraphicsCaching.jl` (1–80), `source/platform/clipboard/Clipboard.jl` (1–215), `source/platform/style/TextMeasure.jl` (120–215), `source/kernel/gesture/GesturePattern.jl` (170–215), `asset/web/client.js` (245–330, 468–494, 572–640, 680–785), `example/kernel/BackendHeadless.jl` (1–80).

Documents: `concepts.md`, `architecture-decisions.md`, `devices-and-backends.md`, the five documents under `documentation/package/backend/`, `popup-window.md` (parts), the PAR rules of the section "Editor, devices, and backends" and PAR-SINGLE-WRITER, PAR-STORE-THEN-DRAIN, PAR-BIDIRECTIONAL-PROJECTION. Plans: `cairo-glfw-backend.md`, `sdl-per-editor-state.md`, `sdl-backend-outputs.md` (tentative), `packages-compose-by-seams.md` (the decisions and the step list), `faster-executable-startup.md` (head), `event-layer-reaudit.md`, and the kernel audit files `06-event.md`, `07-device.md`, `09-backend.md`, `23-playback.md`.

I ran no Julia and no test. Every claim below comes from the code as read.

## State

The kernel half of the seam is small and sound. It is one abstract type, `Backend`, and 19 generic functions, 11 of them with a legal default ([BackendInterface.jl:16](../../../source/kernel/backend/BackendInterface.jl#L16)). Three things already sit once above the seam, as the principles ask: the measure of text (`FontFileMeasure` of the style slice), the geometry of a spline and of an arrowhead, and the event vocabulary. No backend makes a click or a chord.

The weakness is on the other side of the seam. `SdlBackend.jl` is not only a binding to SDL. It also holds the model of how a window is painted: the walk of a canvas between the edges of a clip, the search for what changed since the last paint (about 1 940 lines that call no SDL function), the fit of a window to its content, the report of a changed frame, and the queue of the input. The web backend, the PDF writer and the two test backends have a smaller copy of some of these parts, or none. So a feature of the model holds on SDL only: a lazy list is drawn lazily, a popup fits its content, a changed frame is reported, a repaint keys a graphic by its placement.

The same shape shows in the smaller things. Each painter decides again how a rectangle with a border composes. Each backend names its keys by its own table. Three backends hold their own copy of the rule of a held frame. The clipboard goes around the backend, and the colours of the system are read by code that sits in the SDL package and calls no SDL function.

The pending plan for a Cairo and GLFW backend says to copy the painters of the PDF writer and the window loop of SDL. That would be the fourth copy. The main proposal of this review is one more layer above the seam, written once (a walk of a canvas, a paint record, a window host, an input queue), and a thinner seam below it.

## Inventory

### 1. The seam: generic × backend

"default" is the method of [BackendDefaults.jl](../../../source/kernel/backend/BackendDefaults.jl). "—" is no method, so a `MethodError`.

| Generic | Declared in | SDL | Web | Console | Video | Test doubles |
| --- | --- | --- | --- | --- | --- | --- |
| `initialize_backend!`, `quit_backend!` | kernel/backend | yes | yes | yes | yes | yes |
| `take_from_devices!` | kernel/backend | [5539](../../../source/backend/sdl/SdlBackend.jl#L5539) | [860](../../../source/backend/web/WebBackend.jl#L860) | [358](../../../source/backend/console/ConsoleBackend.jl#L358) | [286](../../../source/backend/video/VideoBackend.jl#L286) | queue |
| `write_to_devices!` | kernel/backend | `ScreenDocument` [5937](../../../source/backend/sdl/SdlBackend.jl#L5937) | `ScreenDocument` [1058](../../../source/backend/web/WebBackend.jl#L1058) | `TextBlock` [334](../../../source/backend/console/ConsoleBackend.jl#L334) | `ScreenDocument`, one window [488](../../../source/backend/video/VideoBackend.jl#L488) | any value |
| `wait_for_input`, `wake_backend!` | kernel/backend | yes | yes | yes | wait only | default |
| `open_native_windows!` | kernel/backend | [5822](../../../source/backend/sdl/SdlBackend.jl#L5822) | default | default | default | default |
| `configure_devices!` | kernel/backend | keeps the `Display` | default | default | keeps the `Display` | default |
| `get_display_size`, `get_pointer_position` | kernel/backend | yes | default | default | yes | default |
| `find_system_colors` | kernel/backend | yes, no SDL call | default (`nothing`) | default | default | headless: scripted |
| `prepare_held_frames!`, `run_held_frame!`, `end_held_frames!` | kernel/backend | [SdlHeldFrames.jl:170](../../../source/backend/sdl/SdlHeldFrames.jl#L170) | [938](../../../source/backend/web/WebBackend.jl#L938) | [168](../../../source/backend/console/ConsoleBackend.jl#L168) | none (`shows_held_frames` is false) | default |
| `write_image`, `decode_image`, `render_canvas` | kernel/backend, no backend argument | yes (`render_canvas` is a stub) | — | — | — | — |
| `record_video` | kernel/backend, no backend argument | — | — | — | yes | — |
| `get_backend_name`, `get_backend_output` | kernel/editor ([BackendChoice.jl:15](../../../source/kernel/editor/BackendChoice.jl#L15)) | `:sdl`, `:windows` | `:web`, `:windows` | `:console`, `:text` | none | none |
| `get_frame_clock_time` | kernel/editor | default | default | default | [207](../../../source/backend/video/VideoBackend.jl#L207) | default |
| `apply_settings!`, `read_settings!` for `RenderSettings` | platform/settings and platform/screen | [413](../../../source/backend/sdl/SdlBackend.jl#L413) | none | none | [187](../../../source/backend/video/VideoBackend.jl#L187) | none |
| `open_url!` | platform/link ([OpenUrlOperation.jl:43](../../../source/platform/link/OpenUrlOperation.jl#L43)) | [491](../../../source/backend/sdl/SdlBackend.jl#L491) | default (`false`) | default | default | default |
| `send_workload_inputs!`, `has_workload_inputs` | platform/display | [SdlWorkload.jl:38](../../../source/backend/sdl/SdlWorkload.jl#L38) | none | none | none | `WorkloadBackend` |
| clipboard | not in the seam: [Clipboard.jl:84](../../../source/platform/clipboard/Clipboard.jl#L84) | shell tools | shell tools of the server | shell tools | — | a swapped global function |

### 2. Capability × backend

| Capability | SDL | Web | PDF | Video | Console |
| --- | --- | --- | --- | --- | --- |
| Text, rect, line, circle, arc, polyline, polygon, spline, nested canvas | yes [2213](../../../source/backend/sdl/SdlBackend.jl#L2213) | yes [231](../../../source/backend/web/WebBackend.jl#L231) and `client.js:403` | yes [511](../../../source/backend/pdf/PdfWriter.jl#L511) | by SDL | no: text runs only |
| Image as RGBA bytes | yes | yes | yes | by SDL | no |
| Image as an SDL texture pointer | yes [2094](../../../source/backend/sdl/SdlBackend.jl#L2094) | skipped | skipped | by SDL | no |
| Clip of a viewport, nested | by hand [1388](../../../source/backend/sdl/SdlBackend.jl#L1388) | native | native | by SDL | no |
| Transform of a viewport | scale and move [1444](../../../source/backend/sdl/SdlBackend.jl#L1444) | full matrix to the client [297](../../../source/backend/web/WebBackend.jl#L297) | scale and move [498](../../../source/backend/pdf/PdfWriter.jl#L498) | by SDL | no |
| Draws only what is in view | yes [2137](../../../source/backend/sdl/SdlBackend.jl#L2137) | no [199](../../../source/backend/web/WebBackend.jl#L199) | no [538](../../../source/backend/pdf/PdfWriter.jl#L538) | yes | whole block |
| Text measure | style slice | style slice | style slice | style slice | none needed |
| Fonts | font files, fallback file for each glyph | font files served, fallback chosen by the browser | embedded TrueType, own fallback runs | by SDL | terminal |
| Decode an image file | yes [6445](../../../source/backend/sdl/SdlBackend.jl#L6445) | no | no | by SDL | no |
| Pointer events | down, up, move, scroll with fraction, leave | down, up, move, scroll of one notch (`client.js:739`), leave | — | timeline | none |
| Key events | down, up, press | down, up, press | — | timeline | down or press, no up |
| Text input | `SDL_TEXTINPUT` | one character for each `keypress` (`client.js:767`) | — | timeline | UTF-8 bytes |
| Clipboard | not through the backend | not through the backend | — | — | not through the backend |
| Cursor shape | system and glyph cursors [6049](../../../source/backend/sdl/SdlBackend.jl#L6049) | CSS cursor [1128](../../../source/backend/web/WebBackend.jl#L1128) | — | drawn picture [443](../../../source/backend/video/VideoBackend.jl#L443) | no |
| More than one window | yes | yes, browser windows | — | one window [612](../../../source/backend/video/VideoBackend.jl#L612) | no window |
| Popup style (no frame, no focus) | yes [660](../../../source/backend/sdl/SdlBackend.jl#L660) | style is sent, the client does not read it | — | no | no |
| Window fits its content | yes [6199](../../../source/backend/sdl/SdlBackend.jl#L6199) | no | — | no | no |
| Areas of the displays | yes [6215](../../../source/backend/sdl/SdlBackend.jl#L6215) | no | — | no | no |
| Zoom | keeps the device size [6371](../../../source/backend/sdl/SdlBackend.jl#L6371) | in the client (`client.js:245`) | — | keeps the frame size [428](../../../source/backend/video/VideoBackend.jl#L428) | no |
| Density | probe of the machine | of the browser | 1 point is 1 pixel | keyword | no |
| Repaint of a part | guards, moves, placement keys | one rectangle, keys by object [454](../../../source/backend/web/WebBackend.jl#L454) | — | by SDL, optional | compare of the whole frame text |
| Report of a changed frame (`DisplayUpdate`) | yes [5994](../../../source/backend/sdl/SdlBackend.jl#L5994) | no | — | no | no |
| Picture of a part or a window | `write_image` | no | `write_pdf` | frames | no |
| Time of an event | SDL ticks | time of the browser event | — | schedule | time of the read |
| Colours of the system, open a URL | yes | no | — | no | no |

### 3. Draw code per primitive

Each row is one place that tests the type of a graphics element with a chain of `isa`.

| Purpose | Where | Types it names |
| --- | --- | --- |
| draw, SDL | `_dispatch_render_elem!` [SdlBackend.jl:2213](../../../source/backend/sdl/SdlBackend.jl#L2213) | 11 |
| draw, web, server | `_serialize_node` [WebBackend.jl:231](../../../source/backend/web/WebBackend.jl#L231), and again clipped at [369](../../../source/backend/web/WebBackend.jl#L369) | 11 |
| draw, web, browser | `renderNode` in `asset/web/client.js:403` | 10 |
| draw, PDF | `paint_elem!` [PdfWriter.jl:511](../../../source/backend/pdf/PdfWriter.jl#L511) | 11 |
| bounds | `extend_element_bounds!` [GraphicsDocument.jl:1221](../../../source/platform/graphics/GraphicsDocument.jl#L1221) | 11 |
| hit test | `_hit_test_element` [GraphicsDocument.jl:1032](../../../source/platform/graphics/GraphicsDocument.jl#L1032) | 11 |
| pointer shape | `_find_element_shape!` [PointerShape.jl:101](../../../source/platform/graphics/PointerShape.jl#L101) | 3 |
| ink bounds, invisible test, guard, SDL | [2502](../../../source/backend/sdl/SdlBackend.jl#L2502), [2496](../../../source/backend/sdl/SdlBackend.jl#L2496), [3942](../../../source/backend/sdl/SdlBackend.jl#L3942) | 2 to 3 each |
| read all, test backends | `_paint_headless!` [BackendHeadless.jl:55](example/kernel/BackendHeadless.jl#L55), `_read_graphics` [DisplayWorkload.jl:111](../../../source/platform/display/DisplayWorkload.jl#L111) | by field name |

Logic that exists in more than one painter:

| Logic | SDL | Web | PDF | Shared today |
| --- | --- | --- | --- | --- |
| Rectangle with a border: ring or two fills | [1613](../../../source/backend/sdl/SdlBackend.jl#L1613) | `client.js:471` | [210](../../../source/backend/pdf/PdfWriter.jl#L210) | no |
| Circle with a border | [2015](../../../source/backend/sdl/SdlBackend.jl#L2015) | `client.js:575` | [272](../../../source/backend/pdf/PdfWriter.jl#L272) | no |
| Spline to a polyline, arrowheads, the line before an arrowhead | [1794](../../../source/backend/sdl/SdlBackend.jl#L1794), [1946](../../../source/backend/sdl/SdlBackend.jl#L1946) | [215](../../../source/backend/web/WebBackend.jl#L215) | [352](../../../source/backend/pdf/PdfWriter.jl#L352) | the geometry is shared, each painter calls it |
| Where each glyph of a text goes, and in which font file | `compute_placed_glyphs` [1121](../../../source/backend/sdl/SdlBackend.jl#L1121) | offsets and a stack of font families [239](../../../source/backend/web/WebBackend.jl#L239) | own runs and own kerning [130](../../../source/backend/pdf/PdfWriter.jl#L130), [150](../../../source/backend/pdf/PdfWriter.jl#L150) | three ways |
| The forms of the data of an image | [2091](../../../source/backend/sdl/SdlBackend.jl#L2091) | [306](../../../source/backend/web/WebBackend.jl#L306) | [463](../../../source/backend/pdf/PdfWriter.jl#L463) | no |
| Colour to bytes | `_rgba8` [1185](../../../source/backend/sdl/SdlBackend.jl#L1185) | `_rgba` [193](../../../source/backend/web/WebBackend.jl#L193) | `_rgba8` [21](../../../source/backend/pdf/PdfWriter.jl#L21) | no; the console has `_component` [238](../../../source/backend/console/ConsoleBackend.jl#L238) |
| Where a viewport puts its content | [1444](../../../source/backend/sdl/SdlBackend.jl#L1444) | `client.js:624` | [489](../../../source/backend/pdf/PdfWriter.jl#L489) | no; also [PointerShape.jl:108](../../../source/platform/graphics/PointerShape.jl#L108) and [ReferenceBox.jl:117](../../../source/platform/graphics/ReferenceBox.jl#L117) |
| Which elements of a canvas to visit | between clip edges [2137](../../../source/backend/sdl/SdlBackend.jl#L2137) | every element [325](../../../source/backend/web/WebBackend.jl#L325) | every element [538](../../../source/backend/pdf/PdfWriter.jl#L538) | no |
| Print twice to fit the content | [4906](../../../source/backend/sdl/SdlBackend.jl#L4906) | — | [793](../../../source/backend/pdf/PdfWriter.jl#L793) | no |

### 4. Translation of events

| Job | SDL | Web | Console | Others |
| --- | --- | --- | --- | --- |
| Name of a key | `sdl_keysym_to_symbol`, 65 lines [509](../../../source/backend/sdl/SdlBackend.jl#L509) | `convert_web_key_to_symbol`, 55 lines [130](../../../source/backend/web/WebBackend.jl#L130) | two tables and the Ctrl bytes [473](../../../source/backend/console/ConsoleBackend.jl#L473), [480](../../../source/backend/console/ConsoleBackend.jl#L480), [422](../../../source/backend/console/ConsoleBackend.jl#L422) | label of a key: [GesturePattern.jl:187](../../../source/kernel/gesture/GesturePattern.jl#L187) |
| Key code of a name (the way back) | a search over about 430 codes [SdlWorkload.jl:111](../../../source/backend/sdl/SdlWorkload.jl#L111) | — | — | — |
| `KeyPress` of Return and Tab | owed after the `KeyDown` [5714](../../../source/backend/sdl/SdlBackend.jl#L5714) | after the `KeyDown` [645](../../../source/backend/web/WebBackend.jl#L645) | a `KeyPress` only, no `KeyDown` [419](../../../source/backend/console/ConsoleBackend.jl#L419), [529](../../../source/backend/console/ConsoleBackend.jl#L529) | — |
| Modifiers of a pointer event | of the last key event in the queue [5736](../../../source/backend/sdl/SdlBackend.jl#L5736) | of the browser event [574](../../../source/backend/web/WebBackend.jl#L574) | — | — |
| Run of motion gives its newest sample | Julia [5553](../../../source/backend/sdl/SdlBackend.jl#L5553) | not on the server | — | — |
| Limit of idle motion | 30 ms [873](../../../source/backend/sdl/SdlBackend.jl#L873) | one for each animation frame, in `client.js:709` | — | — |
| Run of wheel events merged | [5589](../../../source/backend/sdl/SdlBackend.jl#L5589) | no | — | — |
| Shift and wheel turn sideways | [5778](../../../source/backend/sdl/SdlBackend.jl#L5778) | no code | — | — |
| Id of "no window" | `:none` | `:none` | `:console` [372](../../../source/backend/console/ConsoleBackend.jl#L372) | — |
| Where the pointer is, for its shape | asks SDL [6056](../../../source/backend/sdl/SdlBackend.jl#L6056) | `_track_pointer!` [873](../../../source/backend/web/WebBackend.jl#L873) | — | `_track_pointer!` [VideoBackend.jl:347](../../../source/backend/video/VideoBackend.jl#L347) |
| New time on a scripted event | — | — | — | `_restamp_event` [VideoBackend.jl:315](../../../source/backend/video/VideoBackend.jl#L315), `_stamp_event` [DisplayWorkload.jl:95](../../../source/platform/display/DisplayWorkload.jl#L95) |

There is no shared table. The event layer names the keys in a docstring ([KeyboardEvent.jl:10](../../../source/kernel/event/KeyboardEvent.jl#L10)).

### 5. Backends that only write, and scripted input

| Shape | Examples |
| --- | --- |
| A function that takes a canvas | `write_image` [SdlBackend.jl:4830](../../../source/backend/sdl/SdlBackend.jl#L4830), `write_pdf` [PdfWriter.jl:747](../../../source/backend/pdf/PdfWriter.jl#L747) |
| A function that prints, fits and writes | `write_image` [4906](../../../source/backend/sdl/SdlBackend.jl#L4906), `write_pdf` [793](../../../source/backend/pdf/PdfWriter.jl#L793) |
| A projection with a printer only | `GraphicsCanvasToImageFile` [4989](../../../source/backend/sdl/SdlBackend.jl#L4989), `GraphicsCanvasToPdfFile` [859](../../../source/backend/pdf/PdfWriter.jl#L859) |
| A picture of a running editor | `write_part_picture`, `write_window_picture` [PartPicture.jl:18](../../../source/platform/screen/PartPicture.jl#L18) |
| An offscreen renderer as an untyped named tuple, 8 exported functions | `open_offscreen_renderer` [4730](../../../source/backend/sdl/SdlBackend.jl#L4730) |
| A loop of its own over a timeline | `record_video` [VideoRecording.jl:71](../../../source/backend/video/VideoRecording.jl#L71) |
| A `Backend` whose input is a script | `VideoBackend`, `WorkloadBackend` [DisplayWorkload.jl:16](../../../source/platform/display/DisplayWorkload.jl#L16), `HeadlessBackend`, and `play_live!` of the kernel |

### 6. State of a backend

| State | Where | Scope |
| --- | --- | --- |
| Windows, pending input, modifiers, `Display`, cursors, system colours | fields of `SdlBackend` [270](../../../source/backend/sdl/SdlBackend.jl#L270) | one backend |
| Open fonts, text textures | `_font_cache` [353](../../../source/backend/sdl/SdlBackend.jl#L353), `_text_texture_cache` [383](../../../source/backend/sdl/SdlBackend.jl#L383) | process |
| Pixels in one window unit of the last window | `_LAST_PIXELS_PER_WINDOW_UNIT` [845](../../../source/backend/sdl/SdlBackend.jl#L845) | process |
| Density of the display, EGL and GLX probes | [917](../../../source/backend/sdl/SdlBackend.jl#L917), [4270](../../../source/backend/sdl/SdlBackend.jl#L4270) | process, a fact of the machine |
| Held frames of each backend | `_HELD_FRAMES` [SdlHeldFrames.jl:64](../../../source/backend/sdl/SdlHeldFrames.jl#L64) | process table, one entry for each backend |
| The SDL session and its one event queue | SDL | process |
| All state of the web, console and video backends | fields of the backend | one backend |
| Clipboard reader, writer and write chain | [Clipboard.jl:84](../../../source/platform/clipboard/Clipboard.jl#L84), [153](../../../source/platform/clipboard/Clipboard.jl#L153) | process |

## Findings

### BE-1 The walk of a canvas has no one home, and only the SDL backend draws just what is in view

- **Kind:** partial-feature · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 1 (only what is visible is computed) and 7 (one mechanism for every list). The settled decision on lazy lists: one generic solution for every list.
- **Today:** A `GraphicsCanvas` is the sheet that holds drawn elements. Its elements are a vector of cells or a `ListNode`, a link of a lazy list that can have no end. Which elements a reader must visit is decided in each reader.
  - The SDL render `_render_canvas!` visits only the elements between the edges of the clip. It starts a vector at the first element in view, stops at the first one past the far edge, and steps a list back and forward from its head ([SdlBackend.jl:2137](../../../source/backend/sdl/SdlBackend.jl#L2137)). Six more walks in the same file must visit the same elements: the record, the walk for what changed, the guard, the move, the forget and the cover of a move. A comment says so ([1427](../../../source/backend/sdl/SdlBackend.jl#L1427)). Each repeats the loop over a vector ([2657](../../../source/backend/sdl/SdlBackend.jl#L2657), [3101](../../../source/backend/sdl/SdlBackend.jl#L3101), [3391](../../../source/backend/sdl/SdlBackend.jl#L3391), [3625](../../../source/backend/sdl/SdlBackend.jl#L3625), [3916](../../../source/backend/sdl/SdlBackend.jl#L3916), [4099](../../../source/backend/sdl/SdlBackend.jl#L4099)). *Corrected by the check:* the walks of the SDL file already share their parts. Five of them take the nodes of a list from one helper, `_collect_drawn_nodes` ([3653](../../../source/backend/sdl/SdlBackend.jl#L3653)); only the render and the walk for what changed ([3744](../../../source/backend/sdl/SdlBackend.jl#L3744)) step a list by a loop of their own. All take the first index, the early stop and the drawn test from `_compute_first_drawn_index`, `_is_past_early_stop` and `_is_drawn_element`, and the place of the content of a viewport from `_compute_viewport_content_place`. The comment at 1427 is the comment of that last function. What each walk repeats is a loop of about six lines around these calls.
  - The web backend visits every node. `_list_nodes` follows `prev` and then `next` until `nothing` ([WebBackend.jl:199](../../../source/backend/web/WebBackend.jl#L199)). The full send, the clipped send, the record of the bounds and the walk for what changed all call it ([325](../../../source/backend/web/WebBackend.jl#L325), [352](../../../source/backend/web/WebBackend.jl#L352), [536](../../../source/backend/web/WebBackend.jl#L536), [482](../../../source/backend/web/WebBackend.jl#L482)). The last one runs in every frame.
  - The PDF writer iterates `canvas.elements` ([PdfWriter.jl:538](../../../source/backend/pdf/PdfWriter.jl#L538)). The iteration of a `ListNode` starts at its left end and goes to its right end ([ListNode.jl:448](../../../source/platform/collection/ListNode.jl#L448)).
  - Two more walks follow "the drawing of a backend" for one point: `hit_element_at` ([GraphicsDocument.jl:953](../../../source/platform/graphics/GraphicsDocument.jl#L953)) and `find_pointer_shape` ([PointerShape.jl:41](../../../source/platform/graphics/PointerShape.jl#L41)). Each has its own steps along a list.
  - The headless test backend reads at most 200 links of a list ([BackendHeadless.jl:49](example/kernel/BackendHeadless.jl#L49)). The workload backend reads every element ([DisplayWorkload.jl:111](../../../source/platform/display/DisplayWorkload.jl#L111)).
  - Where a viewport puts its content, with its transform, is computed in five places (inventory 3).
- **Example:**
  ```julia
  # today, WebBackend.jl: every node, also the rows that no pane shows
  for node in _list_nodes(elements)
      push!(out, _serialize_node(node.value))
  end
  # today, PdfWriter.jl
  for elem in canvas.elements            # a ListNode iterates from its left end to its right end
      paint_elem!(ctx, elem, ox, oy)
  end

  # proposed, once in the graphics slice
  walk_drawn_elements(canvas, origin, edges) do element, origin, edges
      ...                                # only the elements that the edges show
  end
  # the web backend, the PDF writer, the bounds, the hit test and the pointer shape call it;
  # a point is edges of no size
  ```
- **Problem:** In a browser a table of many rows computes and sends every row, and it tests every row again in each frame that it writes. A list with no end does not return. A PDF of one page computes the whole list. The next backend must choose between a copy of the 70 lines of the SDL loop and the same fault. Inside the SDL file, seven walks must stay equal by hand, and the comment at [1427](../../../source/backend/sdl/SdlBackend.jl#L1427) is the only guard. *Corrected by the check:* the guard is the set of shared helpers named above, not a comment; by hand stay the list loop of the render and of the walk for what changed, and the short loop over a vector in each walk.
- **Proposal:** One walk in the graphics slice, above the seam. It takes a canvas, the origin, the edges of a clip and a visitor. It owns the order, the skip of a fence, the first element in view, the early stop, the steps along a list with the rule of `_is_skipped_list_node`, the place of the content of a viewport, and the fault guard of one element. Every reader of a canvas calls it: the three painters, the bounds, the hit test, the pointer shape, the record and the guard of the repaint, and the test backends.
- **What goes away:** `_list_nodes` and the four full walks of the web backend; the seven hand-kept loops in `SdlBackend.jl` become seven visitors; the list loops of `hit_element_at` and `_find_elements_shape!`; `_PAINTED_LINKS`; four of the five copies of the viewport place. Roughly 300 to 400 lines, and one class of fault.
- **What stays:** Every primitive and every painter. The pixel result of SDL, because the walk is the one SDL has now. The rule that a canvas over a list needs a layout (`check_list_canvas`).
- **Risk and open questions:** The SDL walks differ in small ways on purpose (the walk for what changed tests a cell before it reads it). The visitor must be able to say "test, do not read". The render is the hot path, so the walk must not allocate for each element. A PDF with pages wants every row of a finite list: it passes open edges, and a list with no end then needs a stated limit.
- **Related plans:** `plan/pending/cairo-glfw-backend.md` (not started) plans `paint_canvas!` after the PDF writer, so it would inherit the fault. `plan/done/a-list-starts-at-its-first-node-in-view.md` made the rule for SDL. *Added by the check:* `plan/done/a-layout-paints-only-what-the-screen-shows.md`, decision D11 and section 4.10: the owner decided on 2026-11-05 that the web backend does not change "for now" and that no plan for it is written now, and the plan states that the PDF writer draws every page because a PDF shows every page.
- **Check:** confirmed-with-corrections. I opened every cited line. The web facts hold: `_list_nodes` follows `prev` and `next` to `nothing`, and four walks call it, one of them in each frame. The PDF writer iterates every element and only skips the draw of one off the page band (`_on_page`). The graphics slice states the contract that these two readers break: "only a layout with no overlap lets a reader stop at the edges of what it shows" ([GraphicsDocument.jl:681](../../../source/platform/graphics/GraphicsDocument.jl#L681)). The list walk with a stop is written five times with three stop rules: the render, `_collect_drawn_nodes`, `_collect_listnode_dirty!`, `hit_element_at` and `_find_elements_shape!`. The copies differ: by reading, the back walk of the hit test breaks before it tests the node that starts before the point ([GraphicsDocument.jl:978](../../../source/platform/graphics/GraphicsDocument.jl#L978)), and the back walk of the pointer shape tests that node and then breaks ([PointerShape.jl:57](../../../source/platform/graphics/PointerShape.jl#L57)). Corrections: the seven walks inside SDL share more than the report says (see above), so the gain inside SDL is small. The report did not name D11: the web part of the proposal is what the owner put off on 2026-11-05, so the proposal asks the owner to open that again. The PDF difference has a stated reason for a paged file. The proposal loses no feature that I could name. Two conditions: the visitor must allow "test the cell, do not read it", as the report says; and "a stated limit" for a list with no end in a file must not become a cap for a view (settled decision on lazy lists). Value after the check: medium. The next reader of a canvas gets simpler; no domain and no widget does.

### BE-2 The SDL backend holds the policy of the windows, and it writes the screen document while it paints

- **Kind:** wrong-place · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 7 (generic before special), 3 (one way to edit), 9 (outside state enters by an acquire). PAR-SINGLE-WRITER says that a paint reads and no cell changes in a read phase. PAR-STORE-THEN-DRAIN says that data enters a running editor through a store and a drain, never through a direct write.
- **Today:** A `ScreenDocument` holds the `WindowDocument`s that the editor shows. What a window backend must do with them, beyond drawing, is written in `write_to_devices!` of SDL ([5937](../../../source/backend/sdl/SdlBackend.jl#L5937)):
  - `_fit_window_size!` gives a window with a `maximum_size` the size of what it printed. It writes `width` and `height` of the document ([6199](../../../source/backend/sdl/SdlBackend.jl#L6199)).
  - `_adopt_native_position!` writes `x` and `y`, or a new `placement`, when the window manager moved the window ([6237](../../../source/backend/sdl/SdlBackend.jl#L6237)).
  - `_write_display_areas!` writes `display_areas` of the screen ([6215](../../../source/backend/sdl/SdlBackend.jl#L6215)).
  - `_keep_device_geometry_at_new_zoom!` writes the size and the place of each window at a new zoom ([6371](../../../source/backend/sdl/SdlBackend.jl#L6371)).
  - `_queue_display_update!` reports a changed frame, and `_queue_pointer_move!` makes a move for a pointer that stands still ([5994](../../../source/backend/sdl/SdlBackend.jl#L5994), [6007](../../../source/backend/sdl/SdlBackend.jl#L6007)).
  - `_update_pointer_shape!` finds the shape of the pointer in the last canvas ([6049](../../../source/backend/sdl/SdlBackend.jl#L6049)).

  The docstring of `ScreenDocument` states the design: "The backend writes it, as it writes the place and the size of a window" ([ScreenDocument.jl:15](../../../source/platform/screen/ScreenDocument.jl#L15)). A resize by a person takes the other way: it is a `WindowResize` event, and a reader answers an operation ([5694](../../../source/backend/sdl/SdlBackend.jl#L5694)).

  The web backend sends `w.width` and `w.height` as they are ([WebBackend.jl:1030](../../../source/backend/web/WebBackend.jl#L1030)). It fits no window, writes no areas, reports no changed frame and makes no move. A popup opens with its bounds as its size, 640 by 800 by default ([ScreenToScreen.jl:472](../../../source/platform/screen/ScreenToScreen.jl#L472)), so the browser opens a window of that size for a small menu (`client.js:292`). The zoom rule exists three times: SDL, the video backend ([VideoBackend.jl:428](../../../source/backend/video/VideoBackend.jl#L428)) and `setZoom` of the client. The pointer shape is tracked three times ([WebBackend.jl:1128](../../../source/backend/web/WebBackend.jl#L1128), [VideoBackend.jl:443](../../../source/backend/video/VideoBackend.jl#L443)). The video backend picks one window ([612](../../../source/backend/video/VideoBackend.jl#L612)).
- **Example:**
  ```julia
  # today, in write_to_devices!(::SdlBackend, …), inside the paint of the frame
  _fit_window_size!(w, canvas)             # writes w.width and w.height
  _adopt_native_position!(res, w, ratio)   # writes w.x and w.y, or w.placement
  _write_display_areas!(backend, screen)   # writes screen.display_areas

  # proposed: the screen slice computes what is a rule of the document
  width = Cell(@computation fit_extent(content_iomap[].output.w, minimum_size[][1], maximum_size[][1]))
  # and a backend only answers facts and does what it is told
  open_native_window!(backend, id, place, size, style)
  present_window!(backend, id, canvas, rects)
  # the size and the place that the window system grants, and the areas of the displays,
  # come back by one way: as input that a reader of the screen turns into an operation
  ```
- **Problem:** Each rule works on SDL only. Facts of the window system enter the data by two ways: an event and an operation for a resize, a write inside the paint for the fit, the place, the areas and the zoom. The order of these writes inside one frame is kept by comments ([5968](../../../source/backend/sdl/SdlBackend.jl#L5968)). A new window backend must copy about 440 lines of rules that name no SDL concept ([5937–6025](../../../source/backend/sdl/SdlBackend.jl#L5937), [6186–6400](../../../source/backend/sdl/SdlBackend.jl#L6186)). *Corrected by the check:* the two ranges hold 304 lines, and 12 of them name SDL: eleven functions (`SDL_GetWindowPosition`, `SDL_GetWindowID`, `SDL_GetMouseState`, `SDL_GetMouseFocus`, `SDL_GetNumVideoDisplays`, `SDL_GetDisplayUsableBounds`, `SDL_SetWindowSize`, `SDL_SetWindowPosition`, `SDL_SetWindowTitle`, `SDL_ShowWindow`, `SDL_GetWindowFlags`) in `_adopt_native_position!`, `_queue_pointer_move!`, `_find_pointer_window`, `_read_display_areas`, `_update_window_geometry!` and `_show_painted_window!`. The rules that call no SDL function are about 150 lines: the compare of the window ids, `_fit_window_size!` and `_fit_extent`, the areas at the zoom, `_keep_device_geometry_at_new_zoom!` and `_queue_display_update!`.
- **Proposal:** A window host in the screen slice, written once, between the editor loop and a thin native seam.
  - Rules of the document become computations of the screen projection `ScreenToScreen`: the size of a window that fits is the clamp of the size of its printed content. The zoom rule becomes one operation on the screen.
  - The host compares the window ids, asks the backend to open, close, move and resize, runs the search for what changed (BE-3), reports the changed frame, makes the move of a still pointer and finds the pointer shape.
  - The native seam is small: open, close, set geometry, present a canvas in given rectangles, set a cursor shape, poll raw input, and answer the granted geometry and the display areas.
  - Granted geometry and display areas enter as input, by an event or by a feed (the kernel has both: `take_from_devices!` and `Feed`). The owner chooses which. No backend writes a cell.
- **What goes away:** About 440 lines of `SdlBackend.jl` move up and lose their SDL types (*corrected by the check:* about 150 lines; the rest of the two ranges calls SDL and stays). The copies in the web backend (`_make_pointer_message`, `_track_pointer!`, the zoom compare), in the video backend (`_follow_display_zoom!`, `_select_window`, the pointer tracking) and in `client.js` (`setZoom` as a rule) go. The fields `drawn_canvases`, `drawn_zoom`, `display_updates`, `pointer_shape` of `SdlBackend` go to the host.
- **What stays:** Every feature: fit to content, a window that follows the window manager, popups on the right display, zoom that keeps the device size, the pointer shape. All of them then also hold in the browser and for a recording, and the video backend can show every window (kernel audit L09-4).
- **Risk and open questions:** The fit as a computation must not chase itself: the content gets the range from minimum to maximum, as now, and only the window reads the result. `popup-window.md` says that the backend fits the size before the placement reads it; a computed size gives the same order by the reads. A window event for a move would be a new event type, so the owner decides between it and a feed. `open_native_windows!` before the first print stays a call of the backend.
- **Related plans:** `plan/pending/cairo-glfw-backend.md` says "Copy the shape of `write_to_devices!(::SdlBackend, …)`". `plan/tentative/sdl-backend-outputs.md` step 4 moves the window code behind a `WindowOutput` inside SDL; this finding moves the rules above SDL instead. *Added by the check,* three recorded decisions that the report did not name:
  - `plan/done/every-popup-window-is-placed-by-a-function.md`, question Q1, answer of the owner on 2026-11-04: "A. The backend writes the usable areas of the displays into the screen document, as it writes the place and the size of each window. The placement reads them and keeps its window inside, with one helper of the screen slice, so the backend keeps no code that places a popup. The backend writes the fitted size before it reads the place, so the place is correct in the first frame."
  - `plan/done/a-tooltip-fits-its-content.md`, section 2 (done 2026-09-22): "The backend takes the size from the printed canvas … It writes the size back into the `WindowDocument`, as `open_native_windows!` writes back the size a window manager grants."
  - `plan/done/zoom-and-theme-controls.md`, section 4.6 and D24 to D26 (the owner, 2026-10-01): the zoom lives in the `Appearance` and is copied into the `Display`; SDL finds the new ratio when it draws and keeps the device size of each window; the web client applies the zoom. Rejected there: a server that converts the sizes.
- **Check:** weakened. The facts of the code hold: `write_to_devices!` of SDL writes `width`, `height`, `x`, `y`, `placement` and `display_areas` inside the paint, and the video backend writes `width` and `height` the same way ([VideoBackend.jl:434](../../../source/backend/video/VideoBackend.jl#L434)); the web backend fits no window, so a popup with a `maximum_size` opens there at its maximum; `popup-window.md` lists "the web backend writes no areas" under its limits. The text of PAR-SINGLE-WRITER ("a print and a paint read") does not agree with these writes. But the write by the backend is not an accident: it is the mechanism of the three decisions above, two of them answers of the owner from the last seven weeks. The parts of the proposal "no backend writes a cell", "areas and granted geometry enter as input" and "the zoom rule becomes one operation on the screen" go against them, and the first needs a new event type or a feed, a new mechanism that only the owner can add. The three "copies" of the zoom rule are the decided design, and the web copy already takes the way of an event: the client sends its new logical size as a resize. The count of lines was wrong (corrected above). What stays a finding: the fit, the report of a changed frame, the move of a still pointer and the compare of the window ids are rules with no SDL call, about 150 lines, that hold on SDL only; a fit computed in `ScreenToScreen` (`fit_extent` of the printed content between the bounds) would give every backend the fit with no new event. It has one cost that the report does not name: today the fitted size lands in the input window, whose cells the output shares, and a placement reads it there (`context.window.width`, [WindowPlacement.jl:119](../../../source/platform/screen/WindowPlacement.jl#L119)); with a computed size the placement and every other reader of the input window must read the computed cell. Value after the check: medium.

### BE-3 The search for what changed since the last paint is written twice, and its home is the SDL file

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 1 (incremental: only what changed is computed) and 2 (a general step knows no domain). PAR-FRAMEWORKS-SINK.
- **Today:**
  - SDL: lines 2314 to 4256 of `SdlBackend.jl`, about 1 940 lines. They find the rectangles that changed from the validity of the cells, a record of what each graphic was painted with, a signature of each leaf, a guard cell for each canvas, and the moves of a scrolled content ([2998](../../../source/backend/sdl/SdlBackend.jl#L2998), [3319](../../../source/backend/sdl/SdlBackend.jl#L3319), [3894](../../../source/backend/sdl/SdlBackend.jl#L3894), [4210](../../../source/backend/sdl/SdlBackend.jl#L4210)). A search of that range finds no call of SDL. Its one link to SDL is the ink box of a text, `_compute_text_texture_box`, at [2507](../../../source/backend/sdl/SdlBackend.jl#L2507), and the field `res.ratio`. *Added by the check:* three rules of the software renderer of SDL also sit inside the range, as code and not only as a call: `_extend_over_scaled_viewports!` ([2409](../../../source/backend/sdl/SdlBackend.jl#L2409)), the rule of an element that an edge of a move cuts ([3374–3378](../../../source/backend/sdl/SdlBackend.jl#L3374)) and `_is_copyable_move` ([3982](../../../source/backend/sdl/SdlBackend.jl#L3982)). About half of the functions of the range (50 of 98 by a count of the definitions) take `res::SdlWindowResources` as the holder of the record.
  - The state of the search lives in `SdlWindowResources`, the record of a native window ([192](../../../source/backend/sdl/SdlBackend.jl#L192), [164](../../../source/backend/sdl/SdlBackend.jl#L164)). The offscreen renderer has no window, so it builds such a record with null pointers to reuse the search ([5081](../../../source/backend/sdl/SdlBackend.jl#L5081)).
  - Web: a second search of about 170 lines ([WebBackend.jl:400–568](../../../source/backend/web/WebBackend.jl#L400)). It keys a record by `objectid` of the graphic ([467](../../../source/backend/web/WebBackend.jl#L467)). SDL keys by placement, because "one graphic can be drawn at more than one place" ([2352](../../../source/backend/sdl/SdlBackend.jl#L2352)). The web search has no signature, no guard and no move, and it gives one rectangle for a window.
  - The switch `partial_render` and the outline `debug_dirty` are settings of the screen slice that only SDL and the video backend apply ([RenderSettings.jl:17](../../../source/platform/screen/RenderSettings.jl#L17)).
- **Example:**
  ```julia
  # today
  computed, moves = _compute_dirty_change(res::SdlWindowResources, canvas)        # SDL window
  res = SdlWindowResources(C_NULL, off.renderer, :offscreen, UInt32(0), "", …)    # offscreen: a window with no window
  clip = _collect_window_dirty(content, ws.prev_bounds)                           # web: another search

  # proposed, once in the graphics slice
  record = PaintRecord()
  change = compute_canvas_change!(record, canvas, (width, height); get_ink_box = get_text_ink_box)
  change.rects        # what to paint again
  change.moves        # the boxes whose pixels only moved
  change.is_changed   # the frame differs: the host reports a DisplayUpdate
  ```
- **Problem:** The browser gets the faults that SDL already solved: a graphic drawn at two places shares one record, a cell that computed the same value repaints, a scroll sends the whole pane. Whether a frame changed is known on SDL only, so `DisplayUpdate` exists on SDL only (*corrected by the check:* the web backend knows it too, because it sends a window in full or a patch only for a frame that changed; it does not report it, and the second search is not the cause). A window backend with Cairo needs a third search or none.
- **Proposal:** A paint record and one search in the graphics slice. It takes the canvas, the size and, as the one hook, a function that gives the ink box of a text. It answers the rectangles, the moves and whether the frame changed. SDL windows, the SDL offscreen renderer and the web patches use it. The rules of the SDL software renderer stay in SDL as steps after the search: the grid of the texels and the boxes of scaled viewports ([2409](../../../source/backend/sdl/SdlBackend.jl#L2409), [1356](../../../source/backend/sdl/SdlBackend.jl#L1356)).
- **What goes away:** The 170 lines of the web search. The fake window record of the offscreen renderer. About 1 900 lines leave the SDL package and become code that every backend can use. `RenderSettings` then means the same for every backend.
- **What stays:** The partial repaint of SDL with the same counts of work, the copy of moved pixels, the outline of the repainted parts, the patches of the browser.
- **Risk and open questions:** This is the hot path of every frame, and tests count its work (`res.painted.visits`). The move must keep those counts. Two checks in the search read the device ratio ([3985](../../../source/backend/sdl/SdlBackend.jl#L3985)); they become answers of the backend. BE-1 should come first, because the search is a visitor of that walk.
- **Related plans:** `plan/done/a-frame-walks-only-what-changed.md` and five more done plans built the search. `plan/pending/sdl-per-editor-state.md` Part 1 (done) made its switches fields of the backend.
- **Check:** confirmed-with-corrections. I counted again: lines 2314 to 4256 are 1 943 lines, and a search for `SDL_`, `TTF_` and `IMG_` calls in them finds none. The web search is lines 400 to 568, keyed by `objectid` of the graphic ([467](../../../source/backend/web/WebBackend.jl#L467), [517](../../../source/backend/web/WebBackend.jl#L517)), with no signature, no guard and no move, and it answers one rectangle. The offscreen renderer builds an `SdlWindowResources` with `C_NULL` for the window ([5081](../../../source/backend/sdl/SdlBackend.jl#L5081)). No shared helper joins the two searches; they share only `extend_element_bounds!` of the graphics slice. The reason on record for the second search is a circumstance, not a design: `plan/done/web-backend.md` (line 216) says that the worktree of the web backend was older than the search of SDL, so the web backend wrote its own. The later plans of the search do not name the web backend (`a-frame-walks-only-what-changed.md`, `a-repaint-draws-only-what-its-rectangles-touch.md`, `a-long-session-keeps-its-frames-fast.md`, `optimize-rendering-dirty-rect.md`). I found no plan and no document that gives a reason for the home in the SDL file. `plan/pending/cairo-glfw-backend.md` line 257 plans to reuse the bounds helpers of the search, so the need is recorded. Corrections: the range holds three rules of the SDL software renderer as code (added above), so the cut between "search" and "steps of SDL after it" goes through the search and is more work than one hook for the ink box; and the lack of `DisplayUpdate` on the web is not caused by the second search (corrected above). The proposal keeps every feature that I could name. Its use by the web backend needs the walk of BE-1 first, and that is the part of BE-1 that the owner put off (D11 of `a-layout-paints-only-what-the-screen-shows.md`). Value after the check: high.

### BE-4 Each painter decides again what a primitive means

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** 7 (a missing case gets its row in the generic mechanism) and 2 (dispatch on type). `architecture-decisions.md` section 4 chooses multiple dispatch over a type case (*corrected by the check:* section 4 is "Multiple dispatch for projections"; it speaks of projections and names no painter).
- **Today:** Four painters draw the same 11 types: SDL, the server side of the web backend, the browser script, and the PDF writer. Each selects by a chain of `isa` or a `switch` (inventory 3). Each holds its own copy of these decisions:
  - A rectangle with a border and an opaque fill is two fills; with a translucent fill it is a fill and a ring. The rule is in [SdlBackend.jl:1619](../../../source/backend/sdl/SdlBackend.jl#L1619), [PdfWriter.jl:218](../../../source/backend/pdf/PdfWriter.jl#L218) and `client.js:479`. The circle has the same rule with another test (`alpha > 0`, not `alpha >= 1`) in [2019](../../../source/backend/sdl/SdlBackend.jl#L2019), [276](../../../source/backend/pdf/PdfWriter.jl#L276) and `client.js:578`.
  - A text: SDL draws each glyph where `compute_placed_glyphs` of the style slice puts it. The web backend sends offsets and lets the browser choose the fallback font from a stack of families. The PDF writer splits the text into runs of one font and writes the kerning again ([130](../../../source/backend/pdf/PdfWriter.jl#L130), [150](../../../source/backend/pdf/PdfWriter.jl#L150)).
  - The data of an image has three forms, one of them a pointer to an SDL texture. Each painter tests the forms ([2091](../../../source/backend/sdl/SdlBackend.jl#L2091), [306](../../../source/backend/web/WebBackend.jl#L306), [463](../../../source/backend/pdf/PdfWriter.jl#L463)).
  - A colour becomes bytes in four functions. The background of a window is a tuple of bytes and not a `StyleColor` ([ScreenDocument.jl:93](../../../source/platform/screen/ScreenDocument.jl#L93)); the default is written in seven places of the code.

  The arc is the measure. It took four commits on one day: the type with its bounds and its hit test (a247ae4d7), SDL (e6a6f0c21), PDF (431eda471), and the web backend with its script (42878e1e8).
- **Example:**
  ```julia
  # today: the same rule in SdlBackend.jl, PdfWriter.jl and client.js
  if bw > 0 && rect.border_color.alpha > 0
      if rect.color.alpha >= 1  …two fills…  else  …a fill and a ring…  end
  end

  # proposed: the graphics slice says once what a primitive draws
  lower_graphics(rect::GraphicsRect, origin)   # → FillRoundRect(…), StrokeRoundRing(…)
  lower_graphics(text::GraphicsText, origin)   # → GlyphRun(file, size, colour, placed glyphs)
  # and a painter has one method for each of about eight draw commands
  draw_command!(target::PdfPage, command::FillRoundRect) = …
  ```
- **Problem:** A new primitive is a change in five files and two languages. A rule that changes in one painter leaves the picture of a window, of its PDF and of the browser different, and no test compares them. The pointer form of an image puts a type of one backend into the graphics model.
- **Proposal:** A lowering step in the graphics slice: one method for each graphics type that answers a short list of draw commands from a small closed set (fill and stroke of a round rectangle, a disc, a ring, an arc, a polyline with a dash, a polygon, a run of placed glyphs, an image as bytes, and the open and close of a clip with a scale). The decisions sit there: the border rule, the tessellation, the arrowheads, the glyph places and font files, the image form, the colour as bytes. A painter draws the commands by dispatch. The web backend sends the commands as they are, so the browser script loses its rules.
- **What goes away:** Three `isa` chains and one `switch` over 11 types; the border rules in three places; the font run and kerning code of the PDF writer (about 60 lines); the family stack of the web text; the three tests of the image form; three colour converters; about 150 lines of rules in `client.js`. The pointer form of `GraphicsImage.data`, if nothing makes it (I found no maker; `render_canvas` is a stub).
- **What stays:** Every primitive and its look. The rasterizers of SDL (its bands for round corners, its triangles for an arc) stay: they implement a command.
- **Risk and open questions:** A lowering in each frame for each element costs time; a cell for each element, or a lowering inside the painter's method, avoids it. The partial repaint of SDL needs the same pixels in a full and in a partial paint, so the lowering must not depend on the clip. The exact set of commands needs a design of its own. This finding is the least urgent of the first four.
- **Related plans:** `plan/pending/cairo-glfw-backend.md` lists a fifth table "primitive → Cairo". Kernel audit L09-8 (`render_canvas`).
- **Check:** weakened. The facts hold. The border rule of a rectangle is the same text in [SdlBackend.jl:1619](../../../source/backend/sdl/SdlBackend.jl#L1619), [PdfWriter.jl:218](../../../source/backend/pdf/PdfWriter.jl#L218) and `client.js:479`; the circle uses `alpha > 0` in all three; the three image forms are tested in three painters; the four commits of the arc are of 2026-10-06. Nothing gives a reason for the copies. What is weaker is the proposal. (1) The project already has a lighter way for the same fault, and the report lists it under "Examined and sound": a pure function of the graphics slice that each painter calls, as for the spline, the arrowheads and the line before an arrowhead. A function that answers the form of a bordered rectangle or circle, one reader of the image forms and one colour converter remove the copied decisions and add no new layer. (2) A list of draw commands for each element in each frame allocates on the hot path of SDL, and the two ways out that the report names are a cell for each element or a lowering inside the painter, which is the lighter way of point 1. (3) A text as "a run of placed glyphs" must still carry its characters: the PDF writer writes runs of one font with the kerning in a `TJ` array and a `ToUnicode` map so that a copy from the PDF gives the text ([pdf.md](../../../documentation/package/backend/pdf/pdf.md)), and SDL draws a whole text from one cached texture; a glyph list would make both worse unless it keeps the text. (4) Touches a statement of the owner: `plan/done/the-editor-always-answers-the-person.md` (lines 200–205, 2026-10-13) drops the option "the picture becomes plain data", in which a worker "makes a list of draw commands", after the words of the owner "it's up to the backend to copy the state, potentially in an image form, if necessary". That was said about threads, not about painters, so it does not forbid this proposal, but the owner should see it beside it. Value after the check: low for the lowering layer; the lighter way of point 1 is a small change of medium value.

### BE-5 Each backend translates and queues its input by its own rules

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** PAR-BACKEND-SEAM: "A single source of truth governs any cross-backend mapping". Principle 7.
- **Today:** The kernel audit knows that the names of the keys and of the buttons differ (L06-1, L09-1, L09-2). The structural cause is wider than a missing table.
  - Names: three tables map a native code to a name (inventory 4). A fourth table maps a name to a label for a person ([GesturePattern.jl:187](../../../source/kernel/gesture/GesturePattern.jl#L187)). The SDL workload needs the way back, and finds it by a search over about 430 key codes ([SdlWorkload.jl:111](../../../source/backend/sdl/SdlWorkload.jl#L111)). The tables do not name the same thing. SDL names the key: its code is the character of the key with no Shift. The web backend names the character that the key types, as its docstring says ([WebBackend.jl:124](../../../source/backend/web/WebBackend.jl#L124)). So Shift+8 is `:eight` on SDL and `:asterisk` in the browser ([554](../../../source/backend/sdl/SdlBackend.jl#L554), [174](../../../source/backend/web/WebBackend.jl#L174)), and Shift+/ is `:slash` on SDL and `:char` in the browser. The console names no punctuation. For a key that types a character, each native code already holds a character, so only the keys with no character, about 35, need a row for each backend.
  - The `KeyPress` of Return and Tab is made in three ways, and the console makes no `KeyDown` for them. *Corrected by the check:* which key types which character is one function of the event layer, `find_typed_character` ([KeyboardEvent.jl:101](../../../source/kernel/event/KeyboardEvent.jl#L101)), and all three backends call it ([SdlBackend.jl:5714](../../../source/backend/sdl/SdlBackend.jl#L5714), [WebBackend.jl:645](../../../source/backend/web/WebBackend.jl#L645), [ConsoleBackend.jl:531](../../../source/backend/console/ConsoleBackend.jl#L531)). Only the hold of the second event differs. The console has a stated reason for its form: "a terminal reports what was typed, and no key going down" ([ConsoleBackend.jl:527](../../../source/backend/console/ConsoleBackend.jl#L527)).
  - The policy of the queue is in SDL: the newest sample of a run of motion, the limit of idle motion, the merge of wheel events, the modifiers of the last key, Shift with the wheel, the slot of a `DisplayUpdate` and of a change of the system colours ([5539–5609](../../../source/backend/sdl/SdlBackend.jl#L5539), [5778](../../../source/backend/sdl/SdlBackend.jl#L5778)). The browser has another limit in JavaScript and no merge.
- **Example:**
  ```julia
  # today
  sdl_keysym_to_symbol(Int32(46))                   # :period
  convert_web_key_to_symbol(".", "Period", mods)    # :period
  # console: '.' has no name
  _find_sdl_keysym(:period)                         # tries the codes until one answers :period

  # proposed, one table in the event layer, read both ways
  find_key_name('.')         # :period
  find_key_character(:period)  # '.'
  get_key_label(:period)     # "."
  # and one queue above the seam that every backend feeds with raw input
  push_key_down!(queue, window, key, modifiers; is_repeat, time)   # owes the KeyPress of Return and Tab itself
  push_pointer_move!(queue, window, x, y, buttons, modifiers; time)   # keeps the newest, limits idle motion
  ```
- **Problem:** A binding with a punctuation key and Shift fires in one backend and not in another. A rule of the queue that a person feels, such as the limit of idle motion, differs between a window and a browser. Each new backend writes a fourth table and a fourth queue.
- **Proposal:** (a) One table of keys in the event layer: name, character or `nothing`, label. The table states one base, the key or the typed character, for every backend. A backend maps only its keys with no character. (b) One input queue above the seam. A backend pushes raw input into it. The queue names the key, owes the `KeyPress` of Return and Tab, keeps the newest motion, limits idle motion, merges a run of wheel events and keeps the order. `take_from_devices!` of a backend is then "pump the native events into the queue, answer the next".
- **What goes away:** Most of `sdl_keysym_to_symbol` and `convert_web_key_to_symbol`, the label table as a separate list, `_find_sdl_keysym`, the fields `pending_inputs`, `pending_motion` and `last_hover_motion` of `SdlBackend` with about 110 lines of queue code, the limit in `client.js`, and the two copies of the function that puts a new time on an event. *Corrected by the check:* the limit in `client.js` can not go. It works before the socket, so a move that it drops is never sent; a queue on the server sees a move only after it crossed the network.
- **What stays:** Every event type and every name. The coalescing and the limit, now for every backend.
- **Risk and open questions:** The event layer is sealed, so the table needs the owner's word for those files. The SDL queue keeps events in the queue of SDL during a wait; the wait must still look without a read.
- **Related plans:** Kernel audit L06-1, L09-1, L09-2, L09-5, L09-9, L09-12 (file level). `plan/pending/event-layer-reaudit.md` (in progress) is the place for the table. *Corrected by the check:* the re-audit plan names no key table; its questions are about docstrings, `:none` and the modifier predicates. The names of the keys are in `plan/pending/kernel-audit-fixes.md`: L09-1 is done (every backend names `:a` to `:z`, step 1.7); the fix of L06-1 (line 816) says "No new table, function or type goes into the event layer"; the open question N-2 (line 2718) asks the owner whether every key of the base US layout gets a name in every backend; the open question L09-12 (line 2744) asks for one id of "no window".
- **Check:** weakened. The facts hold: two tables from a native code to a name and the console tables, a table of labels in the gesture layer ([GesturePattern.jl:187](../../../source/kernel/gesture/GesturePattern.jl#L187)), a search over 429 codes for the way back ([SdlWorkload.jl:111](../../../source/backend/sdl/SdlWorkload.jl#L111)), and the queue rules in SDL only ([5539–5609](../../../source/backend/sdl/SdlBackend.jl#L5539)). I checked the example: SDL code 56 gives `:eight` with or without Shift, and the browser key `*` gives `:asterisk`; Shift and `/` is `:slash` on SDL and `:char` in the browser. `web.md` says "One table maps both the SDL and the browser keys", and there are two tables. What is new against the plans is one point: the two tables have another base (the key, or the character that it types), and question N-2 does not state a base, so its option B would not end the fault. What is weaker: (1) half of part (a) is the content of N-2 and L09-12, which wait for the owner, and a table in the event layer goes against the scope that the fix of L06-1 wrote down; (2) the Return and Tab rule is already one function, and the console form has a reason (corrected above); (3) part (b) loses the limit of the client if it is taken as written (corrected above). What holds of part (b): the server side of the web backend takes one event for each frame from its channel with no merge of a run of wheel events and no newest-motion rule, which SDL has for a slow frame ([5583–5589](../../../source/backend/sdl/SdlBackend.jl#L5583)). Value after the check: medium, most of it in the one base for the key names.

### BE-6 A service of the desktop has no one shape

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 9 (outside state enters by an acquire on a task), 7, and the settled decision that no registry is global to the process. PAR-OPT-IN-DEPENDENCY.
- **Today:** Five services reach the outside in four ways.
  - The colours of the system: a generic of the backend. The only method is in the SDL package, in a file of 225 lines that calls no SDL function: it runs `gsettings`, `gdbus`, `defaults` or reads the registry ([SystemColorQuery.jl:19](../../../source/backend/sdl/SystemColorQuery.jl#L19)). SDL gives only the moment to ask again, a window that gets the focus ([5667](../../../source/backend/sdl/SdlBackend.jl#L5667)). The answer waits in a slot of the SDL input queue.
  - Open a URL: a generic of the backend that the link slice declares; SDL answers, every other backend answers `false` ([OpenUrlOperation.jl:45](../../../source/platform/link/OpenUrlOperation.jl#L45), [NavigatorPageOpen.jl:212](../../../source/platform/navigator/NavigatorPageOpen.jl#L212)).
  - The clipboard: not a capability of the backend. The clipboard slice runs `xclip`, `xsel`, `wl-paste` or `pbpaste` through two functions kept in process-global `Ref`s, which a test swaps ([Clipboard.jl:51](../../../source/platform/clipboard/Clipboard.jl#L51), [84](../../../source/platform/clipboard/Clipboard.jl#L84), [139](../../../source/platform/clipboard/Clipboard.jl#L139)). The operation that writes has the editor in hand and does not use its backend ([193](../../../source/platform/clipboard/Clipboard.jl#L193)). The list has no tool for Windows.
  - Decode an image and write an image: generics with no backend argument and one method in SDL (kernel audit L09-3).
  - How a caller learns that a capability is missing also has five forms: a default answer, `hasmethod` ([WindowScene.jl:213](../../../source/platform/screen/WindowScene.jl#L213)), `applicable` ([PartPicture.jl:93](../../../source/platform/screen/PartPicture.jl#L93)), a `MethodError`, and a trait (`shows_held_frames`, `get_backend_output`). The generics of a backend are declared in five modules (inventory 1). The stated reason for the second module is that the files of the first are sealed (`packages-compose-by-seams.md`, section 4.1). *Corrected by the check:* two of these forms are decisions of the owner of 2026-09-30 in that plan, not drift. C1: "A seam is a generic function that a low package declares. The package that owns a type adds a method for it", so `open_url!` in the link slice and `send_workload_inputs!` in the display slice are in the decided place. C8: "A caller that is not sure asks `hasmethod` first." Section 4.1 also makes "no method of `get_backend_output`" a meaning of its own (the video backend and the test doubles are no candidates), which is what the `hasmethod` at `WindowScene.jl:213` reads.
- **Example:**
  ```julia
  # today
  open_url!(editor.backend, address)     # link slice; SDL answers
  find_system_colors(editor.backend)     # kernel; SDL answers, with gsettings
  write_os_clipboard!(text)              # clipboard slice; a global function and a shell tool
  set_os_clipboard_backend!(read = …, write = …)   # the test seam, global to the process

  # proposed: one group of services, each with the portable default
  read_clipboard(editor.backend)
  write_clipboard!(editor.backend, text)
  open_url!(editor.backend, address)
  find_system_colors(editor.backend)
  ```
- **Problem:** In a browser on another machine, a copy goes to the clipboard of the server. In a browser, a link to a web address opens nothing and the colours of the system are unknown, though the browser can do the one and knows the other. On Windows the clipboard does nothing, though SDL has a clipboard for every system. A test of the clipboard changes a global of the process, so two editors in one process share it.
- **Proposal:** One declared group of desktop services on the backend, in one interface file, with the list of every generic of a backend beside it. Each service has a default that is the portable code of today, moved to the platform: the shell tools of the clipboard and the query of the system colours are not SDL code. A backend adds a method only where its system is better: SDL its clipboard, the web backend the clipboard, the colour scheme and `window.open` of the browser. The test double answers from its own fields, as `HeadlessBackend` already does for the colours. A read of the clipboard or of the colours stays an acquire on a task.
- **What goes away:** The `Ref`s `_READER` and `_WRITER` and `set_os_clipboard_backend!`; the slot `system_colors_change` of the SDL input queue if the answer comes by a feed; the `hasmethod` and `applicable` tests; the spread of the declarations over five modules.
- **What stays:** Copy and paste with the system, the follow of the system colours, links that open, on every system that has them today, and then also in the browser and on Windows.
- **Risk and open questions:** The chain of clipboard writes is "one for the process, because the system clipboard is one" ([Clipboard.jl:149](../../../source/platform/clipboard/Clipboard.jl#L149)); that stays true for the default and is false for a browser. The declarations in the sealed interface file need the owner's word.
- **Related plans:** `plan/done/one-coherent-color-set.md` section 12.16 chose the query at the focus. Kernel audit L09-3. `plan/pending/packages-compose-by-seams.md` put the two choice seams in the editor layer. Other area: the clipboard, link and settings slices of the platform. *Added by the check:* `plan/done/a-paste-never-holds-the-window.md` made the read of the clipboard an acquire on a task with a time limit, and lists "The clipboard of a web backend. It has no system tool." under "Not in this plan" (line 64). `plan/done/clipboard-os-bridge-and-run-example-wrapper.md` chose the shell tools and the `Ref` seam on 2026-06-29, with the reason "No new dependency".
- **Check:** weakened. The facts hold: `SystemColorQuery.jl` has 225 lines and no call of SDL; the clipboard slice runs shell tools through two process-global `Ref`s that a test swaps ([Clipboard.jl:84](../../../source/platform/clipboard/Clipboard.jl#L84), [139](../../../source/platform/clipboard/Clipboard.jl#L139)); `open_url!` answers `false` on every backend but SDL. What is weaker: (1) "declared in five modules" and the `hasmethod` test follow the decisions C1 and C8 of the owner (corrected above), so "one interface file with every generic of a backend" goes against C1, and those two items leave the list of what goes away. (2) "SDL adds its clipboard" does not fit the acquire on a task as it stands: SDL 2 keeps the clipboard in its video subsystem, whose calls belong to the thread that runs SDL video, and the shell tool is what lets the read run on a task of its own (I did not test an SDL clipboard call from a task); the shell default should stay for SDL. (2b) "The query of the system colours as the default" changes what other backends do: the default of `find_system_colors(::Backend)` is `nothing` in the sealed `BackendDefaults.jl`, a platform package can not replace that method, and a default that answers would make the console and the web backend follow the colours of the machine of the server, which they do not do today. (3) The clipboard and the colours of the browser and a clipboard on Windows are new features, each with new messages to the client, and the review does not ask for new features. (4) "Two editors share the test seam" is true and small: the clipboard of the system is one for the process by nature, and only a test swaps the seam. What holds: the clipboard is the one service of the desktop that does not go through the backend of the editor, so the web backend can not answer it, and a copy in a browser on another machine lands in the clipboard of the server; and the query of the colours is platform code in the SDL package. A `read`/`write` pair of the clipboard slice that dispatches on the backend, with the shell tools as its default method, and the query of the colours as a plain function of a platform slice that the SDL method calls, is a small change that C1 allows and that changes no backend of today. Value after the check: medium for that small form; the wider "one group in one file" has none.

### BE-7 Output to a file has six shapes

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 2 (every projection is bidirectional) and 3 (a test and a person take the same way). PAR-OPT-IN-DEPENDENCY says that file export does not subtype `Backend`; the proposal keeps that.
- **Today:** The focus question was "one seam or two". Today there are six shapes (inventory 5).
  - `write_image(document, projection, filename)` and `write_pdf(document, projection, filename)` hold the same 40 lines: print with free axes, measure, print again when the content is larger than a limit ([SdlBackend.jl:4918–4953](../../../source/backend/sdl/SdlBackend.jl#L4918), [PdfWriter.jl:800–840](../../../source/backend/pdf/PdfWriter.jl#L800)). They already differ: only the image moves content at negative coordinates into view ([4955](../../../source/backend/sdl/SdlBackend.jl#L4955)). *Added by the check:* they also measure by different functions: the image by the ink of SDL at the density (`_get_drawn_content_bounds`, [4867](../../../source/backend/sdl/SdlBackend.jl#L4867)), the PDF by `get_canvas_content_bounds` of the graphics slice; and only the PDF has the branch for pages ([809–823](../../../source/backend/pdf/PdfWriter.jl#L809)). The part that is the same is about 25 lines.
  - Two types are projections with a printer only. They write a file inside `print_document` and have no fit ([4989](../../../source/backend/sdl/SdlBackend.jl#L4989), [859](../../../source/backend/pdf/PdfWriter.jl#L859)). PAR-BIDIRECTIONAL-PROJECTION names them as its exception. Only their own tests use them.
  - `record_video` runs a loop of its own with a stand-in editor of two fields, `_VideoEditor` ([VideoRecording.jl:9](../../../source/backend/video/VideoRecording.jl#L9), [157](../../../source/backend/video/VideoRecording.jl#L157)). `VideoBackend` records through the real loop.
  - The offscreen renderer is a named tuple with 8 exported functions ([4747](../../../source/backend/sdl/SdlBackend.jl#L4747)).
- **Example:**
  ```julia
  # today
  write_image(document, projection, "a.png")      # fits in SdlBackend.jl
  write_pdf(document, projection, "a.pdf")        # fits again in PdfWriter.jl
  ChainingProjection(chain, GraphicsCanvasToPdfFile("a.pdf"))   # a projection that writes a file in its printer

  # proposed: two seams. The Backend seam stays for devices and events.
  # The second seam is a paint target that its package owns:
  canvas = print_canvas_to_fit(document, projection; max_width = 1200, max_height = 800)   # graphics slice, once
  paint_canvas!(ImageFileTarget("a.png"; density = 2), canvas)        # ProjecturedSDL
  paint_canvas!(PdfFileTarget("a.pdf"; paginate = true), canvas)      # ProjecturedPDF
  # write_image and write_pdf stay as the two lines above
  ```
- **Problem:** A rule of the fit must be changed twice. A second package that writes images (the Cairo plan) would overwrite the one method of `write_image`, because the method names no type of its package (L09-3). The picture of a part asks `applicable` to learn whether an image writer is loaded.
- **Proposal:** Two seams. `Backend` is for devices and events. A paint target is a value that its package owns: an image file, a PDF file, an image in memory. One generic paints a canvas onto a target, and one shared function prints a document to fit. The two printer-only projections go, and the rule of bidirectional projections needs no exception. `record_video` becomes a timeline on `VideoBackend`.
- **What goes away:** One copy of the fit (40 lines), the two projection types with their reference maps (about 60 lines), `_VideoEditor` and the loop of `record_video` (about 130 lines), the untyped tuple.
- **What stays:** `write_image`, `write_pdf` and `record_video` as calls with their keywords; pages in a PDF; the frames of a video; the picture of a part.
- **Risk and open questions:** `record_video` takes `operation` entries, and a backend delivers only events; the tentative plan holds this as its decision D6. The picture of a part needs a way to ask for "any image target".
- **Related plans:** `plan/tentative/sdl-backend-outputs.md` proposes outputs as a parameter of `SdlBackend` and a timeline as a wrapper backend (decisions D1 to D9 are open); this finding is the same idea one level higher, where the PDF writer also fits. Kernel audit L09-3, L23-4, L23-5. *Added by the check:* the tentative plan was written on 2026-09-25 from the owner's own words ("How about we parameterize it, what should be the output? Windows, in memory images, file images, file videos"). Its section 3.1 says "PDF stays a projection. It is a vector format with its own renderer" (marked "my view"), and its section 3.4 keeps `write_image` and `GraphicsCanvasToImageFile`. The questions L09-3 (how a package answers `write_image` so that a second one does not overwrite it), L23-5 and L23-4 (playback as a source of input around `run_editor!`) are open questions for the owner in `plan/pending/kernel-audit-fixes.md` (lines 2692, 2788, 2821).
- **Check:** covered-by-plan (`plan/tentative/sdl-backend-outputs.md`, with the open questions L09-3, L23-4 and L23-5 of `plan/pending/kernel-audit-fixes.md`). The facts hold: the two fits, the two printer-only projections with tests as their only callers in this repository, `_VideoEditor` and the loop of `record_video`, and the named tuple of the offscreen renderer. But four of the six shapes are the subject of the tentative plan, which comes from the owner and waits for the decisions D1 to D9, and of the three open questions: the typed outputs for an image file and an image in memory, `record_video` on the real loop, the timeline as a wrapper backend, and the overwrite of `write_image` by a second package. Two parts are new. (1) One shared function for the fit. It is smaller than "the same 40 lines": the shared part is about 25 lines, and the two fits differ in more than the report says: the image measures the ink of SDL at the density (`_get_drawn_content_bounds`, [4867](../../../source/backend/sdl/SdlBackend.jl#L4867)) and moves content at negative coordinates, and the PDF measures `get_canvas_content_bounds` and has a branch for pages. `pdf.md` still says that both use one walk. (2) The PDF writer as a paint target, and the end of the two printer-only projections. PAR-BIDIRECTIONAL-PROJECTION names these two as "an explicit, documented decision", both are exported, documented and tested, and the tentative plan keeps one of them; `write_image` and `write_pdf` give the same file, so no output is lost, but the form "a chain that ends in a file" goes. Value after the check: low beside the plan.

### BE-8 The rule of a held frame is written three times

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 7 (one mechanism) and 8 (reuse an existing view).
- **Today:** A held frame is what the window shows while a code unit runs on another thread. The kernel owns the loop of the hold. Each backend owns the rule and the picture.
  - The rule: keep the keys and the window events for later, drop the pointer input that starts in the hold, keep the release of a press from before, read Escape as the stop once the bar shows, read a close as the close. SDL applies it to raw SDL events ([SdlHeldFrames.jl:108–166](../../../source/backend/sdl/SdlHeldFrames.jl#L108)). The web backend applies it to decoded events ([WebBackend.jl:979](../../../source/backend/web/WebBackend.jl#L979)). The console has a part of it ([ConsoleBackend.jl:205](../../../source/backend/console/ConsoleBackend.jl#L205)).
  - The words: "The code runs", "The code does not stop: it computes.", "Quit without saving" are in three files ([SdlHeldFrames.jl:350](../../../source/backend/sdl/SdlHeldFrames.jl#L350), [WebBackend.jl:1009](../../../source/backend/web/WebBackend.jl#L1009), [ConsoleBackend.jl:216](../../../source/backend/console/ConsoleBackend.jl#L216)). The console has no question to quit.
  - The picture: SDL draws a bar with two buttons by hand, with fixed colours and its own hit test ([268](../../../source/backend/sdl/SdlHeldFrames.jl#L268)). It is the one piece of the interface that no widget draws.
- **Example:**
  ```julia
  # today: three methods of three generics in each backend, each with the rule inside
  run_held_frame!(backend::WebBackend, devices, state)    # filters, decides :stop, formats the words

  # proposed
  answer = filter_held_input!(hold, input)          # the kernel, once: keep, drop, :stop, :close, :quit
  bar = describe_held_frame(state, descriptions)    # once: the words and which controls show
  present_held_frame!(backend, bar)                 # the backend only shows it
  ```
- **Problem:** A change of the rule, such as "the middle button also drops", is three changes. The three bars already say different things. A new backend writes the rule a fourth time.
- **Proposal:** With the input queue of BE-5, the rule is one filter over events in the kernel, beside the loop of the hold. The words and the controls are computed once. A backend only presents: its last picture with the bar over it. The bar can be a canvas that the platform prints before the unit starts, so the widget system draws it.
- **What goes away:** About 60 lines of filter in `SdlHeldFrames.jl`, 50 in `WebBackend.jl`, 30 in `ConsoleBackend.jl`, the words in three files. Three generics become one. (*Corrected by the check:* `prepare_held_frames!` can not go. It is the step that makes, before the unit starts, what a held frame draws; see the check below.)
- **What stays:** The window answers while code runs, the bar, the stop, the quit.
- **Risk and open questions:** SDL keeps the kept events in the queue of SDL and filters them raw, because the unit owns the text state of SDL during the hold; a filter over decoded events must make no text. A bar printed as a canvas needs its glyphs before the unit starts, as SDL makes its textures now. The reason for that limit is the process-global font state of SDL.
- **Related plans:** `plan/done/the-editor-always-answers-the-person.md` and `a-long-evaluation-does-not-hold-the-editor.md` built it. `plan/pending/sdl-per-editor-state.md` Part 2 (deferred) is the cause of the limit. *Added by the check:* `plan/done/the-editor-always-answers-the-person.md`, section 5.5 and decision A1 (the owner, 2026-10-13): "A held frame reads no cell, applies no operation, drains no feed, writes no fault store and makes no text. It reads only plain values", and "a held frame draws only textures that `prepare_held_frames!` made before the unit started, so the unit owns the text state as it owns the cells". Section 5.5 also says that a held frame "leaves the keys and the window events … in the queue of the backend".
- **Check:** weakened. The facts hold: the same rule (keep the keys and the window events, drop the pointer input that starts in the hold, keep the release of an older press, Escape after the bar is the stop, a close is the close) is written over raw SDL events ([SdlHeldFrames.jl:108–166](../../../source/backend/sdl/SdlHeldFrames.jl#L108)) and over decoded events ([WebBackend.jl:979](../../../source/backend/web/WebBackend.jl#L979)), and the three sentences of the bar are in three files. What is weaker: (1) The bar as a canvas that the widget system draws goes against the decision A1 and the rule of section 5.5. During a hold the unit owns the cells and the text state; a canvas is made of cells, and its paint reads them and makes text. SDL makes the textures of the words and of the digits 0 to 9 before the unit ([SdlHeldFrames.jl:350](../../../source/backend/sdl/SdlHeldFrames.jl#L350)) for this reason, so the hand-drawn bar is the decided design and not a missing reuse. (2) So three generics can not become one: the prepare step and the end step stay. (3) One filter in the kernel needs decoded events in a queue above the seam, which is BE-5 part (b); without it SDL keeps the events in its own queue, as section 5.5 says. (4) The console difference has a reason: a terminal has no close of a window, so it never answers `:close`, and the kernel asks the question to quit only after a close ([ConsoleBackend.jl:161](../../../source/backend/console/ConsoleBackend.jl#L161), [HeldFrames.jl:174–181](../../../source/kernel/editor/HeldFrames.jl#L174)). What holds with no other change: one function that makes the words of the bar from the `HeldFrameState` and the descriptions, about 10 lines in each of three files, and, when BE-5 (b) exists, the filter. Value after the check: low.

### BE-9 The device layer carries one value that is used

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 11 (design as from scratch) and "an API has no more concepts than its features need".
- **Today:** The kernel has three device types. No code in `source/` or `example/` reads `Keyboard.layout`, `Mouse.button_count` or `Mouse.has_scroll_wheel` ([Keyboard.jl:9](../../../source/kernel/device/Keyboard.jl#L9), [Mouse.jl:10](../../../source/kernel/device/Mouse.jl#L10)). The editor holds a `Vector{Device}` and gives it to seven generics of the seam. The only use is a search for the `Display` by its type, in four places ([SdlBackend.jl:6456](../../../source/backend/sdl/SdlBackend.jl#L6456), [VideoBackend.jl:247](../../../source/backend/video/VideoBackend.jl#L247), [WebBackend.jl:1144](../../../source/backend/web/WebBackend.jl#L1144), [AppearanceOperations.jl:69](../../../source/platform/appearance/AppearanceOperations.jl#L69)). The zoom of the editor is a plain field of that `Display`, not a cell. So three backends keep "the zoom of the last frame" to see a change ([6373](../../../source/backend/sdl/SdlBackend.jl#L6373), [1076](../../../source/backend/web/WebBackend.jl#L1076), [430](../../../source/backend/video/VideoBackend.jl#L430)).
- **Example:**
  ```julia
  # today
  Editor(document, projection; backend, devices = Device[Display(), Keyboard(), Mouse()])
  write_to_devices!(backend, devices, screen)     # SDL does not read `devices`; the web backend searches it

  # proposed
  Editor(document, projection; backend, display = Display())
  write_to_devices!(backend, screen)
  ```
- **Problem:** Each generic of the seam has an argument that tells a new author nothing. A device type invites a use that does not exist.
- **Proposal:** The editor holds one `Display`. `configure_devices!` gives it to the backend, which keeps it, as SDL and the video backend already do. The other generics lose the argument. `Keyboard` and `Mouse` go until a feature reads them.
- **What goes away:** Two types, one argument of seven generics, four searches by type.
- **What stays:** The density, the zoom of one editor, the size of the display.
- **Risk and open questions:** The files are sealed. The device audit kept the three types on purpose and listed the argument under "Not in this plan"; the owner has not decided it. Projects that depend on this one name `Device[…]` in their start code. *Added by the check:* the fields of `Mouse` and `Keyboard` have a reason on record from the owner. `plan/done/device-physical-properties.md`, "Rationale (from the user)": "Mouse button count & scroll-wheel support → later feeds how events map to operations. Keyboard layout → later matters for the same event→operation mapping." Item 4 of `plan/done/device-layer-audit.md`, which the owner accepted on 2026-09-25, says that the two types stay mutable "because a backend fills a device in place". The zoom as a plain field of the `Display` that each backend follows when it draws is D24 and section 4.6 of `plan/done/zoom-and-theme-controls.md` (the owner, 2026-10-01).
- **Related plans:** Kernel audit L09-11 and L07-2 (file level). `plan/done/device-layer-audit.md`. *Added by the check:* both audit items are open questions for the owner in `plan/pending/kernel-audit-fixes.md`, each with its options and a recommendation: L09-11 at line 1956 (remove the `devices` argument of the three generics of a frame, state its use, or state that a backend may ignore it) and L07-2 at line 2683 (the size of the display as a field of the `Display` or only as the answer of the backend).
- **Check:** covered-by-plan (`plan/pending/kernel-audit-fixes.md`, questions L09-11 and L07-2), and one part goes against a reason of the owner. The facts hold: no code in `source/` or `example/` reads `Keyboard.layout`, `Mouse.button_count` or `Mouse.has_scroll_wheel` (only two tests name them); seven generics take `devices`; four places search it for the `Display`. The removal of the argument is the option A of the open question L09-11, so the owner already has it as a question to answer. The report adds one fact to that question: its text says that no backend reads the argument of a frame, and the web backend now reads the zoom from it in each frame ([WebBackend.jl:1075](../../../source/backend/web/WebBackend.jl#L1075), [1142](../../../source/backend/web/WebBackend.jl#L1142)), so option A now also needs `configure_devices!` in the web backend. The removal of `Keyboard` and `Mouse` goes against the reason that the owner gave for their fields (added above): they are there for a later use, in the owner's words. "The zoom is a plain field, so three backends keep the zoom of the last frame" describes the decided design of the zoom, not a fault. Value after the check: low, as the report says; the new part is the one fact for L09-11.

## Covered by plans

- The process-global state of SDL (open fonts, text textures, the one SDL session and event queue, a quit that stops every editor): `plan/pending/sdl-per-editor-state.md` Part 2, deferred by the owner. Two globals are not in its list: `_LAST_PIXELS_PER_WINDOW_UNIT` and the table `_HELD_FRAMES`.
- Three ways to choose a backend when the caller names none (`make_default_backend` of the kernel, `default_backend` of the application slice with an order of preference, the table `PROJECTURED_BACKENDS` of the builder): `plan/pending/packages-compose-by-seams.md` step 10, open, removes the last two.
- Three interpreters of one timeline format (`play_live!`, `VideoBackend`, `record_video`) and the second loop of the playback: kernel audit L23-1, L23-4, L23-5; `plan/tentative/sdl-backend-outputs.md` decisions D5 to D7.
- The backends name keys and buttons differently: kernel audit L06-1, L09-1, L09-2. BE-5 gives the structural cause.
- The output generics dispatch on no type of their package; `render_canvas` is a stub; the video backend shows one window; the console turns Home into a chord; `_wait_for_gate` is copied; the `devices` argument is not read: kernel audit L09-3, L09-8, L09-4, L09-5, L09-12, L09-11.
- A second interactive window backend: `plan/pending/cairo-glfw-backend.md`, not started, with paths of an older layout. BE-1 to BE-4 change what it must write.
- Outputs of SDL as a list (window, image in memory, image file, video file): `plan/tentative/sdl-backend-outputs.md`, tentative.

## Examined and sound

- The measure of text is above the seam: every projection measures with a `TextMeasure` of the style slice, and no backend measures. Right as it is.
- The geometry of a spline, of an arrowhead and of the line before an arrowhead is one set of functions in the graphics slice ([GraphicsDocument.jl:490](../../../source/platform/graphics/GraphicsDocument.jl#L490), [573](../../../source/platform/graphics/GraphicsDocument.jl#L573), [600](../../../source/platform/graphics/GraphicsDocument.jl#L600)); the three painters call it.
- The kernel half of the seam: the interface file declares only, each default is a legal answer, the layer imports nothing.
- No backend makes a click, a chord or a dwell; the gesture tracking projection does, once. Escape is an ordinary key in every backend.
- The wait and the wake differ for a good reason: SDL must pump its queue on its own thread, the web and the console wait on a Julia event.
- `VideoBackend` as a `Backend` that plays a timeline through the real loop is the right shape; it is `record_video` that repeats the loop.
- File export does not subtype `Backend` (PAR-OPT-IN-DEPENDENCY). BE-7 keeps it.
- The console draws a `TextBlock` and not a screen: decision C3 of `packages-compose-by-seams.md` ("a backend says what it draws"). The cost is the 64-line `WindowInputUnwrappingProjection` and the window id `:console`.
- The web, console and video backends keep all their state on the instance.
- The density of the display is a fact of the machine, found once for the process; the rule PAR-PER-EDITOR-STATE allows it.
- The rules of the SDL software renderer (the grid of the texels, a clip that is set at scale 1, the boxes of scaled viewports) are SDL knowledge and belong in the SDL package.
- The windows follow the screen document, and no call opens or closes a window: the right model. BE-2 moves only where the rule is written.

## Check of the report

A second reader checked each finding against the code at commit 3a9b4fae4, the documents under `documentation/` and the plans under `plan/`. The check ran no Julia and no test. It opened the cited lines of every finding; of the inventory tables it opened only the rows that a finding uses. The line numbers of the report were right in every place that the check opened.

| Id | Verdict | Value in the report | Value after the check |
| --- | --- | --- | --- |
| BE-1 | confirmed-with-corrections | high | medium |
| BE-2 | weakened | high | medium |
| BE-3 | confirmed-with-corrections | high | high |
| BE-4 | weakened | medium | low |
| BE-5 | weakened | medium | medium |
| BE-6 | weakened | medium | medium, for the small form only |
| BE-7 | covered-by-plan | medium | low |
| BE-8 | weakened | medium | low |
| BE-9 | covered-by-plan | low | low |

Recorded decisions that a finding touches and that the report did not name:

| Decision | Where | Finding |
| --- | --- | --- |
| The web backend does not skip what is off the screen "for now", and no plan for it is written now (the owner, 2026-11-05) | `plan/done/a-layout-paints-only-what-the-screen-shows.md`, D11 | BE-1, BE-3 |
| The backend writes the areas of the displays into the screen document, as it writes the place and the size of each window (the owner, 2026-11-04) | `plan/done/every-popup-window-is-placed-by-a-function.md`, Q1 | BE-2 |
| The backend takes the size of a window that fits from the printed canvas and writes it back | `plan/done/a-tooltip-fits-its-content.md`, section 2 | BE-2 |
| The zoom lives in the `Appearance` and is copied into the `Display`; each backend follows it when it draws; the web client applies it (the owner, 2026-10-01) | `plan/done/zoom-and-theme-controls.md`, D24 to D26 | BE-2, BE-9 |
| For the threads of a frame, a worker that makes "a list of draw commands" was dropped: the owner said "it's up to the backend to copy the state, potentially in an image form, if necessary" (2026-10-13), and the plan concludes that the option "is not an option of the architecture" | `plan/done/the-editor-always-answers-the-person.md`, section 4, option C | BE-4 |
| No new table, function or type goes into the event layer for the key names | `plan/pending/kernel-audit-fixes.md`, the fix of L06-1 | BE-5 |
| A seam is declared by a low package; a caller that is not sure asks `hasmethod` (the owner, 2026-09-30) | `plan/pending/packages-compose-by-seams.md`, C1 and C8 | BE-6 |
| A held frame reads no cell and makes no text; it draws textures made before the unit (the owner, 2026-10-13) | `plan/done/the-editor-always-answers-the-person.md`, section 5.5 and A1 | BE-8 |
| The fields of `Mouse` and `Keyboard` are there for a later map from events to operations (the owner) | `plan/done/device-physical-properties.md`, "Rationale" | BE-9 |

What goes to the owner as a proposal after the check, in the order of its value:

1. BE-3, one search for what changed, above the seam. It depends on the walk of BE-1.
2. BE-1, one walk of a canvas in the graphics slice. Its web part asks to open D11 again.
3. BE-2, only the part that needs no new mechanism: the fit of a window as a computation of the screen projection, and the rules with no SDL call moved out of the SDL file.
4. BE-5, one base for the name of a key (the key or the typed character) as an addition to the open question N-2; the merge of wheel and motion events on the server side of the web backend.
5. BE-6, the small form: the clipboard read and write dispatch on the backend with the shell tools as the default.
