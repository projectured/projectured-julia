# Fragment of `ProjecturedVideo` — `VideoBackend`, a headless `Backend` that
# plays a scripted timeline through the real editor loop (`run_editor!`)
# instead of a native window, so a recording carries every tool the loop
# offers — the menu, the toolbar, the tabs, the assistant — rather than one
# bare projection printed by hand, the way `record_video` does it.

"""
    VideoBackend(timeline, window_id; width=1280, height=720, fps=30,
                initial_hold=0.5, final_hold=initial_hold,
                supersample=2, scale=1, frames_dir=mktempdir()) -> VideoBackend

A `Backend` whose input is a scripted `timeline` and whose output is one PNG
per repainted frame, so `run_editor!` records a session instead of showing one.

`timeline` is a vector of `(event = …, hold = …)` entries — the `event` half of
the shape `record_video` and `play_live!` take. Entry `i` fires
`initial_hold + Σ hold[1..i-1]` seconds after the first frame is on disk (not
after [`initialize_backend!`](@ref) — the loop's first `read!` runs before its
first `print!`, and a window input delivered into that gap is lost, since the
reader has no `iomap` yet to map it against), as the `WindowInput` `play_live!`
builds for `window_id`, which is where
`write_to_devices` also looks for the window to render — the same routing a
real device and window would give a single-window scene. `final_hold` seconds
after the last entry's own hold has run out, the backend fires a `WindowQuit`
of its own, appended after `timeline`, which ends the loop through the same
`QuitEditorException` the window-close button raises.

The frame count follows the wall clock rather than the render time: a call to
`write_to_devices` that finds a real gap since the frame before first repeats
that frame, once per `1/fps` slot the gap covers — so a slow repaint holds the
old state on screen for as long as it really took, instead of shrinking the
video below the length of the session — then renders and writes the new one.
`wait_for_input` sleeps at most `1/fps` so the loop keeps ticking at that pace
even with nothing scheduled. The rendering itself is `ProjecturedSdl`'s
offscreen renderer (`_open_offscreen_renderer`), opened here and closed by
[`quit_backend!`](@ref).
"""
mutable struct VideoBackend <: Backend
    width::Int
    height::Int
    fps::Int
    frames_dir::String
    window_id::Symbol
    # Each entry is `(event = …, fire_at = …)` — `fire_at` the second, counted
    # from `start_time`, at which `read_from_devices` answers it. The last
    # entry is always the backend's own appended `WindowQuit`.
    timeline::Vector{Any}
    next_entry::Int
    # Set by `read_from_devices` the moment it delivers an entry, and cleared
    # by `write_to_devices` the moment it renders. While it is set, the next
    # entry is held back even if its `fire_at` has passed — so a stretch of
    # real time slow enough to carry several entries' `fire_at` at once (a
    # cold JIT compile, a heavy layout) still renders one of them at a time,
    # instead of applying them all before the frame that shows any of it. It
    # is what makes the appended `WindowQuit` safe: `evaluate_operation`
    # throws before `run_frame!` reaches its own repaint, so the quit must
    # never share a frame with the entry before it.
    awaiting_render::Bool
    pointer_x::Int
    pointer_y::Int
    start_time::Float64
    frame::Base.RefValue{Int}
    last_frame_file::Union{String,Nothing}
    off::Any
    supersample::Int
    scale::Float64
end

function VideoBackend(timeline::AbstractVector, window_id::Symbol;
                      width::Integer = 1280, height::Integer = 720, fps::Integer = 30,
                      initial_hold::Real = 0.5, final_hold::Real = initial_hold,
                      supersample::Integer = 2, scale::Real = 1,
                      frames_dir::AbstractString = mktempdir())
    n = length(timeline)
    entries = Vector{Any}(undef, n + 1)
    acc = Float64(initial_hold)
    for i in 1:n
        haskey(timeline[i], :event) ||
            error("VideoBackend: timeline entry $i carries no `event` — " *
                  "only event entries reach the real editor loop")
        entries[i] = (event = timeline[i].event, fire_at = acc)
        acc += Float64(timeline[i].hold)
    end
    entries[n + 1] = (event = WindowQuit(), fire_at = acc + Float64(final_hold))
    VideoBackend(Int(width), Int(height), Int(fps), String(frames_dir), window_id,
                entries, 1, false, -1, -1, 0.0, Ref(0), nothing, nothing,
                Int(supersample), Float64(scale))
end

# The exact naming `_emit_frames!` writes each frame under, so a backfilled
# copy lands where ffmpeg's `frame_%06d.png` pattern expects it.
_video_frame_path(dir::AbstractString, index::Integer) =
    joinpath(dir, "frame_$(lpad(index, 6, '0')).png")

