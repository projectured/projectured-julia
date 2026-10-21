# ═══════════════════════════════════════════════════════════════════════════
# test/backend/video/editor/ApplicationVideoTest.jl
#
# Smoke test for `record_application_video`: a short clip of the application
# window with no file — the Explorer, no assistant — typing `repl` into a
# freshly opened tab and pressing Enter. Asserts the file exists and bounds the
# duration that `ffprobe` reports rather than
# pinning it to the timeline's own scripted total: a cold, unprecompiled
# process overshoots that total by however long the first-ever compile of the
# panes/widgets/font stack takes, and `VideoBackend`'s own clock starts only
# once the first frame is on disk, so the recorded duration is always a little
# under the wall time `record_application_video` itself measures (which also
# counts building the window before the first frame and encoding after the
# last). The lower bound catches the one failure that matters here — frames
# silently missing, shrinking the video below the session it recorded (G2);
# the upper bound is the one relation that holds regardless of how slow the
# process was. Frame count is checked against the video's own reported
# duration, which `ffmpeg`'s constant frame rate makes an exact relation.
# ═══════════════════════════════════════════════════════════════════════════

# The `ffmpeg` and the `ffprobe` of FFMPEG_jll, which `ProjecturedVideo` encodes
# with, so the checks of a video run also where no `ffmpeg` is installed.
const _FFMPEG = ProjecturedVideo.VideoModule.FFMPEG

# `(duration_seconds, frame_count)` from `ffprobe`, each `nothing` when the probe
# does not report it.
function _probe_video(filename::AbstractString)
    text = read(`$(_FFMPEG.ffprobe()) -v error -count_frames -select_streams v:0
                     -show_entries format=duration:stream=nb_read_frames
                     -of default=noprint_wrappers=1 $filename`, String)
    duration_m = match(r"duration=([\d.]+)", text)
    frames_m = match(r"nb_read_frames=(\d+)", text)
    duration = duration_m === nothing ? nothing : parse(Float64, duration_m.captures[1])
    frames = frames_m === nothing ? nothing : parse(Int, frames_m.captures[1])
    (duration, frames)
end

"""
    test_application_video()

Smoke test for `record_application_video`.
"""
function test_application_video()
@testset "record_application_video" begin
    fps = 10
    initial_hold = 0.3
    final_hold = 0.5
    # Ctrl+T opens a tab on an empty placeholder, Insert turns it into the name
    # buffer, "repl" names the tool, and Enter commits it — the same key
    # sequence `warm_application` uses to open the evaluator.
    timeline = Any[
        (event = KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0), hold = 0.2),
        (event = KeyDown(:insert, ModifierKeys(); time = 0.0),        hold = 0.2),
        make_typein_gestures("repl"; hold = 0.1, jitter = 0.0)...,
        (event = KeyPress('\n'; time = 0.0),        hold = 0.5),
    ]
    expected_duration = initial_hold + sum(e.hold for e in timeline) + final_hold

    filename = tempname() * ".mp4"
    elapsed = Ref(0.0)
    ok = try
        elapsed[] = @elapsed record_application_video(String[], timeline, filename;
                                 width = 480, height = 360, fps = fps,
                                 assistant = :none, root = mktempdir(),
                                 initial_hold = initial_hold, final_hold = final_hold,
                                 supersample = 1)
        true
    catch e
        @warn "record_application_video test skipped (ffmpeg unavailable?): $e"
        false
    end
    if ok
        @test isfile(filename)
        @test filesize(filename) > 0
        duration, frames = _probe_video(filename)
        if duration !== nothing
            @test expected_duration * 0.5 <= duration
            @test duration <= elapsed[] + 1.0
        end
        frames === nothing || duration === nothing ||
            @test isapprox(frames, duration * fps; atol = 2)
        rm(filename; force = true)
    end
end

@testset "in video time, the editor's clock moves one frame of time per frame" begin
    fps = 10
    initial_hold = 0.3
    final_hold = 0.5
    # An await entry notes the time of the editor's clock where the schedule
    # reaches it, and lets the schedule go on at once. Its hold is only a cap on
    # the wait, and a cap of 0 would end the wait before the note is taken.
    times = Float64[]
    note_time = (await = editor -> (push!(times, get_clock_time(editor.clock)); true), hold = 1.0)
    timeline = Any[
        note_time,
        (event = KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0), hold = 1.0),
        note_time,
    ]
    filename = tempname() * ".mp4"
    ok = try
        record_application_video(String[], timeline, filename;
                                 width = 480, height = 360, fps = fps,
                                 assistant = :none, root = mktempdir(),
                                 initial_hold = initial_hold, final_hold = final_hold,
                                 supersample = 1, video_time = true)
        true
    catch e
        @warn "record_application_video test skipped (ffmpeg unavailable?): $e"
        false
    end
    if ok
        # The clock shows the schedule's time, whatever the frames cost to make:
        # the first note at the initial hold, the second one second later.
        @test length(times) == 2
        @test isapprox(times[1], initial_hold; atol = 1 / fps)
        @test isapprox(times[2] - times[1], 1.0; atol = 1 / fps)
        # The video is as long as the schedule, frame for frame.
        _, frames = _probe_video(filename)
        expected = initial_hold + 1.0 + final_hold
        frames === nothing || @test abs(frames - expected * fps) <= 1
        rm(filename; force = true)
    end
