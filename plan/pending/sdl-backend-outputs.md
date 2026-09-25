# The SDL backend draws to a list of outputs: windows, images and videos

> **Status: tentative.** Written 2026-09-25. No step is started. The decisions
> in section 5 are open, and the owner makes them. Each name in this plan is a
> proposal. A recommendation marked "my view" is a recommendation, not a
> decision.

## 1. The request

The owner asked about the categories of the folders in `source/`, and then:

> Hmm, the image output should be its own package.
>
> Should playback also be a backend?
>
> How about headless backend?

> We could also have a backend which draws in memory image not a file image.

> Maybe it these depend on sdl they should be part of that package.
>
> How about we parameterize it, what should be the output? Windows, in memory
> images, file images, file videos, etc.

> Write this into a tentative plan

## 2. What exists

### 2.1 The backends

Five types are subtypes of `Backend`:

| Type | Place | Output | Input |
| --- | --- | --- | --- |
| `ConsoleBackend` | `source/console/Console.jl:4` | terminal | terminal |
| `SdlBackend` | `source/sdl/Sdl.jl:157` | native windows | SDL events |
| `WebBackend` | `source/web/Web.jl:45` | browser | browser |
| `VideoBackend` | `source/video/VideoBackend.jl:55` | one PNG file for each frame, then `ffmpeg` | a timeline |
| `HeadlessBackend` | `example/kernel/BackendHeadless.jl:14` | a log of the documents, no pixels | a queue that the caller fills |

`HeadlessBackend` is a test double. It is in the example package on purpose, so
that no double gets into a production build. Its text measurement is a stub:
8 × 16 pixels for each character. 18 test files use it.

PDF is not a backend. It is the projection `GraphicsCanvasToPdfFile` in
`source/pdf/Pdf.jl:810`.

### 2.2 The paths that draw offscreen

All of them use the SDL software renderer in `source/sdl/Sdl.jl`
(`_open_offscreen_renderer`, `_render_canvas_offscreen!`,
`_offscreen_output_surface`, `_close_offscreen_renderer`).

| Path | Place | What it does |
| --- | --- | --- |
| `write_image(canvas, filename)` | `Sdl.jl:2334` | draws one canvas, then writes `.png` (with `IMG_SavePNG`) or `.bmp` |
| `write_image(document, projection, filename)` | `Sdl.jl:2404` | prints the document, then calls the method above |
| `GraphicsCanvasToImageFile` | `Sdl.jl` | the same output as a projection |
| `_emit_frames!` | `Sdl.jl:2527` | draws one canvas and writes it as N numbered PNG files |
| `record_video` | `source/video/Video.jl:69` | runs `read_intent`, `evaluate_operation` and `print_document` itself, without the editor loop, then `ffmpeg` |
| `VideoBackend` | `source/video/VideoBackend.jl` | runs the real editor loop (`run_editor!`) with a timeline, then `ffmpeg` |
| `render_canvas` | declared at `source/kernel/backend/BackendInterface.jl:148`, method at `Sdl.jl:2215` | declared as "rasterize a graphics-canvas document to an image document"; see 2.4 |
| `decode_image` | declared at `BackendInterface.jl:156`, method at `Sdl.jl:3322` | reads an image file into RGBA bytes: `(data::Vector{UInt8}, width, height)` |

### 2.3 The paths that script input

A timeline entry is `(event = …, hold = …)`, `(operation = …, hold = …)` or
`(await = predicate, hold = …)`. Three places read a timeline, and each place
has its own copy of the timing code:

| Place | `event` | `operation` | `await` | Clock |
| --- | --- | --- | --- | --- |
| `play_live!`, `source/kernel/playback/Playback.jl` | yes | yes | yes | wall clock |
| `VideoBackend` | yes | no | yes | wall clock, or video time with `video_time = true` |
| `record_video` | yes | yes | yes | video time |

An `operation` entry goes directly to the evaluator and does not go through the
reader. A backend can deliver only events. So a backend can not deliver an
`operation` entry now.

`VideoBackend` holds back the next entry until `write_to_devices` draws a frame
(the field `awaiting_render`). This makes sure that each entry shows in its own
frame. `play_live!` applies one entry in each frame for the same reason.

