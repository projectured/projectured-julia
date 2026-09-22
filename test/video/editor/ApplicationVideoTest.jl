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
        (event = KeyDown(:t, ModifierKeys(ctrl = true)), hold = 0.2),
        (event = KeyDown(:insert, ModifierKeys()),        hold = 0.2),
        make_typein_gestures("repl"; hold = 0.1, jitter = 0.0)...,
        (event = KeyDown(:return, ModifierKeys()),        hold = 0.5),
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
end # test_application_video
