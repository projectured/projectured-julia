# Fragment of `VideoModule` — `record_video`, which plays a document and its
# gestures into a video file, and `encode_frames_to_video!`, which encodes the
# frames of every recorder.

# A minimal mutable editor stand-in for `evaluate_operation`, mirroring the test
# harness's `_ReplEditor`: an operation such as `ReplaceDocumentOperation` may
# rebind `.document` (a whole-document swap) and null `.iomap`. `record_video`
# re-reads `.document` afterwards so a root swap is picked up by the next print.
mutable struct _VideoEditor
    document::Any
    iomap::Any
end

"""
    record_video(document, projection; gestures, filename::AbstractString,
                 fps=30, width=1200, height=800,
                 background=(0xf9,0xf9,0xfb,0xff),
                 initial_hold=0.5, final_hold=initial_hold,
                 supersample=2, density=1) -> String

Record a headless video of an editing session and encode it to `filename` (which
must end in `.mp4`). No window is required — frames are rendered with the same
offscreen software renderer as `ProjecturedSDL.write_image` and assembled with `ffmpeg`.

`gestures` is a vector of timed entries. Each entry carries either an `event` or
an `operation`, plus a `hold`:
- `(event = …, hold = …)` — `event` is any backend-agnostic device event
  (`KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`, `MouseUp`, `MouseClick`,
  `MouseMove`, `MouseScroll`), translated to an operation via `read_intent`.
- `(operation = …, hold = …)` — a domain `Operation` injected straight into
  `evaluate_operation`, skipping the reader (for actions with no single-event
  trigger: seed a selection, scroll, swap focus/document). `operation` may be an
  `Operation` value or a `doc -> op` thunk evaluated at fire time.

`hold` is the number of seconds to display the resulting state. Timing is in **video time** (frame
counts, not wall-clock), so the output is deterministic regardless of how long
rendering takes — `round(hold * fps)` identical frames are emitted per gesture.
The initial state (before any gesture) is held for `initial_hold` seconds and the
final state (after the last gesture) for `final_hold` seconds, giving a still
margin at each end of the clip; both default to `0.5`.

For each gesture the standard editor cycle runs: `read_intent` →
`evaluate_operation` → `print_document`, mirroring the live editor loop. Each
frame is laid out at the fixed `width × height` video resolution so mouse-gesture
coordinates line up with what is rendered. Errors from the pipeline propagate
(callers want loud failures, not a partial video).

```julia
gestures = [
    (event = KeyPress('h'; time = time()),                   hold = 0.3),
    (event = KeyPress('i'; time = time()),                   hold = 0.3),
    (event = KeyDown(:right, ModifierKeys(); time = time()), hold = 0.5),
]
record_video(doc, proj; gestures, filename = "/tmp/demo.mp4", fps = 30)
```

`initial_selection` controls where the caret starts. Keyboard typein (e.g.
`KeyPress`) only produces an edit when something is selected, so to record a
typing demo either pass an `initial_selection` (a `Reference` into the
document) or make the first gesture a `MouseClick` that places the caret. When
`initial_selection` is `nothing` (the default) the selection is cleared and the
recording starts caret-free, mirroring a freshly opened editor.

`wait_for` records the result of asynchronous editor work. The gesture loop never
yields, so an `@async` task started by a gesture (e.g. the assistant's streaming
reply launched by ENTER) cannot progress on its own. When `wait_for` is a
predicate, after the last gesture the recording spins (yielding) until it returns
`true` — or `wait_timeout` wall-clock seconds elapse — then re-prints so the
final-hold frames show the settled state (e.g. `wait_for = () -> a.status === :idle`).
"""
function record_video(document, projection; gestures::AbstractVector,
                      filename::AbstractString,
                      fps::Integer = 30,
                      width::Integer = 1200,
                      height::Integer = 800,
                      background::NTuple{4,UInt8} = (0xf9, 0xf9, 0xfb, 0xff),
                      initial_hold::Real = 0.5,
                      final_hold::Real = initial_hold,
                      initial_selection = nothing,
                      wait_for::Union{Nothing,Function} = nothing,
                      wait_timeout::Real = 5.0,
                      supersample::Integer = 2,
                      density::Real = 1,
                      clock::Clock = Clock())
    lowercase(splitext(filename)[2]) == ".mp4" ||
        error("record_video: only .mp4 output is supported (got \"$filename\")")

    # Lay out every frame at the fixed video resolution. The recording clock
    # rides on the printer context, so a time-animated document (whose cells
    # subscribe to `clock`) advances deterministically frame-by-frame; a
    # non-animated document ignores it.
    print_iomap = doc -> print_document(projection, nothing, doc,
        PrinterContext(EmptyReference(), Cell(Int(width)), Cell(Int(height)),
                       Dict{Symbol,Any}(), clock))
    canvas_of = iomap -> begin
        canvas = iomap.output
        canvas isa GraphicsCanvas ||
            error("record_video: projection output is $(typeof(canvas)), expected GraphicsCanvas")
        canvas
    end

    off = open_offscreen_renderer(width, height; supersample=supersample, density=density)
    tmpdir = mktempdir()
    frame = Ref(0)
    # Print the projection ONCE and keep the resulting canvas; every frame just
    # re-renders that same canvas. Re-rendering re-forces the reactive cells, so
    # streamed parts, typed characters, the live progress card and the animation
    # all appear incrementally — *without* re-running the whole (heavy) projection
    # per frame, which would allocate a fresh graphics tree every frame and thrash
    # GC / memory. `set_clock_time!(clock, frame/fps)` advances the recording clock so
    # time-reading cells recompute deterministically (no wall-clock coupling —
    # faster-than-real-time render is exactly what falls out). The projection
    # is only re-printed if an operation swaps the whole document.
    iomap = nothing
    reprint!() = (iomap = print_iomap(document); nothing)
    emit_frames! = (n::Integer) -> for _ in 1:max(n, 0)
        set_clock_time!(clock, frame[] / fps)
        write_offscreen_frames!(off, canvas_of(iomap); background, folder = tmpdir, frame)
    end
    try
        if initial_selection === nothing
            clear_selection!(document)
        else
            set_selection!(document, initial_selection)
        end
        reprint!()
        emit_frames!(round(Int, initial_hold * fps))

        for entry in gestures
            # An `await` entry captures the gradual reveal of asynchronous editor
            # work (e.g. the assistant's streaming reply launched by a prior
            # ENTER). The gesture loop is the only task that yields, so frames are
            # only captured here: spin — printing and emitting one frame per ~1/fps
            # — until the `doc -> Bool` predicate holds or the `hold` cap elapses,
            # so the streamed thinking/text/tool output appears along the time axis
            # instead of popping in fully formed.
            if haskey(entry, :await)
                pred = entry.await
                deadline = time() + Float64(entry.hold)
                while !(pred isa Function ? pred(document) : pred) && time() < deadline
                    emit_frames!(1)
                    yield()
                    sleep(1 / fps)
                end
                emit_frames!(1)
                continue
            end
            # A non-await entry carries either an `event` (translated to an
            # operation via the reader, like live input) or an `operation` (a
            # domain operation injected straight into the evaluator, for actions
            # with no single device-event trigger). An `operation` may be an
            # `Operation` value or a `doc -> op` thunk evaluated at fire time
            # against the current document.
            if haskey(entry, :operation)
                op = entry.operation isa Function ? entry.operation(document) : entry.operation
            else
                op = read_intent(projection, iomap, entry.event)
            end
            if op !== nothing
                ed = _VideoEditor(document, iomap)
                evaluate_operation(ed, op)
                # In-place edits (typing, submit, streamed parts) propagate through
                # the reactive graph, so the cached canvas re-renders them. Only a
                # whole-document *swap* needs a re-print.
                if ed.document !== document
                    document = ed.document
                    reprint!()
                end
            end
            emit_frames!(round(Int, entry.hold * fps))
        end

        # Let async editor work kicked off by the gestures settle before the
        # final frames. The frame loop never yields, so an `@async` task (e.g.
        # the assistant's streaming reply launched by ENTER) can't progress on
        # its own; spin yielding until `wait_for()` is satisfied (or the
        # `wait_timeout` wall-clock deadline passes).
        if wait_for !== nothing
            deadline = time() + wait_timeout
            while !wait_for() && time() < deadline
                yield()
                sleep(0.01)
            end
        end

        # End margin: hold (and keep animating) the final state.
        emit_frames!(max(round(Int, final_hold * fps), 1))

        frame[] == 0 &&
            error("record_video: no frames produced (gestures empty and initial_hold/final_hold ≈ 0)")

        encode_frames_to_video!(tmpdir, filename, fps)
    finally
        close_offscreen_renderer(off)
        rm(tmpdir; force=true, recursive=true)
    end
    filename
end

"""
    encode_frames_to_video!(frames_dir, filename, fps) -> nothing

Encode the frames `frame_000001.png` and on in `frames_dir`, as
`write_offscreen_frames!` names them, into the video `filename` at `fps` frames
per second. `record_video` and `VideoBackend` end a recording with it, so a
codec or a pixel format is chosen in one place.
"""
function encode_frames_to_video!(frames_dir::AbstractString, filename::AbstractString,
                                  fps::Integer)
    pattern = joinpath(frames_dir, "frame_%06d.png")
    # Build the command from a string vector: a backtick literal would reject
    # the unquoted parentheses/asterisks in the `pad` filter expression.
    FFMPEG.exe(Cmd(String[
        "-y", "-hide_banner", "-loglevel", "error",
        "-framerate", string(fps), "-i", pattern,
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", filename]))
    filename
end