### 2.4 The faults found

1. The only method of `render_canvas`, `render_sdl_canvas` at `Sdl.jl:2208`,
   is a stub. It gives back `GraphicsImage(0, 0, 0, 0, nothing)`.
2. `GraphicsCanvasToGraphicsImage` in `source/graphics/GraphicsCaching.jl`
   "will eventually rasterize". Now it draws coloured placeholder boxes.
3. No code in `source/`, `test/` or `example/` reads rendered pixels into
   memory. A pixel check now needs ad hoc code that reads the SDL texture of a
   live window.
4. `VideoBackend` draws only the window `window_id`, or else the first window
   (`VideoBackend.jl:290`). A tooltip and a menu each have their own window
   (PAR-MANY-WINDOWS), so a video does not show them.
5. A video writes one PNG file for each frame to `frames_dir`, and `ffmpeg`
   reads the files after the recording.
6. The timing of a timeline exists three times (2.3).
7. Side finding: `source/style/TrueType.jl` has its header comment two times.

### 2.5 The callers

| Name | Files that use it |
| --- | --- |
| `write_image` | `example/kernel/Harness.jl`, `test/projectured/ProjecturedSuite.jl`, `test/sdl/SdlSuite.jl`, `test/sdl/projection/GraphicsToFileTest.jl`, `test/sdl/backend/DeviceConfigTest.jl` |
| `GraphicsCanvasToImageFile` | `test/projectured/ProjecturedSuite.jl`, `test/sdl/projection/GraphicsToFileTest.jl` |
| `record_video` | `example/sdl/LiveExamples.jl`, `example/kernel/Harness.jl`, `example/projectured/Gallery.jl`, `test/projectured/ProjecturedSuite.jl`, `test/video/VideoSuite.jl`, `test/video/editor/VideoTest.jl` |
| `VideoBackend` | `example/sdl/ApplicationVideo.jl` |
| `play_live!` | `example/sdl/LiveExamples.jl` (`play_live_example`) |
| `decode_image` | `source/markdown/MarkdownToSyntax.jl`, `source/book/BookToSyntax.jl`, `source/rst/RstToSyntax.jl`, `example/substrate/TextDocumentExample.jl` |

### 2.6 The package boundaries

- `ProjecturedSdl` depends on `SDL2_jll` and `SimpleDirectMediaLayer`. It
  already has SDL2_image, which `IMG_SavePNG` needs.
- `ProjecturedVideo` depends on `FFMPEG` and `ProjecturedSdl`.
- `documentation/rule/package-rules.md` gives each third-party dependency its
  own package. If `FFMPEG` goes into `ProjecturedSdl`, each SDL user loads it.

### 2.7 The sealed files

These kernel files are sealed (🔒 in `SEALING.md`): `backend/BackendModule.jl`,
`backend/BackendInterface.jl`, `backend/BackendDefaults.jl`,
`device/DeviceInterface.jl`, `device/Display.jl`. The design below needs no
change to them. A new method for `render_canvas` goes into `Sdl.jl`. If a step
needs a new declaration or a new docstring in a sealed file, stop and ask the
owner first.

`playback/Playback.jl` and `editor/EditorLoop.jl` are not sealed.
`get_frame_clock_time`, which `VideoBackend` overrides, is declared at
`source/kernel/editor/EditorLoop.jl:101`.

### 2.8 The related plans

- `plan/pending/sdl-per-editor-state.md`. Part 1 is done. Part 2 is deferred:
  every backend in one process shares the SDL session. `_font_cache` is also
  module-level. A window output and an image output in one process share both.
- `plan/pending/cairo-glfw-backend.md`. Not started. It is a rasterizer without
  SDL. It is the other answer to decision D2.
- `plan/pending/feature-video-screenplays.md`. It uses `record_video`,
  `LiveExample`, `record_live_example` and `play_live_example`. A change to
  these names or to their behaviour changes that plan.

## 3. The design (tentative)

### 3.1 The outputs are a parameter of `SdlBackend`

