# Fragment of `ProjecturedVideo` — `VideoBackend`, a headless `Backend` that
# plays a scripted timeline through the real editor loop (`run_editor!`)
# instead of a native window, so a recording carries every tool the loop
# offers — the menu, the toolbar, the tabs, the assistant — rather than one
# bare projection printed by hand, the way `record_video` does it.

"""
    VideoBackend(timeline, window_id; width=1280, height=720, fps=30,
                initial_hold=0.5, final_hold=initial_hold,
                supersample=2, scale=1, video_time=false, pointer=true,
                partial_render=false, debug_dirty=false, debug_dirty_hold=0,
                frames_dir=mktempdir()) -> VideoBackend

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
even with nothing scheduled.

With `video_time = true` the backend keeps video time instead: frame `n` is at
`n / fps` seconds, each frame follows the one before by exactly `1/fps`, no frame
is copied, the entries fire by video time, and the loop does not sleep. The
editor's clock shows the same time ([`get_frame_clock_time`](@ref)), so an
animation that reads it moves one frame of time per frame, however long a frame
took to make. It is for a take whose changes come from its timeline and its
clock; a take that waits for work outside the loop, such as the answer of a
model, keeps the wall clock.

A frame in which the editor paints nothing still takes its place in the video,
so a take always ends. The editor paints nothing when a paint fails, when it has
stopped calling `write_to_devices` after too many failures in a row, or when it
has no window. The recorder then holds the last picture it painted: in wall-clock
time, a copy for each `1/fps` slot, and in video time, one copy for each such
frame. After a failed paint, the held picture carries a red line at the bottom
that says what failed. An entry that waits for its frame takes the held picture
as that frame, so the timeline goes on, and the entries after it fire as they
are due.

With `pointer = true` each frame shows the mouse pointer where the last mouse
event of the timeline left it, from the first mouse event on: an arrow, a ring
around its tip while the left button is held, and the ring fading out for 0.3 s
after a release or a click. The pointer is drawn over the window in a canvas of
the frame's own, so nothing of it enters the document of the application. The
rendering itself is `ProjecturedSdl`'s
offscreen renderer (`_open_offscreen_renderer`), opened here and closed by
[`quit_backend!`](@ref).

With `partial_render = true` a frame repaints only the rects that changed, as
an `SdlBackend` with `partial_render` does: the offscreen surface keeps its
pixels, and the dirty walk of `ProjecturedSdl` finds what to paint again. The
pointer is then drawn on the written frame and not into the surface. With
`debug_dirty = true` as well, each frame outlines in red the rects of the last
frame that repainted something, as the window keeps its last picture with its
outline until the next repaint. With `debug_dirty_hold` seconds, each outline
stays on the frames for that long instead, and no longer: a repaint of a single
frame, such as the one where a paragraph grows and the ones below move, stays
long enough to be seen, and a pause after it shows no outline.
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
    # What an `await` entry moves: the schedule of every entry after it, by the
    # seconds the wait really took. A take that waits for a model waits as long
    # as the model takes, and the entries after it follow from there.
    schedule_offset::Float64
    await_started::Float64
    # The editor of this recording, which an `await` predicate reads. The driver
    # puts it here after `make_editor` and before `run_editor!`.
    editor::Any
    frame::Base.RefValue{Int}
    last_frame_file::Union{String,Nothing}
    off::Any
    supersample::Int
    scale::Float64
    video_time::Bool
    # The pointer of the video: whether it is drawn, whether the left button is
    # held, and the schedule second of the last release or click.
    pointer::Bool
    pointer_held::Bool
    pointer_released_at::Float64
    # The partial repaint: whether a frame paints only what changed, whether it
    # outlines that in red, and what the offscreen paint keeps between frames.
    partial_render::Bool
    debug_dirty::Bool
    debug_dirty_hold::Float64
    paint_state::Any
    # The rects of each recent repaint, with its schedule second, for the hold.
    recent_repaints::Vector{Tuple{Float64,Vector{NTuple{4,Int}}}}
    # The reads that answered nothing since the last paint. A frame ends its reads
    # with one that answers nothing, so a read that starts with this count above
    # zero starts a frame after one that painted nothing.
    unpainted_reads::Int
    # The last frame the editor painted, the background of the window, the first
    # line of the fault of the last paint that failed (`nothing` once a paint
    # works), and the held picture with that line on it.
    painted_file::Union{String,Nothing}
    background::NTuple{4,UInt8}
    fault_line::Union{String,Nothing}
    held_file::Union{String,Nothing}
end

function VideoBackend(timeline::AbstractVector, window_id::Symbol;
                      width::Integer = 1280, height::Integer = 720, fps::Integer = 30,
                      initial_hold::Real = 0.5, final_hold::Real = initial_hold,
                      supersample::Integer = 2, scale::Real = 1,
                      video_time::Bool = false, pointer::Bool = true,
                      partial_render::Bool = false, debug_dirty::Bool = false,
                      debug_dirty_hold::Real = 0,
                      frames_dir::AbstractString = mktempdir())
    n = length(timeline)
    entries = Vector{Any}(undef, n + 1)
    acc = Float64(initial_hold)
    for i in 1:n
        entry = timeline[i]
        if haskey(entry, :await)
            entries[i] = (await = entry.await, fire_at = acc, cap = Float64(entry.hold))
        elseif haskey(entry, :event)
            entries[i] = (event = entry.event, fire_at = acc)
            acc += Float64(entry.hold)
        else
            error("VideoBackend: timeline entry $i carries neither `event` nor `await`")
        end
    end
    quit = WindowQuit(; time = time())
    entries[n + 1] = (event = quit, fire_at = acc + Float64(final_hold))
    VideoBackend(Int(width), Int(height), Int(fps), String(frames_dir), window_id,
                entries, 1, false, -1, -1, 0.0, 0.0, -1.0, nothing, Ref(0), nothing, nothing,
                Int(supersample), Float64(scale), video_time, pointer, false, -Inf,
                partial_render, debug_dirty, Float64(debug_dirty_hold), nothing,
                Tuple{Float64,Vector{NTuple{4,Int}}}[], 0, nothing, (0x00, 0x00, 0x00, 0xff),
                nothing, nothing)
end

# The video time of the frame about to be written: the frames written so far,
# each `1/fps` long.
_get_video_seconds(backend::VideoBackend) = backend.frame[] / backend.fps

get_frame_clock_time(backend::VideoBackend, wall_time) =
    backend.video_time ? _get_video_seconds(backend) : wall_time

# The second of the schedule: the video time when the backend keeps it, and the
# wall clock since the first frame otherwise.
_get_schedule_seconds(backend::VideoBackend) =
    backend.video_time ? _get_video_seconds(backend) : time() - backend.start_time

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
    backend.unpainted_reads = 0
    backend.painted_file = nothing
    backend.fault_line = nothing
    backend.held_file = nothing
    nothing
end

quit_backend!(backend::VideoBackend) = (_close_offscreen_renderer(backend.off); nothing)

get_pointer_position(backend::VideoBackend) = (backend.pointer_x, backend.pointer_y)

get_display_size(backend::VideoBackend) = (backend.width, backend.height)

# In video time the loop makes the next frame at once; it only lets other tasks
# run.
wait_for_input(backend::VideoBackend, devices, timeout_seconds) =
    backend.video_time ? (yield(); nothing) :
    (sleep(min(Float64(timeout_seconds), 1.0 / backend.fps)); nothing)

"""
    read_from_devices(backend::VideoBackend, devices) -> WindowInput or nothing

