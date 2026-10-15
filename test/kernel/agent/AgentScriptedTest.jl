# `ScriptedAgentConnection` of `ProjecturedKernelExample` — the external agent
# that the tests of the assistant play: the events of the work of an agent as
# steps of a turn, the queue of a session for the events between two prompts,
# and the cancel of a subagent and the stop of a background task, which it
# records.

using Test
using ProjecturedKernel.AgentModule
import ProjecturedKernel.LlmModule: LlmMessage, LlmText, LlmContent, LlmTextStart, LlmTextDelta, LlmTextStop
using ProjecturedKernelExample: ScriptedAgentConnection

function test_scripted_agent_connection()
@testset "a scripted agent connection" begin

    @testset "it plays the events of the work of an agent as steps" begin
        steps = Any[
            AgentSubagentUpdate("sub-1"; title = "Explore", state = :running, can_cancel = true),
            AgentSubagentUpdate("sub-1"; event = LlmMessage(:user, LlmContent[LlmText("Find the bug")])),
            AgentSubagentUpdate("sub-1"; event = LlmTextStart()),
            AgentSubagentUpdate("sub-1"; event = LlmTextDelta("Found it.")),
            AgentSubagentUpdate("sub-1"; event = LlmTextStop()),
            AgentSubagentUpdate("sub-1"; state = :idle, stop_reason = :end_turn),
            AgentBackgroundTaskUpdate("task-1"; kind = :local_bash, title = "sleep 10", status = :running,
                                      start_time = 1.0e9, can_stop = true),
            AgentPlanUpdate([AgentPlanEntry("Read", :high, :completed; id = "1"),
                             AgentPlanEntry("Write", :high, :pending; id = "2", blocked_by = ["1"])]; id = "tasks"),
            AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode", markdown = "# Plan"),
            AgentNoticeUpdate(:warning, "API retry 1 of 3", ""),
            AgentCompactionUpdate("c1", :completed, nothing),
            AgentSessionInfoUpdate(nothing; process_id = 4242)]
        connection = ScriptedAgentConnection([steps])
        start_agent_connection!(connection)
        session_id = open_agent_session!(connection)
        events = Any[]
        @test send_agent_prompt!(connection, session_id, [LlmText("Go")];
                                 on_event = event -> push!(events, event)) === :end_turn
        @test events == steps
    end

    @testset "a session keeps its queue, which takes the events between two prompts" begin
        connection = ScriptedAgentConnection([Any[
            AgentBackgroundTaskUpdate("task-1"; title = "sleep 10", status = :running, can_stop = true)]])
        start_agent_connection!(connection)
        queue = AgentEventQueue()
        session_id = open_agent_session!(connection; events = queue)
        @test only(connection.sessions).events === queue
        events = Any[]
        send_agent_prompt!(connection, session_id, [LlmText("Go")]; on_event = event -> push!(events, event))
        @test only(events).status === :running
        @test isempty(take_agent_events!(queue))
        # The task ends after the prompt: the agent puts its end into the queue.
        ended = AgentBackgroundTaskUpdate("task-1"; status = :completed, end_time = 1.0e9, can_stop = false)
        put_agent_event!(only(connection.sessions).events, ended)
        @test take_agent_events!(queue) == Any[ended]
        # A session opened with no queue keeps none.
        open_agent_session!(connection)
        @test connection.sessions[2].events === nothing
    end

    @testset "it records the cancel of a subagent and the stop of a background task" begin
        connection = ScriptedAgentConnection([])
        start_agent_connection!(connection)
        session_id = open_agent_session!(connection)
        @test cancel_agent_subagent!(connection, session_id, "sub-1") === nothing
        @test connection.subagent_cancels == [session_id => "sub-1"]
        @test stop_agent_background_task!(connection, session_id, "task-1") === true
        @test stop_agent_background_task!(connection, session_id, "task-2") === true
        @test connection.background_task_stops == [session_id => "task-1", session_id => "task-2"]
    end

end
end # test_scripted_agent_connection
