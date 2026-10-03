# Video recording

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [sdl.md](../sdl/sdl.md), [editor.md](../../kernel/editor.md)

`ProjecturedVideo` records a scripted editing session as an `.mp4` file, with no window. It is a file export and not a `Backend`: it runs the session through a small copy of the editor cycle and encodes the frames with `ffmpeg`. This document says how a timeline becomes frames, why the video is the same on every run, and where the recorder differs from the editor.

## How it works

### One call

```julia
record_video(document, projection, gestures, filename;
             fps = 30, width = 1200, height = 800, initial_hold = 0.5, final_hold = initial_hold,
             initial_selection = nothing, wait_for = nothing, wait_timeout = 5.0,
             supersample = 2, density = 1, clock = Clock())
```

`record_video` is a generic of `BackendModule` in the kernel, beside `write_image`; this package adds its one method, and the umbrella `Projectured` exports the name. `filename` must end in `.mp4`. The projection must print a `GraphicsCanvas`, not a `ScreenDocument`, because the recorder has no window; for any other output the call raises an error. Each frame is laid out at `width` by `height`, so the coordinates of a mouse event match the picture.

### The timeline

`gestures` is a vector of named tuples. Each one has a `hold` in seconds:

| Entry | What the recorder does |
| --- | --- |
| `(event = e, hold = h)` | calls `read_intent(projection, iomap, e)` and evaluates the operation that it returns |
| `(operation = op, hold = h)` | evaluates `op`, or `op(document)` when `op` is a function; for an action that no single event makes |
| `(await = predicate, hold = h)` | emits one frame and yields, again and again, until `predicate(document)` returns `true` or `h` seconds of wall-clock time pass |

The event goes straight to the reader, with no `WindowInput` and no gesture tracking projection. So a click is a `MouseClick` entry; a `MouseDown` and a `MouseUp` do not make one. `initial_selection` sets the selection before the first frame, and `nothing` clears it. A `KeyPress` edits only when something is selected, so a typing demo needs an `initial_selection` or a first `MouseClick`. `make_typein_gestures(text)` in `example/kernel/Harness.jl` makes the `KeyPress` entries of a text, and `timed_await(predicate)` in `example/backend/sdl/LiveExamples.jl` makes an `await` entry.

### Video time

An entry emits `round(hold * fps)` frames. The recorder counts time in frames and not in wall-clock time, so the video is the same on a slow and on a fast machine. `initial_hold` and `final_hold` add still frames at the two ends. The printer context carries `clock`, and the recorder sets it to `frame / fps` before each frame, so a document that reads the clock moves in video time.

### Print once

The recorder prints the projection once and renders the same canvas for each frame. A render reads the reactive cells, so an edit, a typed character or a streamed reply shows in the next frame with no new print. A print for each frame would build a new graphics tree for each frame. The recorder prints again only when an operation replaces the whole document: it evaluates the operation on `_VideoEditor`, which holds only `document` and `iomap`, and compares the document afterwards.

### Work in another task

The loop over the entries does not yield, so a task that a gesture started, such as the streamed reply of the assistant, does not run between the entries. An `await` entry lets that task run and records its progress frame by frame. `wait_for` is a function with no argument: after the last entry the recorder yields until it returns `true` or `wait_timeout` seconds pass. That wait emits no frames, so the final frames show the settled state at once.

### Encode

`write_offscreen_frames!` writes each frame as a PNG file into a temporary folder, through the offscreen renderer of `ProjecturedSDL` with `supersample` and `density`; see [sdl.md](../sdl/sdl.md). `FFMPEG.exe` then encodes the files with `libx264` and `yuv420p`. The filter `pad=ceil(iw/2)*2:ceil(ih/2)*2` makes both sides even, which H.264 needs. The command is a vector of strings, because a backtick command literal does not accept the parentheses and asterisks of the filter without quotes. An error in the chain propagates to the caller; a `finally` block closes the renderer and deletes the folder. A timeline that makes no frame raises an error.

## How it fits

The code is the slice `VideoModule`, in `source/backend/video/`: `VideoModule.jl` holds its imports and its exports, and `ProjecturedVideo` includes that file and exports the same names.

