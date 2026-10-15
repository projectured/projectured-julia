# `AgentModule` — the events of an external agent: the short constructors of a
# plan entry, a plan and the title of a session, the keyword constructors of the
# work of an agent, and the queue that takes the events of a session between
# two prompts from another task.

using Test
using ProjecturedKernel.AgentModule
import ProjecturedKernel.LlmModule: LlmMessage, LlmText, LlmContent, LlmTextDelta

function test_agent_connection_event()
@testset "the events of an external agent" begin

    @testset "a short plan entry and a short plan have empty ids and no other content" begin
        entry = AgentPlanEntry("Read", :high, :completed)
        @test (entry.content, entry.priority, entry.status) == ("Read", :high, :completed)
        @test (entry.id, entry.description, entry.active_title, entry.blocked_by) == ("", "", "", String[])
        # Two entries with the same fields are equal, also with a vector of blockers.
        @test entry == AgentPlanEntry("Read", :high, :completed)
        @test hash(entry) == hash(AgentPlanEntry("Read", :high, :completed))
        @test entry != AgentPlanEntry("Read", :high, :pending)
        plan = AgentPlanUpdate([entry])
        @test plan.entries == [AgentPlanEntry("Read", :high, :completed)]
        @test (plan.id, plan.markdown, plan.uri, plan.is_removed) == ("", nothing, nothing, false)
    end

    @testset "a plan entry has an id, a description, an active title and blockers" begin
        entry = AgentPlanEntry("Run the tests", :medium, :in_progress; id = "2", description = "All of them.",
                               active_title = "Running the tests", blocked_by = ["1"])
        @test (entry.id, entry.description, entry.active_title) == ("2", "All of them.", "Running the tests")
        @test entry.blocked_by == ["1"]
        @test entry == AgentPlanEntry("Run the tests", :medium, :in_progress; id = "2",
                                      description = "All of them.", active_title = "Running the tests",
                                      blocked_by = ["1"])
        @test entry != AgentPlanEntry("Run the tests", :medium, :in_progress; id = "2", blocked_by = ["3"])
    end

    @testset "a plan has an id and one of three contents, or is removed" begin
        steps = AgentPlanUpdate([AgentPlanEntry("Read", :high, :pending)]; id = "tasks")
        @test (steps.id, length(steps.entries), steps.markdown, steps.uri) == ("tasks", 1, nothing, nothing)
        markdown = AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode", markdown = "# Plan\n\n1. Read")
        @test (markdown.id, markdown.markdown, isempty(markdown.entries)) == ("plan-mode", "# Plan\n\n1. Read", true)
        file = AgentPlanUpdate(AgentPlanEntry[]; id = "file", uri = "file:///plan.md")
        @test (file.uri, file.markdown) == ("file:///plan.md", nothing)
        removed = AgentPlanUpdate(AgentPlanEntry[]; id = "tasks", is_removed = true)
        @test removed.is_removed && removed.id == "tasks"
    end

    @testset "a subagent update keeps what it does not name, and carries one event" begin
        started = AgentSubagentUpdate("sub-1"; title = "Explore", description = "Explore the code",
                                      state = :running, can_cancel = true)
        @test (started.id, started.title, started.description, started.state, started.can_cancel) ==
              ("sub-1", "Explore", "Explore the code", :running, true)
        @test started.stop_reason === nothing && started.token_count === nothing && started.event === nothing
        idle = AgentSubagentUpdate("sub-1"; state = :idle, stop_reason = :end_turn, token_count = 1200,
                                   tool_call_count = 3, duration = 4.5, last_tool = "Read", summary = "Found it")
        @test (idle.state, idle.stop_reason, idle.token_count, idle.tool_call_count, idle.duration) ==
              (:idle, :end_turn, 1200, 3, 4.5)
        @test (idle.last_tool, idle.summary, idle.title, idle.can_cancel) == ("Read", "Found it", nothing, nothing)
        # The prompt of a subagent, its text, and the update of a subagent of it.
        prompt = AgentSubagentUpdate("sub-1"; event = LlmMessage(:user, LlmContent[LlmText("Find the bug")]))
        @test prompt.event isa LlmMessage && prompt.event.role === :user
        text = AgentSubagentUpdate("sub-1"; event = LlmTextDelta("Looking"))
        @test text.event == LlmTextDelta("Looking")
        nested = AgentSubagentUpdate("sub-1"; event = AgentSubagentUpdate("sub-2"; state = :running))
        @test nested.event isa AgentSubagentUpdate && nested.event.id == "sub-2"
    end

    @testset "a background task update keeps what it does not name" begin
        started = AgentBackgroundTaskUpdate("task-1"; kind = :local_bash, title = "sleep 10", status = :running,
                                            tool_call_id = "t1", start_time = 1.0e9, can_stop = true)
        @test (started.id, started.kind, started.title, started.status) ==
              ("task-1", :local_bash, "sleep 10", :running)
        @test (started.tool_call_id, started.start_time, started.can_stop) == ("t1", 1.0e9, true)
        @test started.subagent_id === nothing && started.output_uri === nothing && started.end_time === nothing
        ended = AgentBackgroundTaskUpdate("task-1"; status = :completed, end_time = 1.0e9 + 10,
                                          output_uri = "file:///tmp/out.txt", summary = "Slept", can_stop = false)
        @test (ended.status, ended.end_time, ended.output_uri, ended.summary, ended.can_stop) ==
              (:completed, 1.0e9 + 10, "file:///tmp/out.txt", "Slept", false)
        @test ended.kind === nothing && ended.title === nothing && ended.start_time === nothing
        @test AgentBackgroundTaskUpdate("task-2"; subagent_id = "sub-1").subagent_id == "sub-1"
    end

    @testset "a notice, a compaction, and the process of a session" begin
        notice = AgentNoticeUpdate(:warning, "API retry 1 of 3", "")
        @test (notice.severity, notice.title, notice.description) == (:warning, "API retry 1 of 3", "")
        compaction = AgentCompactionUpdate("c1", :completed, "The summary")
        @test (compaction.id, compaction.status, compaction.summary) == ("c1", :completed, "The summary")
        @test AgentCompactionUpdate("c1", :in_progress, nothing).summary === nothing
        # The title alone builds as it did; a process id comes beside it.
        @test AgentSessionInfoUpdate("Title") == AgentSessionInfoUpdate("Title", nothing)
        process = AgentSessionInfoUpdate(nothing; process_id = Int32(4242))
        @test (process.title, process.process_id) == (nothing, 4242)
        @test process.process_id isa Int
    end

    @testset "the queue takes the events of another task, in order" begin
        queue = AgentEventQueue()
        @test take_agent_events!(queue) == Any[]
        consumer = Threads.@spawn begin
            seen = Any[]
            deadline = time() + 10
            while length(seen) < 200 && time() < deadline
                append!(seen, take_agent_events!(queue))
                yield()
            end
            seen
        end
        producer = Threads.@spawn for k in 1:200
            put_agent_event!(queue, AgentNoticeUpdate(:info, "notice $(k)", ""))
        end
        @test put_agent_event!(queue, AgentNoticeUpdate(:info, "late", "")) === nothing
        wait(producer)
        seen = fetch(consumer)
        rest = take_agent_events!(queue)
        titles = String[event.title for event in vcat(seen, rest)]
        # The events of one task keep their order, and none is lost or taken twice.
        @test filter(title -> title != "late", titles) == ["notice $(k)" for k in 1:200]
        @test count(==("late"), titles) == 1
        @test isempty(take_agent_events!(queue))
    end

end
end # test_agent_connection_event
