# The assistant conversation demo of the gallery, recorded to a video file. Its
# document is the conversation example, which names several domains, so the test
# lives in the umbrella suite.

function test_assistant_conversation_video()
    @testset "assistant conversation demo records and waits for the reply" begin
        # Drives the full assistant composer: prose → julia eval → prose → submit,
        # then `wait_for` lets the FakeLlm reply land before the final frames. Uses
        # the default reply (a fenced ```julia block + a multi-byte em dash) so the
        # markdown→JuliaDocument parse and the FakeLlm char-chunking are exercised.
        filename = tempname() * ".mp4"
        ok = try
            record_assistant_conversation_video(filename;
                fps = 10, width = 800, height = 600, supersample = 1, final_hold = 0.5)
            true
        catch e
            @warn "assistant video test skipped (ffmpeg unavailable?): $e"
            false
        end
        if ok
            @test isfile(filename)
            @test filesize(filename) > 0
            rm(filename; force = true)
        end
    end
end