`ProjecturedVideo` depends on `FFMPEG`, the kernel, the platform and `ProjecturedSDL`. It declares the triggers `Projectured` and `FFMPEG` with the default `auto`, so AutoIntegration loads it when both are loaded; see [autointegration.md](../../autointegration/autointegration.md). It re-exports the essential names of `ProjecturedPlatform.EssentialsModule`; see [essentials.md](../../platform/essentials/essentials.md). It takes the offscreen renderer from `ProjecturedSDL` and does not have one of its own. It registers nothing.

`VideoBackend` is the other recorder: a `Backend` that plays a timeline through the real editor loop, so a take carries the whole application window. `record_application_video` in `example/backend/sdl/ApplicationVideo.jl` builds the window as `run_application` does and records it with this backend. With `partial_render = true` a frame repaints only the rectangles that changed, as a window with `partial_render` does, and `debug_dirty = true` outlines them in red on the frames; see [sdl.md](../sdl/sdl.md). The outline of the last repaint stays on the frames until the next one, as a window keeps its last picture. With `debug_dirty_hold` seconds, each outline stays for that long and then goes, so a pause in the take shows no outline. The `RenderSettings` of an editor reach a take through `apply_settings!`, and the recorder gives the editor settings that read these values from the backend, so the keywords of a take stay.

`record_assistant_conversation_video()` in `example/projectured/Gallery.jl` records a turn of the assistant with a `FakeLlm` and `wait_for`. `record_live_example` in `example/backend/sdl/LiveExamples.jl` records the timeline of a `LiveExample`, which `play_live_example` plays in a real window.

With `pointer = true`, `VideoBackend` draws the picture of the shape at the pointer on top of its ring, from [`find_pointer_shape`](../../platform/graphics/graphics.md#the-shape-of-the-pointer) at the point, in the window of the frame. Six shapes are a polygon in the style of the arrow, white with a black border; the crossed circle adds a ring of two circles around it. The three hands are glyphs of the Lucide font, black with a white outline, and the hot spot of the pointing hand is at the tip of its finger. A shape this backend does not draw is the arrow.

## Design decisions

- **A package for one dependency.** `ProjecturedVideo` is the only package that loads FFMPEG, so a user of the editor and of `write_image` does not load it. See [plan/done/extract-video-package.md](../../../../plan/done/extract-video-package.md).
- **Video time, not wall-clock time.** The video is the same on every run, and the rendering can be slower or faster than real time. See [plan/done/headless-video-recording.md](../../../../plan/done/headless-video-recording.md).
- **Print once, render each frame.** The reactive cells bring each change into the kept canvas, and no frame allocates a new tree.
- **The offscreen renderer of SDL.** A frame looks like a screenshot from `write_image`, and no second rasterizer exists.
- **A failure raises an error.** A caller gets an error and not a partial video.

## Usage

```julia
gestures = [
    (event = MouseClick(:left, 120, 40; time = time()), hold = 0.3),   # place the caret
    (event = KeyPress('h'; time = time()), hold = 0.3),
    (event = KeyPress('i'; time = time()), hold = 0.3),
    (event = KeyDown(:right, ModifierKeys(); time = time()), hold = 0.5),
]
record_video(document, projection, gestures, "demo.mp4"; fps = 30)
record_assistant_conversation_video("assistant.mp4")
```

- Examples: `record_assistant_conversation_video` and `record_live_example`.
- Test: `test_video()` in `ProjecturedVideoTest` runs the layering guard and `test_record_video()`: it encodes an `.mp4`, types with an initial selection, seeds the caret with an operation entry, and records the assistant demo with `wait_for`. `test_video_pointer_shape()` checks the picture that `VideoBackend` chooses for the shape at the pointer, and renders each of the nine shapes to a bitmap to check that it draws both black and white pixels around its hot spot.

## Limits

- `_VideoEditor` has only `document` and `iomap`. An operation whose evaluation reads any other field of the editor fails.
- No gesture tracking projection runs, so no click, double click or key chord is built from the raw events.
- No test covers an `await` entry, and the docstring of `record_video` does not describe it.
- Only `.mp4` is written.
