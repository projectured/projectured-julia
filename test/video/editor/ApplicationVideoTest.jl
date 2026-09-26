# ═══════════════════════════════════════════════════════════════════════════
# test/video/editor/ApplicationVideoTest.jl
#
# Smoke test for `record_application_video`: a short clip of the application
# window with no file — the navigator, an empty tab, no assistant — typing
# `repl` into a freshly opened tab and pressing Enter. Asserts the file exists
# and, when `ffprobe` is available, bounds its reported duration rather than
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

# `(duration_seconds, frame_count)` from `ffprobe`, or `(nothing, nothing)`
# when `ffprobe` is not on `PATH` or the probe fails.
function _probe_video(filename::AbstractString)
    text = try
        read(`ffprobe -v error -count_frames -select_streams v:0
                       -show_entries format=duration:stream=nb_read_frames
                       -of default=noprint_wrappers=1 $filename`, String)
    catch e
        @warn "ffprobe unavailable, skipping its assertions: $e"
        return (nothing, nothing)
    end
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
        (event = KeyDown(:return, ModifierKeys(); time = 0.0),        hold = 0.5),
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

# The last frame of a video as rows of RGB pixels, or `nothing` when `ffmpeg` is
# not on `PATH`.
function _read_last_frame(filename::AbstractString, width::Integer, height::Integer)
    bytes = try
        read(`ffmpeg -v error -sseof -0.1 -i $filename -frames:v 1 -f rawvideo -pix_fmt rgb24 -`)
    catch e
        @warn "ffmpeg unavailable, skipping the frame assertions: $e"
        return nothing
    end
    length(bytes) == width * height * 3 || return nothing
    [(Int(bytes[3 * (y * width + x) + 1]), Int(bytes[3 * (y * width + x) + 2]), Int(bytes[3 * (y * width + x) + 3]))
     for y in 0:height - 1, x in 0:width - 1]
end

@testset "the pointer is drawn where the last mouse event left it" begin
    width, height = 480, 360
    timeline = Any[(event = MouseMove(300, 200, MouseButtons(), ModifierKeys(); time = 0.0), hold = 0.5)]
    # One folder for both takes: the navigator shows its name.
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
@testset "a partial repaint draws what a full repaint draws" begin
    width, height = 480, 360
    # A mouse event first: from it on, the pointer is drawn over each frame.
    timeline = Any[
        (event = MouseMove(300, 200, MouseButtons(), ModifierKeys(); time = 0.0), hold = 0.2),
        (event = KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0), hold = 0.3),
        (event = KeyDown(:insert, ModifierKeys(); time = 0.0),        hold = 0.3),
        make_typein_gestures("repl"; hold = 0.1, jitter = 0.0)...,
        (event = KeyDown(:return, ModifierKeys(); time = 0.0),        hold = 0.5),
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
    if !any(isnothing, (full, partial, outlined))
        # The kept surface, painted again only where something changed, ends as
        # the full paint ends, beyond the noise of the encoder.
        @test count(i -> maximum(abs.(full[i] .- partial[i])) > 60, CartesianIndices(full)) == 0
        # The outline of the last repaint stays on the frame.
        is_red(p) = p[1] > 180 && p[2] < 80 && p[3] < 80
        @test count(is_red, outlined) > count(is_red, partial)
    end
end
end # test_application_video