function initialize_backend!(backend::VideoBackend)
    backend.off = _open_offscreen_renderer(backend.width, backend.height;
                                           supersample = backend.supersample,
                                           scale = backend.scale)
    # -1 marks the clock as not yet started (see `write_to_devices`): the loop's
    # first `read!` runs before the first `print!`, while `editor.iomap` is
    # still `nothing`, and a window input delivered into that gap is dropped by
    # the reader with no operation and no way back (`read!`'s own
    # `editor.iomap === nothing` branch). Starting the clock only once the
    # first frame is on disk guarantees no entry can fire before the pipeline
    # is ready to read one.
    backend.start_time = -1.0
    backend.next_entry = 1
    backend.awaiting_render = false
    backend.frame[] = 0
    backend.last_frame_file = nothing
    nothing
end

quit_backend!(backend::VideoBackend) = (_close_offscreen_renderer(backend.off); nothing)

# `SdlBackend`'s own method ignores its instance argument — the font metrics it
# reads are process-global (the `_get_font` cache) — so a throwaway instance
# reaches the same measurement `ProjecturedSdl` gives a real window.
measure_text(::VideoBackend, text::AbstractString, font) =
    measure_text(SdlBackend(), text, font)

get_pointer_position(backend::VideoBackend) = (backend.pointer_x, backend.pointer_y)

get_display_size(backend::VideoBackend; display::Integer = 0) = (backend.width, backend.height)

wait_for_input(backend::VideoBackend, devices, timeout_seconds) =
    (sleep(min(Float64(timeout_seconds), 1.0 / backend.fps)); nothing)

"""
    read_from_devices(backend::VideoBackend, devices) -> WindowInput or nothing

The next `timeline` entry whose `fire_at` has passed, as the `WindowInput`
`play_live!` builds for a live device: `entry.event` wrapped for
`backend.window_id`. A mouse event updates the tracked pointer position before
it is returned. Answers `nothing` when the timeline is exhausted, the next
entry has not fired yet, or the entry already delivered has not been rendered
yet (`awaiting_render`) — every one of them the same "nothing left this poll"
answer a real device gives, and the last of them what keeps one entry per frame
true regardless of how long an entry's own turn through the loop takes.
"""
function read_from_devices(backend::VideoBackend, devices)
    backend.start_time < 0 && return nothing   # no frame on disk yet — nothing to map an event onto
    backend.awaiting_render && return nothing
    backend.next_entry > length(backend.timeline) && return nothing
    entry = backend.timeline[backend.next_entry]
    (time() - backend.start_time) >= entry.fire_at || return nothing
    backend.next_entry += 1
    backend.awaiting_render = true
    _track_pointer!(backend, entry.event)
    WindowInput(backend.window_id, entry.event)
end

function _track_pointer!(backend::VideoBackend, event)
    event isa Union{MouseDown,MouseUp,MousePress,MouseMove,MouseScroll} || return nothing
    backend.pointer_x = event.x
    backend.pointer_y = event.y
    nothing
end

# Fill the wall-clock gap since the last frame with copies of it: while more
# than one `1/fps` slot has passed since `backend.frame[]` was written, copy
# `last_frame_file` forward one slot at a time. Nothing to fill before the
# first frame exists.
function _backfill_frames!(backend::VideoBackend)
    backend.last_frame_file === nothing && return nothing
    while true
        target = floor(Int, (time() - backend.start_time) * backend.fps)
        backend.frame[] < target - 1 || break
        backend.frame[] += 1
        cp(backend.last_frame_file, _video_frame_path(backend.frames_dir, backend.frame[]))
    end
    nothing
end

"""
    write_to_devices(backend::VideoBackend, devices, screen::ScreenDocument)

Render the window named by `backend.window_id` (or, failing that, the first
window of `screen` — the routing `read_from_devices` also uses) and write it as
the next frame, backfilling the wall-clock gap first (see
[`VideoBackend`](@ref)). A window this backend does not recognise as
`GraphicsCanvas` content is an error, exactly as `record_video` and
`SdlBackend` treat it.
"""
function write_to_devices(backend::VideoBackend, devices, screen::ScreenDocument)
    window = _select_window(backend, screen)
    window === nothing && return nothing
    canvas = window.content
    canvas isa GraphicsCanvas ||
        error("write_to_devices: WindowDocument(id=:$(window.id)).content is " *
              "$(typeof(canvas)), expected GraphicsCanvas")
    # The first frame starts the timeline's clock (see `initialize_backend!`);
    # there is nothing yet to backfill a gap against.
    backend.start_time < 0 ? (backend.start_time = time()) : _backfill_frames!(backend)
    _emit_frames!(backend.off, canvas, backend.width, backend.height, window.bg,
                 backend.frames_dir, backend.frame, 1)
    backend.last_frame_file = _video_frame_path(backend.frames_dir, backend.frame[])
    backend.awaiting_render = false
    nothing
end

function _select_window(backend::VideoBackend, screen::ScreenDocument)
    for w in screen.windows
        w isa WindowDocument && w.id == backend.window_id && return w
    end
    for w in screen.windows
        w isa WindowDocument && return w
    end
    nothing
end

export VideoBackend