end

# The frames of `bytes`, raw RGB frames of `width` by `height`, each as rows of
# pixels.
_split_frames(bytes, width::Integer, height::Integer) =
    [[(Int(bytes[at + 3 * (y * width + x) + 1]), Int(bytes[at + 3 * (y * width + x) + 2]),
       Int(bytes[at + 3 * (y * width + x) + 3])) for y in 0:height - 1, x in 0:width - 1]
     for at in 0:width * height * 3:length(bytes) - width * height * 3]

# The last frame of a video as rows of RGB pixels, or `nothing` when the video
# has no frame of `width` by `height`.
function _read_last_frame(filename::AbstractString, width::Integer, height::Integer)
    bytes = read(`$(_FFMPEG.ffmpeg()) -v error -sseof -0.1 -i $filename
                  -frames:v 1 -f rawvideo -pix_fmt rgb24 -`)
    length(bytes) == width * height * 3 || return nothing
    only(_split_frames(bytes, width, height))
end

# Every frame of a short video, in order.
_read_frames(filename::AbstractString, width::Integer, height::Integer) =
    _split_frames(read(`$(_FFMPEG.ffmpeg()) -v error -i $filename
                        -f rawvideo -pix_fmt rgb24 -`), width, height)

@testset "the pointer is drawn where the last mouse event left it" begin
    width, height = 480, 360
    timeline = Any[(event = MouseMove(300, 200, MouseButtons(), ModifierKeys(); time = 0.0), hold = 0.5)]
    # One folder for both takes: the Files pane shows its name.
    root = mktempdir()
    frames = map((true, false)) do pointer
        filename = tempname() * ".mp4"
        record_application_video(String[], timeline, filename; width = width, height = height, fps = 10,
                                 assistant = :none, root = root, initial_hold = 0.2, final_hold = 0.3,
                                 supersample = 1, video_time = true, pointer = pointer)
        frame = _read_last_frame(filename, width, height)
        rm(filename; force = true)
        frame
    end
    if !any(isnothing, frames)
        with_pointer, without = frames
        # The pixels that the pointer changed, beyond the noise of the encoder.
        changed = [Tuple(index) for index in CartesianIndices(with_pointer)
                   if maximum(abs.(with_pointer[index] .- without[index])) > 60]
        @test !isempty(changed)
        rows, columns = first.(changed), last.(changed)
        # Julia indices start at 1, pixels at 0.
        @test abs(minimum(columns) - 1 - 300) <= 2
        @test abs(minimum(rows) - 1 - 200) <= 2
        @test maximum(columns) - minimum(columns) <= 16
        @test maximum(rows) - minimum(rows) <= 24
    end
end
@testset "the views of the window and its Appearance tab draw with the appearance of the take" begin
    appearance = ProjecturedPlatform.Appearance()
    seen = Ref{Any}(nothing)
    timeline = Any[(await = editor -> (seen[] = ProjecturedPlatform.find_editor_appearance(; editor); true),
                    hold = 1.0)]
    filename = tempname() * ".mp4"
    try
        record_application_video(String[], timeline, filename; width = 480, height = 360, fps = 10,
                                 assistant = :none, root = mktempdir(), initial_hold = 0.2, final_hold = 0.3,
                                 supersample = 1, video_time = true, appearance)
    catch e
        @warn "record_application_video test: the encoding failed (ffmpeg unavailable?): $e"
    finally
        rm(filename; force = true)
    end
    # The tab and the keys change the appearance that the widgets of the window
    # draw with, so a step of a scale or an edit of a style shows.
    @test seen[] === appearance
    @test any(entry -> ProjecturedPlatform.get_theme_type(entry.theme) === ProjecturedPlatform.WidgetTheme,
              values(appearance.themes))
end
@testset "at a zoom the frame shows the window larger, and a click lands where the frame shows" begin
    width, height = 480, 360
    # The Evaluator button of the toolbar, the third after Explorer and Files, is
    # at (68, 43) in the window, so a frame at a zoom of 1.5 shows it at (102, 65).
    takes = map((1.0, 1.5)) do zoom
        opened = Ref(false)
        timeline = Any[(event = MouseClick(:left, 102, 65, 1, ModifierKeys(); time = 0.0), hold = 0.6),
                       (await = editor -> (opened[] = ProjecturedPlatform.find_pane("Evaluator"; editor) !== nothing;
                                           true), hold = 1.0)]
        filename = tempname() * ".mp4"
        record_application_video(String[], timeline, filename; width, height, fps = 10, assistant = :none,
                                 root = mktempdir(), initial_hold = 0.5, final_hold = 0.3, supersample = 1,
                                 video_time = true, pointer = false,
                                 appearance = ProjecturedPlatform.Appearance(zoom = zoom))
        frame = _read_last_frame(filename, width, height)
        rm(filename; force = true)
        (opened = opened[], frame)
    end
    # The click opens the evaluator only where the frame shows its button there.
    @test !takes[1].opened
    @test takes[2].opened
    # The menu text at the top left is half as tall again: the rows of its dark
    # pixels, in a box that holds "File" and ends above the toolbar.
    function text_rows(frame)
        rows = [y for y in 1:32 if any(x -> sum(frame[y, x]) < 300, 1:40)]
        isempty(rows) ? 0 : maximum(rows) - minimum(rows) + 1
    end
    if all(take -> take.frame !== nothing, takes)
        plain, zoomed = text_rows(takes[1].frame), text_rows(takes[2].frame)
        @test plain > 0
        @test zoomed >= 1.3 * plain
    end
