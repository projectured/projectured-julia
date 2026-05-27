# Headless video recording of the editor

## Context

ProjecturEd already has the two ingredients needed to record a video of an editing session without a window: an **offscreen SDL software renderer** that writes a single frame to BMP ([Sdl.jl:613-653](program/src/backend/Sdl.jl#L613-L653)), and a **windowless read-eval-print walker** that drives the editor by feeding it a list of events one at a time ([ReplTest.jl:14-46](test/src/editor/ReplTest.jl#L14-L46)). What is missing is a function that ties them together: take a *timed* sequence of gestures, run the REPL cycle for each one, snapshot a frame after each event, and assemble the frames into a video.

This enables demo videos for the README, tutorial GIFs/MP4s, regression-style "golden video" checks for examples, and reproducible bug-report recordings. Timing is in **video time** (frame counts, not wall-clock) so output is deterministic regardless of how long rendering takes.

## Design summary

Add a `record_video(document, projection, gestures, filename; fps, width, height, background)` function that:

1. Initializes a single offscreen SDL software renderer (reuses [Sdl.jl write_image](program/src/backend/Sdl.jl#L613) machinery).
2. Renders the initial document state as frame 0.
3. For each `(event, hold)` entry, calls `projection_read` → `evaluate_operation` → `projection_print` (the same cycle used by [`walk_repl_loop`](test/src/editor/ReplTest.jl#L14)), then writes `round(hold * fps)` identical BMP frames showing the post-event state.
4. Invokes `ffmpeg` via `FFMPEG.jl` to encode the BMP sequence into an H.264 MP4.
5. Cleans up the temp frame directory.

### Gesture format

```julia
gestures = [
    (event = KeyPress('h'),            hold = 0.3),
    (event = KeyPress('i'),            hold = 0.3),
    (event = KeyDown(:right, Modifiers(), false), hold = 1.0),
    (event = MousePress(:left, 100, 50, Modifiers()), hold = 0.5),
]
```

`event` is any backend-agnostic event already defined in [Keyboard.jl](program/src/device/Keyboard.jl) / [Mouse.jl](program/src/device/Mouse.jl) (`KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll`). `hold` is seconds to display the resulting state. The initial state (before any gesture) is shown for `initial_hold` seconds (separate kwarg, defaults to `0.5`).

### Output format

MP4 only, encoded with libx264 + `yuv420p` pixel format for universal playback. Frame rate defaults to `fps=30`.

## Files to modify

### 1. `program/src/backend/Sdl.jl` — extract reusable offscreen renderer

Refactor the body of [`write_image(canvas, filename, ...)`](program/src/backend/Sdl.jl#L613) so the SDL surface/renderer setup is reusable across many frames:

- Add a small internal helper that opens an offscreen surface+renderer pair, returns the `SdlWindowHandle`, and a corresponding `_save_surface_bmp(surface, filename)` and teardown helper.
- Keep the existing public `write_image` overloads unchanged (they call the helper for a single frame).

This avoids re-initializing SDL_Init/TTF_Init and recreating the renderer per frame — important because there will be hundreds-to-thousands of frames per video.

### 2. `program/src/backend/Sdl.jl` — add `record_video`

New function appended after the `GraphicsCanvasToImageFile` block (after [Sdl.jl:734](program/src/backend/Sdl.jl#L734)):

```julia
function record_video(document, projection, gestures::AbstractVector,
                      filename::AbstractString;
                      fps::Integer = 30,
                      width::Integer = 1200,
                      height::Integer = 800,
                      background::NTuple{4,UInt8} = (0x00,0x00,0x00,0xff),
                      initial_hold::Real = 0.5)
    # 1. Open offscreen surface+renderer (via the new helper).
    # 2. mktempdir() for BMP frames.
    # 3. clear_selection!(document); iomap = projection_print(projection, document)
    #    Render frame 0001..N from iomap.output for initial_hold seconds.
    # 4. For each (event, hold) in gestures:
    #      op = projection_read(projection, iomap, event)
    #      op !== nothing && evaluate_operation(op, document)
    #      iomap = projection_print(projection, document)
    #      Render ceil(hold * fps) frames from iomap.output.
    # 5. Close SDL renderer/surface.
    # 6. Invoke ffmpeg to encode frame_%06d.bmp -> filename.
    # 7. Remove temp dir.
end
```

Encoding command (issued via `FFMPEG.exe_ffmpeg`):

```
ffmpeg -y -framerate <fps> -i <tmp>/frame_%06d.bmp \
       -c:v libx264 -pix_fmt yuv420p -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
       <filename>
```

The `pad` filter guarantees even dimensions (libx264 requires them); the existing `write_image` accepts any size.

Notes:
- Use `clear_selection!` at the start to mirror `walk_repl_loop`, so the initial frame is consistent.
- Wrap event loop in `try / finally` so the SDL renderer + temp dir are always cleaned up.
- Re-raise errors from `projection_read` / `evaluate_operation` rather than swallowing them — production callers want loud failures, not partial videos.

### 3. `program/Project.toml` — add `FFMPEG` dependency

Add:
```toml
FFMPEG = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
```
(direct dependency on the `FFMPEG.jl` wrapper, not just the transitive `FFMPEG_jll` already in the Manifest). Run `Pkg.resolve()` after the edit.

### 4. `program/src/Projectured.jl` — export `record_video`

Add `record_video` to the symbols re-exported from `SdlModule` (mirror the existing `write_image` export).

### 5. `example/src/Examples.jl` — add `record_video_example`

Mirror the existing [`write_image_example`](example/src/Examples.jl#L94-L104) pattern (around line 94):

```julia
function record_video_example(example::Example, gestures, filename;
                              width=1200, height=800, fps=30, kwargs...)
    record_video(example.document, example.projection, gestures, filename;
                 width, height, fps, kwargs...)
end

function record_video_example(name::AbstractString, gestures,
                              filename = tempname() * ".mp4"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    record_video_example(examples[idx], gestures, filename; kwargs...)
end
```

Add `record_video_example` to the export list at [ProjecturedExample.jl:88](example/src/ProjecturedExample.jl#L88).

### 6. `guide/debugging.md` — document the new helper

Add a short section showing a minimal example, similar to the existing `write_image_example` snippet.

## What is intentionally NOT in scope

- **Cursor blink / smooth animation between events.** Repeating identical frames between events is fine — ffmpeg encodes them cheaply and the video plays smoothly. Animations can be a later extension.
- **Real-time playback.** Timing is in video time only; this function never `sleep`s.
- **GIF / WebM / other formats.** Filename extension is currently constrained to `.mp4`.
- **Window-based capture.** This is purely headless via the existing software renderer.
- **MCP integration** for triggering recordings from an AI agent — out of scope for v1, but the function signature is MCP-friendly should that follow.

## Verification

1. **Smoke test in REPL** (from `example/` env):
   ```julia
   using Projectured, ProjecturedExample
   gestures = [
       (event = KeyPress('h'),               hold = 0.3),
       (event = KeyPress('i'),               hold = 0.3),
       (event = KeyDown(:right, Modifiers(), false), hold = 0.5),
   ]
   record_video_example("json", gestures, "/tmp/demo.mp4"; fps=30)
   ```
   Verify `/tmp/demo.mp4` exists, has non-zero size, and plays in a video player.

2. **Frame-count check** via shell:
   ```bash
   ffprobe -v error -select_streams v:0 -count_packets \
           -show_entries stream=nb_read_packets -of csv=p=0 /tmp/demo.mp4
   ```
   Should equal `round(0.5*30) + round(0.3*30) + round(0.3*30) + round(0.5*30)` = `15 + 9 + 9 + 15` = `48`.

3. **Add a test** in `test/src/editor/` (e.g. `VideoTest.jl`) that records a 1-second video from `json_example` and asserts the output file exists and has > 0 bytes. Wire it into `test_all` only if `FFMPEG.exe_ffmpeg` is available, so CI without ffmpeg doesn't break.

4. **Manual visual inspection**: play the MP4 and confirm each gesture's resulting state is visible for roughly the expected duration.