`SdlBackend` gets a list of outputs, for example
`SdlBackend(outputs = [WindowOutput()])`. The default is `[WindowOutput()]`, so
`SdlBackend()` keeps its behaviour.

| Output | Package | Renderer | Where the `Display` comes from |
| --- | --- | --- | --- |
| `WindowOutput` | `sdl` | GPU renderer, one for each native window | the operating system |
| `MemoryImageOutput` | `sdl` | software renderer, offscreen | its parameters: width, height, scale |
| `ImageFileOutput` | `sdl` | memory image, then PNG or BMP encoding | its parameters |
| `VideoFileOutput` | `video` | memory frames, then the `FFMPEG` encoder | its parameters |

The reasons:

- Memory images and image files need only SDL and SDL2_image, which `sdl`
  already loads.
- Images and windows use the same SDL_ttf glyph rasterizer, so an image shows
  the same text as a window.
- The outputs are subtypes of one abstract type (proposal: `SdlOutput`). So
  `video` adds `VideoFileOutput` and does not put `FFMPEG` into `sdl`.
- With a list, a live window and a recording can run at the same time. Nothing
  in the code can do that now.

These parts stay outside this parameter (my view):

- PDF stays a projection. It is a vector format with its own renderer.
- `web` and `console` keep their own backends. The parameter belongs to `sdl`,
  not to the kernel.
- `HeadlessBackend` stays the test double with no dependencies.
- The Cairo plan stays a separate plan.

### 3.2 The input is a second axis

An offscreen output has no keyboard and no mouse. So the input is a separate
choice:

- live SDL events, which need a window
- a timeline: the playback
- a queue that the caller fills, as in `HeadlessBackend`

The existing tools become combinations:

| Outputs | Input | What it is |
| --- | --- | --- |
| window | live | the editor now |
| window | timeline | `play_live!` now |
| video file | timeline | `VideoBackend` now |
| memory image | queue | a pixel test without a display (new) |
| window + video file | live | a recording of a real session (new) |

There are two forms for the input (decision D5):

- **A parameter of `SdlBackend`**, next to `outputs`.
- **A wrapper backend**, for example `TimelineBackend(inner, timeline)`. It
  merges the timeline into the input of `inner` and passes all output to
  `inner`. A timeline is not specific to SDL, so the wrapper can be in the
  `playback` layer of the kernel and can also work with `web`.

My view: the wrapper. It removes two of the three copies of the timing code,
and every `write_to_devices` call goes through it, so it sees each frame.

### 3.3 The places where input and output depend on each other

1. **The frame signal.** The timeline holds back the next entry until an output
   draws a frame (2.3).
2. **The pointer.** `VideoBackend` draws the mouse pointer into each frame, at
   the position of the last mouse event of the timeline. A video output needs
   the pointer position from the input. With live input, it comes from SDL.
3. **The frame clock.** With `video_time = true`, `VideoBackend` overrides
   `get_frame_clock_time`. So the clock of the editor follows the frames of the
   video output.

### 3.4 What happens to the existing names

| Name | After this plan |
| --- | --- |
| `write_image` (both methods) | stays, with the same signatures. It makes a backend with `ImageFileOutput`, prints one time, and stops. |
| `GraphicsCanvasToImageFile` | stays. It uses the same code as `ImageFileOutput`. |
| `render_canvas` | gets a real method on top of `MemoryImageOutput`. |
| `VideoBackend` | becomes the timeline input with `VideoFileOutput`. It can stay as a name for that combination. |
| `play_live!` | becomes the timeline input with `WindowOutput`. Its `operation` entries depend on D6. |
| `record_video` | depends on D7. |
| `_emit_frames!` | goes away, if D8 sends frames to `ffmpeg` without files. |

## 4. The steps (tentative)

Each step is one commit on a branch in its own worktree, and each step has its
own test. The steps start only after the owner asks for the work.

0. [ ] The owner makes the decisions D1 to D9. Record them in section 5.
1. [ ] **The baseline.** On `main`, run `test_sdl()`, `test_video()` and
   `test_kernel()`. Record the counts. Record the pixel hash of one live window
   (the method in the note "live window pixel compare").