end
@testset "a partial repaint draws what a full repaint draws" begin
    width, height = 480, 360
    # A mouse event first: from it on, the pointer is drawn over each frame.
    timeline = Any[
        (event = MouseMove(300, 200, MouseButtons(), ModifierKeys(); time = 0.0), hold = 0.2),
        (event = KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0), hold = 0.3),
        (event = KeyDown(:insert, ModifierKeys(); time = 0.0),        hold = 0.3),
        make_typein_gestures("repl"; hold = 0.1, jitter = 0.0)...,
        (event = KeyPress('\n'; time = 0.0),        hold = 0.5),
    ]
    root = mktempdir()
    take(; kwargs...) = begin
        filename = tempname() * ".mp4"
        record_application_video(String[], timeline, filename; width = width, height = height, fps = 10,
                                 assistant = :none, root = root, initial_hold = 0.2, final_hold = 0.3,
                                 supersample = 1, video_time = true, kwargs...)
        frame = _read_last_frame(filename, width, height)
        rm(filename; force = true)
        frame
    end
    full = take()
    partial = take(partial_render = true)
    outlined = take(partial_render = true, debug_dirty = true)
    held = take(partial_render = true, debug_dirty = true, debug_dirty_hold = 0.2)
    if !any(isnothing, (full, partial, outlined, held))
        # The kept surface, painted again only where something changed, ends as
        # the full paint ends, beyond the noise of the encoder.
        @test count(i -> maximum(abs.(full[i] .- partial[i])) > 60, CartesianIndices(full)) == 0
        # The outline of the last repaint stays on the frame.
        is_red(p) = p[1] > 180 && p[2] < 80 && p[3] < 80
        @test count(is_red, outlined) > count(is_red, partial)
        # With a hold, the outline goes when the hold is over: the last key is
        # more than 0.2 s before the last frame.
        @test count(is_red, held) < count(is_red, outlined)
    end
end

@testset "a take goes on past a paint that fails, with the fault on the frames it holds" begin
    width, height, fps = 480, 360, 10
    root = mktempdir()
    path = joinpath(root, "items.json")
    write(path, """[{"name": "tea", "price": 3}]""")
    # A JSON string whose text can not be computed makes the paint after the
    # insert fail. The frames then hold the last picture with the fault on it,
    # until the string shows its fault in its place and the window paints again.
    break_paint = (await = editor -> begin
                       items = get_edited_document(find_pane("items.json"; editor))
                       broken = JsonString("tea")
                       set_cell_computation!(getfield(broken, :value),
                                             () -> error("the text of this string can not be computed"))
                       insert_elements!(items, 1, [broken]; editor)
                       true
                   end, hold = 1.0)
    timeline = Any[
        (event = MouseMove(300, 200, MouseButtons(), ModifierKeys(); time = 0.0), hold = 0.2),
        break_paint,
        (event = KeyDown(:down, ModifierKeys(); time = 0.0), hold = 1.5),
        (event = KeyDown(:up, ModifierKeys(); time = 0.0), hold = 0.5),
    ]
    schedule = 0.2 + 0.2 + 1.5 + 0.5 + 0.3
    filename = tempname() * ".mp4"
    # In video time, so the frames are the same on a slow and on a fast machine.
    recording = @async record_application_video([path], timeline, filename;
                                                width = width, height = height, fps = fps,
                                                assistant = :none, root = root,
                                                initial_hold = 0.2, final_hold = 0.3,
                                                supersample = 1, video_time = true)
    # A recorder that waits for a frame that never comes does not end.
    @test timedwait(() -> istaskdone(recording), 180.0) === :ok
    @test istaskdone(recording) && !istaskfailed(recording)
    if istaskdone(recording) && !istaskfailed(recording)
        duration, _ = _probe_video(filename)
        duration === nothing || @test schedule * 0.5 <= duration
        frames = _read_frames(filename, width, height)
        # A held picture carries the red band of the fault across the bottom; this
        # row is in the band, above its text.
        is_red(p) = p[1] > 170 && p[2] < 100 && p[3] < 100
        has_band(frame) = count(is_red, frame[height - 25, :]) > 0.8 * width
        # The insert is at 0.4 s, and the first frame with the band is its frame or
        # the next one.
        @test findfirst(has_band, frames) in round(Int, 0.4 * fps) .+ (1:2)
        # The window paints again, so the take ends on a frame with no band.
        @test !isempty(frames) && !has_band(last(frames))
        rm(filename; force = true)
    end
end
end # test_application_video
