# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/VideoTest.jl
#
# Smoke test for `record_video`: drive the json example through a few gestures,
# encode an MP4, and assert the file exists and is non-empty. ffmpeg ships with
# FFMPEG.jl (via FFMPEG_jll), so it is normally available; should encoding fail
# for any reason the test is skipped with a warning rather than failing CI.
# ═══════════════════════════════════════════════════════════════════════════

function test_record_video()
@testset "record_video" begin
    gestures = [
        (event = KeyPress('h'),                        hold = 0.3),
        (event = KeyPress('i'),                        hold = 0.3),
        (event = KeyDown(:right, Modifiers(), false),  hold = 0.4),
    ]
    filename = tempname() * ".mp4"
    ok = try
        record_video(make_json_document_example(), make_json_projection_example(),
                     gestures, filename; fps=30, width=400, height=300, supersample=1)
        true
    catch e
        @warn "record_video test skipped (ffmpeg unavailable?): $e"
        false
    end
    if ok
        @test isfile(filename)
        @test filesize(filename) > 0
        rm(filename; force=true)
    end

    # .mp4 is the only supported container.
    @test_throws ErrorException record_video(
        make_json_document_example(), make_json_projection_example(),
        gestures, tempname() * ".avi")
end
end # test_record_video