The next `timeline` entry whose `fire_at` has passed, as the `WindowInput`
`play_live!` builds for a live device: `entry.event` wrapped for
`backend.window_id`, with the time of the schedule when it fires, so the
gesture recognizer measures a click and a double click in the time of the
video. A mouse event updates the tracked pointer position before it is
returned. Answers `nothing` when the timeline is exhausted, the next
entry has not fired yet, or the entry already delivered has not been rendered
yet (`awaiting_render`) — every one of them the same "nothing left this poll"
answer a real device gives, and the last of them what keeps one entry per frame
true regardless of how long an entry's own turn through the loop takes.

A read that starts after a frame in which the editor painted nothing first holds
the last picture for that frame (see [`VideoBackend`](@ref)), and the held
picture is the frame of an entry that waits for one.
"""
function read_from_devices(backend::VideoBackend, devices)
    backend.start_time < 0 && return nothing   # no frame on disk yet — nothing to map an event onto
    backend.unpainted_reads > 0 && _hold_picture!(backend)
    input = _take_due_entry!(backend)
    input === nothing && (backend.unpainted_reads += 1)
    input
end

# The next entry of the timeline when it is due, as its window input; `nothing`
# while an entry waits for its frame, while the next one is not due, and for an
# `await` entry.
function _take_due_entry!(backend::VideoBackend)
    backend.awaiting_render && return nothing
    backend.next_entry > length(backend.timeline) && return nothing
    entry = backend.timeline[backend.next_entry]
    elapsed = _get_schedule_seconds(backend)
    elapsed >= entry.fire_at + backend.schedule_offset || return nothing
    haskey(entry, :await) && return _wait_for_entry!(backend, entry, elapsed)
    backend.next_entry += 1
    backend.awaiting_render = true
    _track_pointer!(backend, entry.event)
    WindowInput(backend.window_id, _restamp_event(entry.event, backend.start_time + elapsed))
end

# `event` with the time `time` in place of its own. The time is the last field of
# every event (see `Event`), and the full constructor takes every field.
function _restamp_event(event, time::Float64)
    type = typeof(event)
    type(ntuple(i -> getfield(event, i), fieldcount(type) - 1)..., time)
end

# An `await` entry holds the schedule until its predicate answers true, or
# until its cap of seconds runs out. It delivers no event, and the frames of
# the wait are the frames of whatever the editor does meanwhile: a streaming
# turn of the assistant paints itself into them. When the wait ends, every
# entry after it moves by the seconds the wait took, so nothing fires late in a
# batch.
function _wait_for_entry!(backend::VideoBackend, entry, elapsed::Float64)
    backend.await_started < 0 && (backend.await_started = elapsed)
    waited = elapsed - backend.await_started
    done = waited >= entry.cap
    if !done
        answer = try
            entry.await(backend.editor)
        catch
            false
        end
        done = answer === true
    end
    done || return nothing
    backend.next_entry += 1
    backend.schedule_offset = elapsed - entry.fire_at
    backend.await_started = -1.0
    nothing
end

function _track_pointer!(backend::VideoBackend, event)
    event isa Union{MouseDown,MouseUp,MousePress,MouseMove,MouseScroll} || return nothing
    backend.pointer_x = event.x
    backend.pointer_y = event.y
    if event isa MouseDown && event.button === :left
        backend.pointer_held = true
    elseif event isa Union{MouseUp,MousePress} && event.button === :left
        backend.pointer_held = false
        backend.pointer_released_at = _get_schedule_seconds(backend)
    end
    nothing
end

# The arrow of the pointer with its tip at (0, 0), the outline of a common
# desktop pointer; the ring around the tip; and how long the ring takes to fade
# out after a release.
const _POINTER_ARROW = [(0, 0), (0, 17), (4, 13), (7, 20), (10, 19), (7, 12), (12, 12)]
const _POINTER_RING_RADIUS = 11
const _POINTER_RING_WIDTH = 3
const _POINTER_FADE_SECONDS = 0.3

# The shapes of the pointer where the timeline left it: the ring while the left
# button is held or while it fades out, and the arrow on top.
function _make_pointer_graphics(backend::VideoBackend)
    x, y = backend.pointer_x, backend.pointer_y
    ring = color_solarized_orange
    since_release = _get_schedule_seconds(backend) - backend.pointer_released_at
    elements = Any[]
    if backend.pointer_held
        push!(elements, GraphicsCircle(x, y, _POINTER_RING_RADIUS; color = color_transparent,
                                       border_width = _POINTER_RING_WIDTH, border_color = ring))
    elseif 0 <= since_release < _POINTER_FADE_SECONDS
        left = 1 - since_release / _POINTER_FADE_SECONDS
        faded = StyleColor(ring.red, ring.green, ring.blue, left)
        push!(elements, GraphicsCircle(x, y, _POINTER_RING_RADIUS + 6 * (1 - left); color = color_transparent,
                                       border_width = _POINTER_RING_WIDTH, border_color = faded))
    end
    push!(elements, GraphicsPolygon([(x + dx, y + dy) for (dx, dy) in _POINTER_ARROW];
                                    color = color_white, border_width = 1, border_color = color_black))
    elements
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
    backend.start_time < 0 ? (backend.start_time = time()) :
        (backend.video_time || _backfill_frames!(backend))
    backend.background = window.bg
    try
        if backend.partial_render
            _write_partial_frame!(backend, canvas, window.bg)
        else
            if backend.pointer && backend.pointer_x >= 0
                canvas = GraphicsCanvas(Any[canvas; _make_pointer_graphics(backend)]; w = backend.width, h = backend.height)
            end
            _emit_frames!(backend.off, canvas, backend.width, backend.height, window.bg,
                         backend.frames_dir, backend.frame, 1)
        end
    catch exception
        # The frames hold the last picture with this fault on it until a paint
        # works, and the barrier of the editor records the fault. A partial
        # paint that stopped half way left its surface unknown, so the next
        # paint paints it all.
        line = _describe_fault(exception)
        line == backend.fault_line || (backend.held_file = nothing)
        backend.fault_line = line
        backend.paint_state = nothing
        rethrow()
    end
    backend.last_frame_file = _video_frame_path(backend.frames_dir, backend.frame[])
    backend.painted_file = backend.last_frame_file
    backend.fault_line = nothing
    backend.held_file = nothing
    backend.unpainted_reads = 0
    backend.awaiting_render = false
    nothing
end

# The first line of what a failed paint threw.
_describe_fault(exception) = String(first(split(sprint(showerror, exception), '\n')))

# What the video shows for a frame in which the editor painted nothing: the
# last picture, with the line of the fault on it after a failed paint. In
# wall-clock time the copies fill each `1/fps` slot up to now; in video time the
# frame is one copy. An entry that waits for its frame has it now.
function _hold_picture!(backend::VideoBackend)
    backend.awaiting_render = false
    picture = _render_held_picture!(backend)
    picture === nothing && return nothing
    backend.last_frame_file = picture
    if backend.video_time
        backend.frame[] += 1
        cp(picture, _video_frame_path(backend.frames_dir, backend.frame[]))
    else
        _backfill_frames!(backend)
    end
    nothing
end

# The picture that the frames hold: the last painted frame, or after a failed
# paint that frame with the red line of the fault drawn on it. The line is drawn
# once for each fault, and the calls after it answer the same file. When no
# paint has worked yet, the line is drawn on the background of the window, as a
# frame of its own.
function _render_held_picture!(backend::VideoBackend)
    backend.fault_line === nothing && return backend.painted_file
    backend.held_file === nothing || return backend.held_file
    overlay = _make_fault_line_graphics(backend)
    if backend.painted_file === nothing
        _emit_frames!(backend.off, overlay, backend.width, backend.height, backend.background,
                      backend.frames_dir, backend.frame, 1)
        backend.held_file = _video_frame_path(backend.frames_dir, backend.frame[])
    else
        backend.held_file = joinpath(backend.frames_dir, "held_$(backend.frame[]).png")
        _save_picture_with_overlay!(backend.off, backend.painted_file, overlay,
                                    backend.width, backend.height, backend.held_file)
    end
    backend.held_file
end

# The red band across the bottom of a held picture, with the fault in white.
const _FAULT_BAND_HEIGHT = 28

function _make_fault_line_graphics(backend::VideoBackend)
    top = backend.height - _FAULT_BAND_HEIGHT
    GraphicsCanvas(Any[GraphicsRect(0, top, backend.width, _FAULT_BAND_HEIGHT; color = color_solarized_red),
                       GraphicsText("The window can not paint: " * backend.fault_line, 8, top + 5;
                                    font = font_dejavu_monospace_bold_16, color = color_white)];
                   w = backend.width, h = backend.height)
end

# A frame of a partial repaint: the window canvas paints only what changed, and
# the pointer is drawn on the written frame, because a canvas made around the
# window each frame would be new to the dirty walk and repaint it all.
function _write_partial_frame!(backend::VideoBackend, canvas::GraphicsCanvas, background)
    backend.paint_state === nothing &&
        (backend.paint_state = _make_offscreen_paint_state(backend.off, backend.width, backend.height))
    state = backend.paint_state
    painted = _render_canvas_offscreen_partial!(backend.off, state, canvas, background)
    pointer = backend.pointer && backend.pointer_x >= 0 ?
              GraphicsCanvas(_make_pointer_graphics(backend); w = backend.width, h = backend.height) :
              nothing
    outline = backend.debug_dirty ? _get_held_outline(backend, painted, state.last_rects) :
              NTuple{4,Int}[]
    _emit_frame_with_overlay!(backend.off, backend.width, backend.height, pointer, outline,
                              backend.frames_dir, backend.frame)
end

# The rects to outline on this frame: those of the last repaint, or with a hold,
# those of every repaint of the last `debug_dirty_hold` seconds.
function _get_held_outline(backend::VideoBackend, painted, last_rects)
    backend.debug_dirty_hold > 0 || return last_rects
    now = _get_schedule_seconds(backend)
    isempty(painted) || push!(backend.recent_repaints, (now, painted))
    filter!(entry -> now - entry[1] <= backend.debug_dirty_hold, backend.recent_repaints)
    held = NTuple{4,Int}[]
    for (_, rects) in backend.recent_repaints
        append!(held, rects)
    end
    unique(held)
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
