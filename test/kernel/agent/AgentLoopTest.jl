# The agent loop: what `run_turn!` answers, and what it sends to `on_event`, for
# a scripted model over a target that no editor loop runs.

using Test
import ProjecturedKernel.AgentModule: Agent, run_turn!, AgentToolResult
import ProjecturedKernel.FaultModule: FaultStore, get_fault_records
import ProjecturedKernel.LlmModule: LlmMessage, LlmFailure, LlmTextStart, LlmTurnEnd
import ProjecturedKernel.ToolModule: Tool, ToolSet, register_tool!
using ProjecturedKernelExample: ScriptedLlm, make_scripted_turn, make_scripted_run,
                                make_scripted_say

# A target that keeps a fault store, as an editor does.
struct AgentLoopTarget
    faults::FaultStore
end
ProjecturedKernel.FaultModule.get_fault_store(target::AgentLoopTarget) = target.faults

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

    @testset "a tool that throws records a fault in the store of the target" begin
        tools = _make_agent_loop_tools((target, arguments) -> error("no such pane"))
        llm = ScriptedLlm([_make_agent_loop_call_round(),
                           _make_agent_loop_answer_round("It failed.")])
        target = AgentLoopTarget(FaultStore())
        events = Any[]
        stop = run_turn!(Agent(llm, tools), target; messages = () -> LlmMessage[],
                         on_event = event -> push!(events, event))
        @test stop === :end_turn
        @test only(_get_agent_tool_results(events)).is_error
        record = only(get_fault_records(target.faults))
        @test record.site === :tool
        @test record.origin === :probe
        @test occursin("no such pane", record.message)
    end

    @testset "a tool name that no tool answers gives a result marked as an error" begin
        tools = _make_agent_loop_tools((target, arguments) -> "unused")
        round = make_scripted_turn(
            make_scripted_run(""; tool_id = "tu_1", tool_name = "agent_loop_missing");
            stop_reason = "tool_use")
        llm = ScriptedLlm([round, _make_agent_loop_answer_round("Done.")])
        stop, events = _run_agent_loop_turn(Agent(llm, tools))
        result = only(_get_agent_tool_results(events))
        @test stop === :end_turn
        @test result.is_error
        @test occursin("KeyError", result.output)
        @test occursin("agent_loop_missing", result.output)
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

    @testset "a failure in the stream ends the turn with :error" begin
        calls = Ref(0)
        tools = _make_agent_loop_tools((target, arguments) -> (calls[] += 1; "ran"))
        # The round streams a whole tool call, and then the failure.
        round = vcat(make_scripted_run(""; tool_id = "tu_1", tool_name = "probe"),
                     NamedTuple[(event = LlmFailure("overloaded"), delay = 0.0)])
        stop, events = _run_agent_loop_turn(Agent(ScriptedLlm([round]), tools))
        @test stop === :error
        @test calls[] == 0
        @test any(event -> event isa LlmFailure, events)
        @test isempty(_get_agent_tool_results(events))
    end

    # The answer is the stop reason of the last round that ran: the model still
    # waits for tools when the cap ends the turn.
    @testset "the round cap ends a turn that keeps calling tools" begin
        calls = Ref(0)
        tools = _make_agent_loop_tools((target, arguments) -> (calls[] += 1; "ran"))
        llm = ScriptedLlm([_make_agent_loop_call_round() for _ in 1:3])
        agent = Agent(llm, tools; max_rounds = 2)
        stop = @test_logs (:warn, r"round cap") match_mode = :any run_turn!(
            agent, (name = :target,); messages = () -> LlmMessage[],
            on_event = event -> nothing)
        @test stop === :tool_use
        @test calls[] == 2
        @test llm.cursor == 2
    end

    @testset "the results follow the round that asked, in the order of the calls" begin
        tools = _make_agent_loop_tools((target, arguments) -> "ran")
        round = make_scripted_turn(
            make_scripted_run(""; tool_id = "tu_1", tool_name = "probe"),
            make_scripted_run(""; tool_id = "tu_2", tool_name = "probe");
            stop_reason = "tool_use")
        llm = ScriptedLlm([round, _make_agent_loop_answer_round("Done.")])
        stop, events = _run_agent_loop_turn(Agent(llm, tools))
        @test stop === :end_turn
        @test [result.call.id for result in _get_agent_tool_results(events)] ==
              ["tu_1", "tu_2"]
        turn_end = findfirst(event -> event isa LlmTurnEnd, events)
        @test events[turn_end].stop_reason === :tool_use
        @test turn_end < findfirst(event -> event isa AgentToolResult, events)
        @test findlast(event -> event isa AgentToolResult, events) <
              findfirst(event -> event isa LlmTextStart, events)
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
