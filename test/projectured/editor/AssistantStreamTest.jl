# An answer of the built-in assistant streams into a running editor through the
# feed of the agent events: each event of the turn goes into the queue of the turn,
# and a frame applies the queue with no call for each event. So a stream of many
# deltas runs no held frame for a delta, and only the calls of the turn, such as
# the call that makes the messages of a round, run as code units.

# A backend that shows held frames and counts the code units that prepare them, and
# paints nothing: the window of a test in which the loop runs.
mutable struct _StreamHeldFrameBackend <: BackendModule.Backend
    prepared::Int
end
_StreamHeldFrameBackend() = _StreamHeldFrameBackend(0)

BackendModule.initialize_backend!(::_StreamHeldFrameBackend) = nothing
BackendModule.quit_backend!(::_StreamHeldFrameBackend) = nothing
BackendModule.take_from_devices!(::_StreamHeldFrameBackend, devices) = nothing
BackendModule.write_to_devices!(::_StreamHeldFrameBackend, devices, output) = nothing
BackendModule.wait_for_input(::_StreamHeldFrameBackend, devices, timeout) = sleep(min(timeout, 0.001))
BackendModule.prepare_held_frames!(backend::_StreamHeldFrameBackend, devices, parts) =
    (backend.prepared += 1; nothing)
BackendModule.run_held_frame!(::_StreamHeldFrameBackend, devices, state::BackendModule.HeldFrameState) =
    (sleep(0.001); :none)
BackendModule.end_held_frames!(::_StreamHeldFrameBackend, devices) = nothing

# A model that records the request of each round and streams the rounds of a
# scripted model.
struct _StreamRecordingLlm <: LlmModule.Llm
    inner::Any
    requests::Vector{Any}
end
_StreamRecordingLlm(inner) = _StreamRecordingLlm(inner, Any[])

function LlmModule.stream_turn(llm::_StreamRecordingLlm, request; on_event::Function)
    push!(llm.requests, request)
    LlmModule.stream_turn(llm.inner, request; on_event)
end

# Run the loop of `editor` until the turn of `a` that a submit starts ends, or 60
# seconds pass, and quit it.
function _stream_run_turn!(editor, a::Assistant, prompt::AbstractString)
    a.input.value = prompt
    post_operation!(editor, SubmitProseOperation(a))
    driver = @async try
        # The turn starts in the first frame, and its status says when it ends.
        timedwait(() -> a.status === :streaming, 30.0; pollint = 0.01)
        timedwait(() -> a.status !== :streaming, 60.0; pollint = 0.01)
    finally
        post_operation!(editor, QuitEditorOperation())
    end
    run_editor!(editor)
    wait(driver)
    nothing
end

_stream_make_editor(a::Assistant, backend; fault_policy = make_strict_fault_policy()) =
    Editor(a, make_assistant_projection_example(); backend, devices = Device[],
           tools = register_default_tools!(ToolSet()), fault_policy)

# The queues of turns that the feeds of `editor` still hold.
_stream_count_turn_sources(editor) =
    sum((count(source -> source isa AssistantModule._TurnEventSource, feed.sources)
         for feed in editor.feeds if feed isa AgentEventFeed); init = 0)

# A model that streams a text and then fails.
struct _StreamFailingLlm <: LlmModule.Llm end

function LlmModule.stream_turn(::_StreamFailingLlm, request; on_event::Function)
    on_event(LlmTextStart())
    foreach(word -> on_event(LlmTextDelta(word)), ["Half ", "an ", "answer."])
    error("the model failed")
end

_stream_collect_answer_text(a::Assistant) =
    join((_text_to_string(part.content) for turn in collect(a.conversation.turns)
          if turn.role === :assistant for part in collect(turn.parts)), "\n")

# Whether this process can run a code unit on a thread other than the one of this
# task, which held frames need.
_stream_has_code_unit_thread() =
    EditorModule._find_code_unit_place(Threads.threadid()) !== nothing

# An assistant whose last turn is an answer of `count` paragraphs of 100 words, and
# the part of that answer.
function _stream_make_long_answer(count::Integer)
    paragraph = join(("word$i" for i in 1:100), " ")
    part = ConversationPart(make_text_block(join(fill(paragraph, count), "\n")))
    a = Assistant(; conversation = ConversationConversation([
        ConversationTurn(:user, [ConversationPart("Write.")]),
        ConversationTurn(:assistant, [part])]))
    (a, part)
end

# The output cells that one delta at the end of an answer of `count` paragraphs
# invalidates, and the output objects that it makes again.
function _stream_measure_delta_locality(count::Integer)
    a, part = _stream_make_long_answer(count)
    report = measure_printer_locality(a, make_assistant_projection_example(),
                                      _ -> AssistantModule._append_text_delta!(part, " more"))
    (; invalidated = length(report.invalidated), lost = report.lost_objects, report.errors)
