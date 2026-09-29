# The agent loop: what `run_turn!` answers, and what it sends to `on_event`, for
# a scripted model over a target that no editor loop runs.

using Test
import ProjecturedKernel.AgentModule: Agent, run_turn!, AgentToolResult
import ProjecturedKernel.LlmModule: LlmMessage
import ProjecturedKernel.ToolModule: Tool, ToolSet, register_tool!
using ProjecturedKernelExample: ScriptedLlm, make_scripted_turn, make_scripted_run,
                                make_scripted_say

# A callable object in the place of a function: it keeps each event that it gets.
struct AgentLoopEventLog
    events::Vector{Any}
end
(log::AgentLoopEventLog)(event) = (push!(log.events, event); nothing)

# A tool set with one tool, `probe`, that `handler` answers.
function _make_agent_loop_tools(handler)
    set = ToolSet()
    register_tool!(set, Tool("probe", "a tool of the test", NamedTuple[], handler))
    set
end

# A round in which the model calls `probe` and waits for its answer.
_make_agent_loop_call_round() =
    make_scripted_turn(make_scripted_run(""; tool_id = "tu_1", tool_name = "probe");
                       stop_reason = "tool_use")

# A round in which the model says `text` and ends the turn.
_make_agent_loop_answer_round(text) =
    make_scripted_turn(make_scripted_say(text; delay = 0); stop_reason = "end_turn")

# One turn over a target that no editor loop runs: the stop reason, and each
# event that the turn sent.
function _run_agent_loop_turn(agent::Agent)
    events = Any[]
    stop = run_turn!(agent, (name = :target,); messages = () -> LlmMessage[],
                     on_event = event -> push!(events, event))
    stop, events
end

_get_agent_tool_results(events) = filter(event -> event isa AgentToolResult, events)

function test_agent_loop()
@testset "the agent loop" begin
    @testset "a tool that throws gives a result marked as an error" begin
        # The message of `error` holds neither "ERROR" nor "Error", so only the
        # throw marks the result.
        tools = _make_agent_loop_tools((target, arguments) -> error("no such pane"))
        llm = ScriptedLlm([_make_agent_loop_call_round(),
                           _make_agent_loop_answer_round("It failed.")])
        stop, events = _run_agent_loop_turn(Agent(llm, tools))
        result = only(_get_agent_tool_results(events))
        @test stop === :end_turn
        @test result.call.id == "tu_1"
        @test result.is_error
        @test occursin("no such pane", result.output)
    end

    @testset "a tool that answers gives a result not marked as an error" begin
        tools = _make_agent_loop_tools((target, arguments) -> "three words")
        llm = ScriptedLlm([_make_agent_loop_call_round(),
                           _make_agent_loop_answer_round("Done.")])
        stop, events = _run_agent_loop_turn(Agent(llm, tools))
        result = only(_get_agent_tool_results(events))
        @test stop === :end_turn
        @test !result.is_error
        @test result.output == "three words"
    end

    @testset "a stream with no terminal event ends the turn with :error" begin
        calls = Ref(0)
        tools = _make_agent_loop_tools((target, arguments) -> (calls[] += 1; "ran"))
        # The round streams text and a whole tool call, and ends with no turn end.
        round = vcat(make_scripted_say("Let me look."; delay = 0),
                     make_scripted_run(""; tool_id = "tu_1", tool_name = "probe"))
        stop, events = _run_agent_loop_turn(Agent(ScriptedLlm([round]), tools))
        @test stop === :error
        @test calls[] == 0
        @test isempty(_get_agent_tool_results(events))
    end

    @testset "an interrupt in a tool goes through the loop" begin
        tools = _make_agent_loop_tools((target, arguments) -> throw(InterruptException()))
        llm = ScriptedLlm([_make_agent_loop_call_round(),
                           _make_agent_loop_answer_round("Done.")])
        events = Any[]
        record = event -> push!(events, event)
        @test_throws InterruptException run_turn!(Agent(llm, tools), (name = :target,);
                                                  messages = () -> LlmMessage[],
                                                  on_event = record)
        @test isempty(_get_agent_tool_results(events))
    end

    @testset "a callable object is a callback" begin
        tools = _make_agent_loop_tools((target, arguments) -> "three words")
        llm = ScriptedLlm([_make_agent_loop_call_round(),
                           _make_agent_loop_answer_round("Done.")])
        log = AgentLoopEventLog(Any[])
        @test run_turn!(Agent(llm, tools), (name = :target,);
                        messages = () -> LlmMessage[], on_event = log) === :end_turn
        @test length(_get_agent_tool_results(log.events)) == 1
        @test !ismutabletype(Agent)
    end

    @testset "a round cap below one is refused" begin
        llm = ScriptedLlm([_make_agent_loop_answer_round("Done.")])
        @test_throws ArgumentError Agent(llm, ToolSet(); max_rounds = 0)
        @test_throws ArgumentError Agent(llm, ToolSet(); max_rounds = -1)
        @test Agent(llm, ToolSet(); max_rounds = 1).max_rounds == 1
    end
end
end # test_agent_loop