2. [ ] **`MemoryImageOutput` in `sdl`.** It draws the screen offscreen into an
   RGBA buffer. A function gives back the buffer. `render_canvas` gets a real
   method on top of it. Test: draw a small canvas, then check the colour of
   pixels at known coordinates.
3. [ ] **`ImageFileOutput` in `sdl`.** It is the memory image plus the PNG or
   BMP encoder. `write_image` and `GraphicsCanvasToImageFile` use it. Test:
   `test/sdl/projection/GraphicsToFileTest.jl` passes with no change.
4. [ ] **`WindowOutput` in `sdl`.** Move the window code behind this output
   without a change in behaviour: dirty rectangles, buffer age, supersampling
   and window placement stay the same. Test: `test_sdl()`, and the pixel hash of
   the live window is equal to the baseline. Frame time: measure only with an
   idle machine and the approval of the owner.
5. [ ] **The timeline input.** Use the form from D5. Take the timing code from
   `VideoBackend`, with the frame signal and the pointer position (3.3).
   `play_live!` uses it. Test: a timeline with 3 events on a memory image output
   gives 3 frames, one for each entry.
6. [ ] **`VideoFileOutput` in `video`.** `VideoBackend` becomes the timeline
   input with this output. Test: `test/video/editor/VideoTest.jl` passes.
7. [ ] **`record_video`.** Do what D7 says.
8. [ ] **The documents.** Update `documentation/package/sdl/sdl.md`,
   `documentation/package/video/video.md`,
   `documentation/package/kernel/devices-and-backends.md`, and the backend
   group in `documentation/package/README.md`. Update
   `plan/pending/feature-video-screenplays.md` if a name that it uses changed.

## 5. The open decisions

- **D1. A screen with many windows, drawn offscreen.** One image for each
  window, or one image of the whole screen, with each window at its position.
  One image of the screen shows tooltips and menus in a video (2.4, fault 4).
- **D2. The rasterizer.** SDL, as this plan says, or a rasterizer without SDL
  (`plan/pending/cairo-glfw-backend.md`). My view: SDL first, because the glyphs
  are then the same as in the windows.
- **D3. Window and recording at the same time.** The window draws on the GPU. A
  recording needs the pixels in memory. There are two ways: read the pixels back
  from the GPU for each frame, or draw each frame a second time in software.
  Each way costs frame time.
- **D4. The pixel type.** My view: RGBA bytes with a width and a height, the
  format that `decode_image` gives back now. Then a decoded image and a
  rendered image are the same kind of value.
- **D5. The form of the input.** A parameter of `SdlBackend`, or a wrapper
  backend (3.2). My view: the wrapper.
- **D6. The `operation` entries.** A backend can deliver only events. The
  choices are a new path from the backend to the evaluator, or a timeline of
  events only. A new path is a new mechanism, so the owner decides it before
  anybody writes it.
- **D7. `record_video`.** Keep it as it is, or rebuild it on the real editor
  loop with the timeline input and `VideoFileOutput`. A rebuild needs D6,
  because `record_video` accepts `operation` entries.
- **D8. The frame files.** Keep one PNG file for each frame on disk, or send the
  frames to the standard input of `ffmpeg`.
- **D9. The names.** Each name in this plan is a proposal: `SdlOutput`,
  `WindowOutput`, `MemoryImageOutput`, `ImageFileOutput`, `VideoFileOutput`,
  `TimelineBackend`. Check them against
  `documentation/rule/naming-rules.md` before step 2.

## 6. The risks

- **The shared SDL session.** Part 2 of `sdl-per-editor-state.md` is deferred.
  A window output and an image output in one process share `SDL_Init` and
  `_font_cache`. Step 2 must not make that worse.
- **GPU pixels against software pixels.** The window uses the GPU renderer and
  a supersampled target texture. An image uses the software renderer. The two
  can differ in anti-aliasing, so an image test can not always equal the window
  pixel for pixel.
- **The hot path.** Step 4 moves the code that draws each frame of each window.
  A change in behaviour there shows in every session. The pixel hash and the
  frame time before and after are the checks.
- **Another plan uses the video names.** `feature-video-screenplays.md` uses
  `record_video` and the live examples. Step 7 and D7 change what that plan
  can use.