end

function test_assistant_stream()
@testset "an answer streams into a running editor through the feed of the agent events" begin
    @testset "with no loop, each event applies at once and a turn leaves no queue" begin
        a = Assistant(; llm = ScriptedLlm([_final_text_script("Done at once.")]))
        editor = _stream_make_editor(a, HeadlessBackend())
        for prompt in ("One.", "Two.")
            a.input.value = prompt
            evaluate_operation(editor, SubmitProseOperation(a))
            @test timedwait(() -> a.status === :idle, 30.0; pollint = 0.01) === :ok
            a.llm = ScriptedLlm([_final_text_script("Done at once.")])
        end
        @test count(turn -> any(part -> occursin("Done at once.", _text_to_string(part.content)),
                                collect(turn.parts)), collect(a.conversation.turns)) == 2
        @test _stream_count_turn_sources(editor) == 0
    end
    @testset "a delta at the end of a long answer changes only the end of its print" begin
        small = _stream_measure_delta_locality(10)
        large = _stream_measure_delta_locality(1_000)
        @test isempty(small.errors) && isempty(large.errors)
        # 100 times the answer: the same work for a delta, with some room.
        @test large.invalidated <= 2 * small.invalidated + 10
        @test large.lost <= 2 * small.lost + 10
    end

    if !_stream_has_code_unit_thread()
        # @broken: this process has no second thread, so a code unit runs inline and no held frame shows
        @test_broken false
    else
        @testset "a stream of 200 deltas runs no held frame for a delta" begin
            words = ["word$i " for i in 1:200]
            llm = ScriptedLlm([make_scripted_turn(make_scripted_say(join(words); chunk_words = 1,
                                                                    delay = 0.002))])
            a = Assistant(; llm)
            backend = _StreamHeldFrameBackend()
            editor = _stream_make_editor(a, backend)
            _stream_run_turn!(editor, a, "Count.")
            @test a.status === :idle
            @test occursin("word1 ", _stream_collect_answer_text(a))
            @test occursin("word200", _stream_collect_answer_text(a))
            # The calls of the turn: the read of its settings, the messages of the
            # round, the end of the round, and the steps of its start and its end.
            # Each delta in a call of its own would add a unit for each frame that
            # drains one.
            @test 3 <= backend.prepared <= 12
            @test _stream_count_turn_sources(editor) == 0
        end

        @testset "the messages of a round hold the text of the round before it" begin
            inner = ScriptedLlm([
                vcat(NamedTuple[_ev(LlmTextStart()), _ev(LlmTextDelta("First ")),
                                _ev(LlmTextDelta("round.")), _ev(LlmTextStop())],
                     _tool_use_script("tu_1", "wait", Dict{String,Any}())),
                _final_text_script("Second round.")])
            llm = _StreamRecordingLlm(inner)
            a = Assistant(; llm)
            editor = _stream_make_editor(a, _StreamHeldFrameBackend())
            _stream_run_turn!(editor, a, "Two rounds.")
            @test length(llm.requests) == 2
            second = llm.requests[2].messages
            @test any(message -> message.role === :assistant &&
                                 any(content -> content isa LlmText &&
                                                occursin("First round.", content.text),
                                     message.content),
                      second)
            # The text of the first round, the call of its tool and the text of the
            # second round stand in the turn in this order.
            parts = collect(last(collect(a.conversation.turns)).parts)
            first_text = findfirst(part -> occursin("First round.", _text_to_string(part.content)), parts)
            tool = findfirst(part -> part.content isa EvaluatorForm, parts)
            second_text = findfirst(part -> occursin("Second round.", _text_to_string(part.content)), parts)
            @test first_text !== nothing && tool !== nothing && second_text !== nothing
            @test first_text < tool < second_text
        end

        @testset "a turn that fails shows its text before the error and leaves no queue" begin
            a = Assistant(; llm = _StreamFailingLlm())
            editor = _stream_make_editor(a, _StreamHeldFrameBackend();
                                fault_policy = FaultPolicy(is_console_enabled = false,
                                                           is_sound_enabled = false))
            _stream_run_turn!(editor, a, "Fail.")
            @test a.status === :error
            turns = collect(a.conversation.turns)
            answer = findfirst(turn -> any(part -> occursin("Half an answer.", _text_to_string(part.content)),
                                           collect(turn.parts)), turns)
            failure = findfirst(turn -> any(part -> occursin("the model failed", _text_to_string(part.content)),
                                            collect(turn.parts)), turns)
            @test answer !== nothing && failure !== nothing && answer < failure
            @test _stream_count_turn_sources(editor) == 0
        end
    end
end
end
