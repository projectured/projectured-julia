# An answer of the built-in assistant streams into a running editor through the
# feed of the agent events: each event of the turn goes into the queue of the turn,
# and a frame applies the queue with no call for each event. So a stream of many
# deltas runs no held frame for a delta, and only the calls of the turn, such as
# the call that makes the messages of a round, run as code units.

# A backend that shows held frames and counts the code units that prepare them, and
# paints nothing: the window of a test in which the loop runs.
mutable struct _AsHeldFrameBackend <: BackendModule.Backend
    prepared::Int
end
_AsHeldFrameBackend() = _AsHeldFrameBackend(0)

BackendModule.initialize_backend!(::_AsHeldFrameBackend) = nothing
BackendModule.quit_backend!(::_AsHeldFrameBackend) = nothing
BackendModule.take_from_devices!(::_AsHeldFrameBackend, devices) = nothing
BackendModule.write_to_devices!(::_AsHeldFrameBackend, devices, output) = nothing
BackendModule.wait_for_input(::_AsHeldFrameBackend, devices, timeout) = sleep(min(timeout, 0.001))
BackendModule.prepare_held_frames!(backend::_AsHeldFrameBackend, devices, parts) =
    (backend.prepared += 1; nothing)
BackendModule.run_held_frame!(::_AsHeldFrameBackend, devices, state::BackendModule.HeldFrameState) =
    (sleep(0.001); :none)
BackendModule.end_held_frames!(::_AsHeldFrameBackend, devices) = nothing

# A model that records the request of each round and streams the rounds of a
# scripted model.
struct _AsRecordingLlm <: LlmModule.Llm
    inner::Any
    requests::Vector{Any}
end
_AsRecordingLlm(inner) = _AsRecordingLlm(inner, Any[])

function LlmModule.stream_turn(llm::_AsRecordingLlm, request; on_event::Function)
    push!(llm.requests, request)
    LlmModule.stream_turn(llm.inner, request; on_event)
end

# Run the loop of `editor` until the turn of `a` that a submit starts ends, or 60
# seconds pass, and quit it.
function _as_run_turn!(editor, a::Assistant, prompt::AbstractString)
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

_as_editor(a::Assistant, backend) =
    Editor(a, make_assistant_projection_example(); backend, devices = Device[],
           tools = register_default_tools!(ToolSet()))

_as_answer_text(a::Assistant) =
    join((_text_to_string(part.content) for turn in collect(a.conversation.turns)
          if turn.role === :assistant for part in collect(turn.parts)), "\n")

# Whether this process can run a code unit on a thread other than the one of this
# task, which held frames need.
_as_has_code_unit_thread() =
    EditorModule._find_code_unit_place(Threads.threadid()) !== nothing

function test_assistant_stream()
@testset "an answer streams into a running editor through the feed of the agent events" begin
    if !_as_has_code_unit_thread()
        # @broken: this process has no second thread, so a code unit runs inline and no held frame shows
        @test_broken false
    else
        @testset "a stream of 200 deltas runs no held frame for a delta" begin
            words = ["word$i " for i in 1:200]
            llm = ScriptedLlm([make_scripted_turn(make_scripted_say(join(words); chunk_words = 1,
                                                                    delay = 0.002))])
            a = Assistant(; llm)
            backend = _AsHeldFrameBackend()
            editor = _as_editor(a, backend)
            _as_run_turn!(editor, a, "Count.")
            @test a.status === :idle
            @test occursin("word1 ", _as_answer_text(a))
            @test occursin("word200", _as_answer_text(a))
            # The calls of the turn: the read of its settings, the messages of the
            # round, the end of the round, and the steps of its start and its end.
            # Each delta in a call of its own would add a unit for each frame that
            # drains one.
            @test backend.prepared <= 12
        end

        @testset "the messages of a round hold the text of the round before it" begin
            inner = ScriptedLlm([
                vcat(NamedTuple[_ev(LlmTextStart()), _ev(LlmTextDelta("First ")),
                                _ev(LlmTextDelta("round.")), _ev(LlmTextStop())],
                     _tool_use_script("tu_1", "wait", Dict{String,Any}())),
                _final_text_script("Second round.")])
            llm = _AsRecordingLlm(inner)
            a = Assistant(; llm)
            editor = _as_editor(a, _AsHeldFrameBackend())
            _as_run_turn!(editor, a, "Two rounds.")
            @test length(llm.requests) == 2
            second = llm.requests[2].messages
            @test any(message -> message.role === :assistant &&
                                 any(content -> content isa LlmText &&
                                                occursin("First round.", content.text),
                                     message.content),
                      second)
            @test occursin("Second round.", _as_answer_text(a))
        end
    end
end
end
