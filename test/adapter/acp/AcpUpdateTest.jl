# The translation of a `session/update` into the events of the kernel: the frame
# that a chunk of text or of reasoning gets, the close of a block by a new
# message or a tool call, a tool call and its update, a diff, the plans, a
# notice and a compaction; and the reading of a subagent update, of the process
# of a session and of the notification of a background task.

using ProjecturedACP.AcpModule: AcpTurn, _translate_session_update!, _close_open_block!,
                                _format_tool_content, _read_subagent_update, _read_background_task,
                                _read_session_info_update

_update(kind; fields...) = Dict{String,Any}("sessionUpdate" => kind,
                                            (String(key) => value for (key, value) in fields)...)
_text(text) = Dict{String,Any}("type" => "text", "text" => text)

function test_acp_update()
    @testset "a session update becomes kernel events" begin
        @testset "chunks of one message share one block" begin
            turn = AcpTurn(identity)
            first = _translate_session_update!(turn, _update("agent_message_chunk";
                                                             content = _text("Hel"), messageId = "m1"))
            second = _translate_session_update!(turn, _update("agent_message_chunk";
                                                              content = _text("lo"), messageId = "m1"))
            @test first == Any[LlmTextStart(), LlmTextDelta("Hel")]
            @test second == Any[LlmTextDelta("lo")]
            @test _close_open_block!(Any[], turn) == Any[LlmTextStop()]
            @test turn.open_block === :none
        end

        @testset "reasoning, then text, then a new message" begin
            turn = AcpTurn(identity)
            events = Any[]
            append!(events, _translate_session_update!(turn, _update("agent_thought_chunk"; content = _text("hmm"))))
            append!(events, _translate_session_update!(turn, _update("agent_message_chunk";
                                                                     content = _text("A"), messageId = "m1")))
            append!(events, _translate_session_update!(turn, _update("agent_message_chunk";
                                                                     content = _text("B"), messageId = "m2")))
            @test events == Any[LlmThinkingStart(), LlmThinkingDelta("hmm"), LlmThinkingStop(),
                                LlmTextStart(), LlmTextDelta("A"), LlmTextStop(),
                                LlmTextStart(), LlmTextDelta("B")]
        end

        @testset "a tool call closes the open block, and its update keeps the rest" begin
            turn = AcpTurn(identity)
            _translate_session_update!(turn, _update("agent_message_chunk"; content = _text("Let me look.")))
            call = _translate_session_update!(turn, _update("tool_call"; toolCallId = "t1",
                title = "Read file", kind = "read", status = "pending",
                rawInput = Dict{String,Any}("path" => "a.jl"),
                _meta = Dict{String,Any}("claudeCode" => Dict{String,Any}("toolName" => "Read"))))
            @test call[1] == LlmTextStop()
            event = call[2]
            @test event isa AgentToolCallUpdate
            @test (event.id, event.name, event.title, event.kind, event.status) ==
                  ("t1", "Read", "Read file", :read, :pending)
            @test event.input == Dict{String,Any}("path" => "a.jl")
            @test event.output === nothing
            update = only(_translate_session_update!(turn, _update("tool_call_update"; toolCallId = "t1",
                status = "completed",
                content = Any[Dict{String,Any}("type" => "content", "content" => _text("1 line"))])))
            @test (update.id, update.status, update.output) == ("t1", :completed, "1 line")
            @test update.title === nothing && update.kind === nothing && update.input === nothing
        end

        @testset "a resource gives its text, its media type and its uri" begin
            resource = Dict{String,Any}("type" => "resource", "resource" => Dict{String,Any}(
                "uri" => "file:///c.md", "mimeType" => "text/markdown", "text" => "# Title\n"))
            update = only(_translate_session_update!(AcpTurn(identity), _update("tool_call_update"; toolCallId = "t1",
                status = "completed", content = Any[Dict{String,Any}("type" => "content", "content" => resource)])))
            @test (update.output, update.output_mime_type, update.output_uri) == ("# Title\n", "text/markdown", "file:///c.md")
            # Text alone has no media type.
            plain = only(_translate_session_update!(AcpTurn(identity), _update("tool_call_update"; toolCallId = "t2",
                status = "completed", content = Any[Dict{String,Any}("type" => "content", "content" => _text("x"))])))
            @test plain.output_mime_type === nothing && plain.output_uri === nothing
        end

        @testset "a diff shows its path and its lines" begin
            text = _format_tool_content(Any[Dict{String,Any}(
                "type" => "diff", "path" => "/a.jl", "oldText" => "x = 1", "newText" => "x = 2\ny = 3")])
            @test text == "/a.jl\n-x = 1\n+x = 2\n+y = 3"
        end

        @testset "a plan replaces the plan" begin
            plan = only(_translate_session_update!(AcpTurn(identity), _update("plan"; entries = Any[
                Dict{String,Any}("content" => "Read", "priority" => "high", "status" => "completed"),
                Dict{String,Any}("content" => "Write", "priority" => "low", "status" => "pending")])))
            @test plan isa AgentPlanUpdate
            @test plan.entries == [AgentPlanEntry("Read", :high, :completed),
                                   AgentPlanEntry("Write", :low, :pending)]
        end

        @testset "a plan of version 1 has the empty id" begin
            plan = only(_translate_session_update!(AcpTurn(identity), _update("plan"; entries = Any[])))
            @test (plan.id, plan.entries, plan.markdown, plan.uri, plan.is_removed) ==
                  ("", AgentPlanEntry[], nothing, nothing, false)
        end

        @testset "an entry reads the four keys of _meta.claudeCode, and no other" begin
            entry = Dict{String,Any}("content" => "Write", "priority" => "medium", "status" => "pending",
                "_meta" => Dict{String,Any}("claudeCode" => Dict{String,Any}(
                    "taskId" => "2", "description" => "Write the file", "activeForm" => "Writing the file",
                    "blockedBy" => Any["1", 3], "owner" => "agent")))
            plan = only(_translate_session_update!(AcpTurn(identity), _update("plan_update";
                plan = Dict{String,Any}("type" => "items", "planId" => "tasks", "entries" => Any[entry]))))
            @test plan.id == "tasks"
            @test only(plan.entries) == AgentPlanEntry("Write", :medium, :pending; id = "2",
                description = "Write the file", active_title = "Writing the file", blocked_by = ["1", "3"])
            # An entry with no `_meta` has an empty id and no blockers.
            bare = only(_translate_session_update!(AcpTurn(identity), _update("plan_update";
                plan = Dict{String,Any}("type" => "items", "planId" => "other", "entries" => Any[
                    Dict{String,Any}("content" => "Read", "priority" => "high", "status" => "completed")]))))
            @test only(bare.entries) == AgentPlanEntry("Read", :high, :completed)
        end

        @testset "a plan of Markdown, a plan in a file, a removal, and a content of no known type" begin
            turn = AcpTurn(identity)
            _translate_session_update!(turn, _update("agent_message_chunk"; content = _text("Here.")))
            events = _translate_session_update!(turn, _update("plan_update";
                plan = Dict{String,Any}("type" => "markdown", "planId" => "plan-mode", "content" => "# Plan")))
            # A plan closes the open block, as a plan of version 1 does.
            @test events[1] == LlmTextStop()
            @test (events[2].id, events[2].markdown, events[2].uri, isempty(events[2].entries)) ==
                  ("plan-mode", "# Plan", nothing, true)
            file = only(_translate_session_update!(turn, _update("plan_update";
                plan = Dict{String,Any}("type" => "file", "planId" => "file", "uri" => "file:///plan.md"))))
            @test (file.id, file.uri, file.markdown) == ("file", "file:///plan.md", nothing)
            removed = only(_translate_session_update!(turn, _update("plan_removed"; planId = "plan-mode")))
            @test (removed.id, removed.is_removed) == ("plan-mode", true)
            @test isempty(_translate_session_update!(turn, _update("plan_update";
                plan = Dict{String,Any}("type" => "diagram", "planId" => "x"))))
        end

        @testset "a notice and a compaction" begin
            turn = AcpTurn(identity)
            notice = only(_translate_session_update!(turn, _update("notice"; severity = "warning",
                                                                   title = "API retry 1 of 3", description = "529")))
            @test (notice.severity, notice.title, notice.description) == (:warning, "API retry 1 of 3", "529")
            odd = only(_translate_session_update!(turn, _update("notice"; severity = "loud", title = "Hi")))
            @test (odd.severity, odd.description) == (:info, "")
            started = only(_translate_session_update!(turn, _update("compaction_update"; compactionId = "c1",
                                                                    status = "in_progress")))
            @test (started.id, started.status, started.summary) == ("c1", :in_progress, nothing)
            completed = only(_translate_session_update!(turn, _update("compaction_update"; compactionId = "c1",
                status = "completed", summary = Any[_text("First."), _text("Second.")])))
            @test (completed.status, completed.summary) == (:completed, "First.\nSecond.")
            cleared = only(_translate_session_update!(turn, _update("compaction_update"; compactionId = "c1",
                                                                    status = "completed", summary = nothing)))
            @test cleared.summary == ""
        end

        @testset "a subagent update reads its state, its counts and whether it can be cancelled" begin
            started = _read_subagent_update(_update("subagent_update"; sessionId = "child-1", title = "Explore",
                description = "general-purpose", state = Dict{String,Any}("state" => "running"),
                capabilities = Dict{String,Any}("cancel" => Dict{String,Any}())))
            @test (started.id, started.title, started.description, started.state, started.can_cancel) ==
                  ("child-1", "Explore", "general-purpose", :running, true)
            @test started.stop_reason === nothing && started.token_count === nothing && started.event === nothing
            idle = _read_subagent_update(_update("subagent_update"; sessionId = "child-1",
                state = Dict{String,Any}("state" => "idle", "stopReason" => "end_turn"),
                _meta = Dict{String,Any}("claudeCode" => Dict{String,Any}(
                    "usage" => Dict{String,Any}("totalTokens" => 1200, "toolUses" => 3, "durationMs" => 4500),
                    "lastToolName" => "Read", "summary" => "Found it"))))
            @test (idle.state, idle.stop_reason, idle.token_count, idle.tool_call_count, idle.duration) ==
                  (:idle, :end_turn, 1200, 3, 4.5)
            @test (idle.last_tool, idle.summary, idle.title, idle.can_cancel) == ("Read", "Found it", nothing, nothing)
            # The usage of an idle state gives the token count of an agent with no `_meta`.
            plain = _read_subagent_update(_update("subagent_update"; sessionId = "child-2",
                state = Dict{String,Any}("state" => "idle", "usage" => Dict{String,Any}(
                    "totalTokens" => 50, "inputTokens" => 40, "outputTokens" => 10)),
                capabilities = nothing))
            @test (plain.token_count, plain.tool_call_count, plain.can_cancel) == (50, nothing, false)
            @test _read_subagent_update(_update("subagent_update"; sessionId = "c",
                state = Dict{String,Any}("state" => "dreaming"))).state === :unknown
            @test _read_subagent_update(_update("subagent_update"; sessionId = "c",
                state = Dict{String,Any}("state" => "requires_action"))).state === :requires_action
        end

        @testset "a session info update reads the process id of _meta" begin
            update = _read_session_info_update(_update("session_info_update";
                _meta = Dict{String,Any}("processId" => 4242)))
            @test (update.title, update.process_id) == (nothing, 4242)
            titled = _read_session_info_update(_update("session_info_update"; title = "Fix it"))
            @test (titled.title, titled.process_id) == ("Fix it", nothing)
        end

        @testset "a background task reads its keys, with the times in seconds" begin
            first = _read_background_task(Dict{String,Any}("sessionId" => "s", "taskId" => "task-1",
                "kind" => "local_bash", "title" => "sleep 10", "status" => "running",
                "startTime" => 1_700_000_000_000, "canStop" => true, "toolCallId" => "t1",
                "subagentId" => "child-1"))
            @test (first.id, first.kind, first.title, first.status, first.can_stop) ==
                  ("task-1", :local_bash, "sleep 10", :running, true)
            @test (first.start_time, first.tool_call_id, first.subagent_id) == (1.7e9, "t1", "child-1")
            @test first.end_time === nothing && first.output_uri === nothing && first.summary === nothing
            # A later notification carries only the keys that changed.
            patch = _read_background_task(Dict{String,Any}("sessionId" => "s", "taskId" => "task-1",
                "status" => "completed", "endTime" => 1_700_000_010_500, "canStop" => false,
                "outputUri" => "file:///tmp/out.txt", "summary" => "Slept"))
            @test (patch.status, patch.end_time, patch.can_stop, patch.output_uri, patch.summary) ==
                  (:completed, 1.7000000105e9, false, "file:///tmp/out.txt", "Slept")
            @test patch.kind === nothing && patch.title === nothing && patch.start_time === nothing
        end

        @testset "an update the client does not show answers no event" begin
            turn = AcpTurn(identity)
            for kind in ("usage_update", "available_commands_update", "session_info_update",
                         "current_mode_update", "config_option_update", "user_message_chunk",
                         "subagent_update", "an_update_from_the_future")
                @test isempty(_translate_session_update!(turn, _update(kind)))
            end
        end
    end
end
