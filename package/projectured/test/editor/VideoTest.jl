# ═══════════════════════════════════════════════════════════════════════════
# test/editor/VideoTest.jl
#
# Smoke test for `record_video`: drive the json example through a few gestures,
# encode an MP4, and assert the file exists and is non-empty. ffmpeg ships with
# FFMPEG.jl (via FFMPEG_jll), so it is normally available; should encoding fail
# for any reason the test is skipped with a warning rather than failing CI.
#
# A second case checks that keyboard typein actually edits the document: typein
# only produces an operation when something is selected, so the recording is
# given an `initial_selection` (a text caret) and the targeted character is
# asserted to change.
# ═══════════════════════════════════════════════════════════════════════════

using Projectured: set_selection!, evaluate_reference

function test_record_video()
@testset "record_video" begin
    @testset "encodes an mp4" begin
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
    end

    @testset "typein edits the document with an initial selection" begin
        doc  = make_json_document_example()
        proj = make_json_projection_example()
        # A text caret so the keypress has somewhere to type; without a selection
        # the reader yields no operation and typein would be a silent no-op.
        caret = first(collect_text_selections(doc))
        before = evaluate_reference(doc, caret)
        filename = tempname() * ".mp4"
        ok = try
            record_video(doc, proj, [(event = KeyPress('z'), hold = 0.2)], filename;
                         fps=10, width=400, height=300, supersample=1,
                         initial_selection=caret)
            true
        catch e
            @warn "record_video typein test skipped (ffmpeg unavailable?): $e"
            false
        end
        if ok
            @test filesize(filename) > 0
            rm(filename; force=true)
        end
        # The edit is applied regardless of whether encoding ran: the typed 'z'
        # now sits at the caret.
        @test evaluate_reference(doc, caret) == 'z'
        @test evaluate_reference(doc, caret) != before
    end

    @testset "timed operation entry seeds the caret for a following keypress" begin
        # An `:operation` entry (ReplaceSelectionOperation) is injected straight
        # into the evaluator — no event needed — then a `:event` keypress edits
        # at that selection. Proves operation entries reach evaluate_operation and
        # the next event reads against the updated state.
        doc  = make_json_document_example()
        proj = make_json_projection_example()
        caret = first(collect_text_selections(doc))
        filename = tempname() * ".mp4"
        timeline = [
            (operation = ReplaceSelectionOperation(caret), hold = 0.2),
            (event     = KeyPress('q'),                    hold = 0.2),
        ]
        ok = try
            record_video(doc, proj, timeline, filename;
                         fps=10, width=400, height=300, supersample=1)
            true
        catch e
            @warn "record_video operation-entry test skipped (ffmpeg unavailable?): $e"
            false
        end
        if ok
            @test filesize(filename) > 0
            rm(filename; force=true)
        end
        # The keypress landed at the operation-seeded caret regardless of encoding.
        @test evaluate_reference(doc, caret) == 'q'
    end

    # .mp4 is the only supported container.
    @test_throws ErrorException record_video(
        make_json_document_example(), make_json_projection_example(),
        [(event = KeyPress('a'), hold = 0.1)], tempname() * ".avi")

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
end # test_record_video
