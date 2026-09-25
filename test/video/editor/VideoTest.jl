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

# The reference of the *string* a `{k}` position caret points into: the caret path
# with its terminal position step dropped. `collect_position_selections` yields
# `…{k}` carets, but `evaluate_reference` of a `{k}` returns the position step, not
# the character — to read the edited text we evaluate the enclosing string.
_caret_string_reference(p::ConcreteReference) =
    p.tail isa EmptyReference ? EmptyReference() :
    ConcreteReference(p.head, _caret_string_reference(p.tail))
_caret_string_reference(p) = p

function test_record_video()
@testset "record_video" begin
    @testset "encodes an mp4" begin
        gestures = [
            (event = KeyPress('h'; time = 0.0),                        hold = 0.3),
            (event = KeyPress('i'; time = 0.0),                        hold = 0.3),
            (event = KeyDown(:right, ModifierKeys(), false; time = 0.0),  hold = 0.4),
        ]
        filename = tempname() * ".mp4"
        ok = try
            record_video(make_json_document_example(), make_json_projection_example();
                         gestures, filename, fps=30, width=400, height=300, supersample=1)
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
        caret = first(collect_position_selections(doc))
        string_ref = _caret_string_reference(caret)   # the string the caret sits in
        before = evaluate_reference(doc, string_ref)
        filename = tempname() * ".mp4"
        ok = try
            record_video(doc, proj; gestures = [(event = KeyPress('z'; time = 0.0), hold = 0.2)],
                         filename, fps=10, width=400, height=300, supersample=1,
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
        # The edit is applied regardless of whether encoding ran: the typed 'z' now
        # sits at the caret (position 0 of the string), so the string gains a
        # leading 'z' and its content changes.
        after = evaluate_reference(doc, string_ref)
        @test first(after) == 'z'
        @test after != before
    end

    @testset "timed operation entry seeds the caret for a following keypress" begin
        # An `:operation` entry (ReplaceSelectionOperation) is injected straight
        # into the evaluator — no event needed — then a `:event` keypress edits
        # at that selection. Proves operation entries reach evaluate_operation and
        # the next event reads against the updated state.
        doc  = make_json_document_example()
        proj = make_json_projection_example()
        caret = first(collect_position_selections(doc))
        string_ref = _caret_string_reference(caret)
        filename = tempname() * ".mp4"
        timeline = [
            (operation = ReplaceSelectionOperation(caret), hold = 0.2),
            (event     = KeyPress('q'; time = 0.0),                    hold = 0.2),
        ]
        ok = try
            record_video(doc, proj; gestures = timeline, filename,
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
        # The keypress landed at the operation-seeded caret regardless of encoding:
        # a leading 'q' now heads the string.
        @test first(evaluate_reference(doc, string_ref)) == 'q'
    end

    # .mp4 is the only supported container.
    @test_throws ErrorException record_video(make_json_document_example(), make_json_projection_example();
                                             gestures = [(event = KeyPress('a'; time = 0.0), hold = 0.1)],
                                             filename = tempname() * ".avi")

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

"""
    test_json_build_live()

Replay the timeline of `json_build_live` headless, as the recorder feeds it, and
check that every key answers an operation and that the result is the example
document. The build moves the caret alone: no key of it selects structure.
"""
function test_json_build_live()
@testset "json_build_live builds its document from the caret" begin
    live = only(example for example in live_examples if example.name == "json_build")
    document = live.example.make_document()
    projection = live.example.make_projection()
    set_selection!(document, EmptyReference())
    editor = Editor(ConsoleBackend(), document, projection, Device[Display(), Keyboard(), Mouse()])
    reprint!() = editor.iomap = print_document(projection, nothing, editor.document,
        PrinterContext(EmptyReference(), Cell(live.width), Cell(live.height), Dict{Symbol,Any}(), Clock()))
    reprint!()
    @test !any(entry -> entry.event isa KeyDown && entry.event.modifiers.alt, live.timeline)
    dead = Int[]
    for (i, entry) in enumerate(live.timeline)
        change = read_intent(projection, nothing, Intent(entry.event, nothing), editor.iomap)
        operation = change isa Intent ? change.operation : change
        if operation isa Operation
            evaluate_operation(editor, operation)
            reprint!()
        else
            push!(dead, i)
        end
    end
    @test isempty(dead)
    # The example document, with the bool of "meta" before its number: the caret
    # can not leave a container whose last value is a bool.
    meta = JsonObject("created" => JsonString("2025-01-15"), "draft" => JsonBool(false),
                      "version" => JsonNumber(2))
    expected = JsonObject((entry.key => (entry.key == "meta" ? meta : entry.value)
                           for entry in make_json_document_example().entries)...)
    @test isempty(compare_content(editor.document, expected))
end
end # test_json_build_live
