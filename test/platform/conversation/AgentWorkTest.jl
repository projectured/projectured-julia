"""
    test_agent_work()

The work of an external agent, against a scripted connection: a subagent and
its transcript, a subagent of a subagent, the plans, a background task that
ends after the prompt through the queue and the feed of a real editor, the
notices, the process of the session, a turn that the agent starts by itself, a
question of a subagent and a question between two prompts, the order of the
events, the duplicate, and the facets.
"""
function test_agent_work()
    @testset "the work of an external agent" begin
        @testset "a subagent fills its work and its transcript, and goes idle" begin
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("I ask "),
                AgentSubagentUpdate("sub1"; title = "Explore", description = "Look around", state = :running,
                                    can_cancel = true),
                AgentSubagentUpdate("sub1"; event = LlmMessage(:user, [LlmText("Find the files")])),
                AgentSubagentUpdate("sub1"; event = LlmTextStart()),
                AgentSubagentUpdate("sub1"; event = LlmTextDelta("I look.")),
                AgentSubagentUpdate("sub1"; event = AgentToolCallUpdate("c1"; name = "Grep", status = :completed,
                                                                        input = Dict{String,Any}("pattern" => "x"),
                                                                        output = "a.jl")),
                AgentSubagentUpdate("sub1"; state = :idle, stop_reason = :end_turn, token_count = 1200,
                                    tool_call_count = 1, duration = 2.5, last_tool = "Grep", summary = "Found a.jl"),
                LlmTextDelta("a subagent."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Explore")
            @test a.agent_work.id == "scripted-session-1"
            child = only(collect(a.agent_work.subagents))
            @test (child.id, child.title, child.description, child.state, child.stop_reason) ==
                  ("sub1", "Explore", "Look around", :idle, :end_turn)
            @test (child.token_count, child.tool_call_count, child.duration, child.last_tool, child.summary,
                   child.can_cancel) == (1200, 1, 2.5, "Grep", "Found a.jl", true)
            turns = collect(child.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            @test occursin("Find the files", AssistantModule._part_text(only(turns[1].parts)))
            parts = collect(turns[2].parts)
            @test occursin("I look.", AssistantModule._part_text(parts[1]))
            @test parts[2].content isa EvaluatorForm && parts[2].content.tool_name == "Grep" &&
                  parts[2].content.output == "a.jl"
            # Idle ended its turn.
            @test turns[2].stop_reason === :end_turn && turns[2].finish_time > 0
            # The work of the subagent leaves the transcript of the session alone,
            # and its text block stays one.
            main = collect(a.conversation.turns)
            @test [turn.role for turn in main] == [:user, :assistant]
            @test occursin("I ask a subagent.", AssistantModule._part_text(only(main[2].parts)))
            @test isempty(collect(a.agent_work.conversation.turns))
        end

        @testset "a subagent of a subagent" begin
            connection = ScriptedAgentConnection([Any[
                AgentSubagentUpdate("sub1"; title = "Outer", state = :running,
                    event = AgentSubagentUpdate("sub2"; title = "Inner", state = :running,
                                                event = LlmMessage(:user, [LlmText("Dig")]))),
                AgentSubagentUpdate("sub1"; event = AgentSubagentUpdate("sub2"; event = LlmTextDelta("Deep."))),
                AgentSubagentUpdate("sub1"; event = AgentSubagentUpdate("sub2"; state = :idle))]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            outer = only(collect(a.agent_work.subagents))
            inner = only(collect(outer.subagents))
            @test (outer.title, outer.state, inner.title, inner.state) == ("Outer", :running, "Inner", :idle)
            @test isempty(collect(outer.conversation.turns))
            turns = collect(inner.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            @test occursin("Deep.", AssistantModule._part_text(only(turns[2].parts)))
            @test compute_item_facet(a, Val(:subagents)) == 1
        end

        @testset "a plan with a blocked step and a step in progress, an update in place, Markdown and a removal" begin
            first_plan = [AgentPlanEntry("Read the code", :high, :completed; id = "1"),
                          AgentPlanEntry("Write the code", :medium, :in_progress; id = "2",
                                         active_title = "Writing the code", description = "All of it"),
                          AgentPlanEntry("Run the tests", :low, :pending; id = "3", blocked_by = ["2"])]
            second_plan = [AgentPlanEntry("Read the code", :high, :completed; id = "1"),
                           AgentPlanEntry("Write the code", :medium, :completed; id = "2",
                                          active_title = "Writing the code", description = "All of it"),
                           AgentPlanEntry("Run the tests", :low, :in_progress; id = "3", blocked_by = ["2"])]
            connection = ScriptedAgentConnection([
                Any[AgentPlanUpdate(first_plan; id = "tasks"), AgentPlanUpdate([AgentPlanEntry("Only", :medium, :pending)])],
                Any[AgentPlanUpdate(second_plan; id = "tasks"),
                    AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode", markdown = "Do it in two steps.")],
                Any[AgentPlanUpdate(AgentPlanEntry[]; id = "tasks", is_removed = true)]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Plan")
            plans = collect(a.agent_work.plans)
            @test [plan.id for plan in plans] == ["tasks", ""]
            @test [get_document_title(plan) for plan in plans] == ["tasks", "Plan"]
            plan = plans[1]
            steps = collect(plan.steps)
            @test [step.id for step in steps] == ["1", "2", "3"]
            @test [step.status for step in steps] == [:completed, :in_progress, :pending]
            @test (steps[2].active_title, steps[2].description, steps[2].priority) ==
                  ("Writing the code", "All of it", :medium)
            @test is_work_plan_step_blocked(plan, steps[3]) && !is_work_plan_step_blocked(plan, steps[2])
            @test only(collect(plans[2].steps)).id == "1"
            @test compute_item_facet(a, Val(:plan)) == "1/3"
            # The second update writes the statuses of the same steps.
            _submit_to_agent!(a, "Go on")
            @test all(k -> collect(plan.steps)[k] === steps[k], 1:3)
            @test [step.status for step in steps] == [:completed, :completed, :in_progress]
            @test !is_work_plan_step_blocked(plan, steps[3])
            @test compute_item_facet(a, Val(:plan)) == "2/3"
            markdown = collect(a.agent_work.plans)[3]
            @test (markdown.id, markdown.text, isempty(markdown.steps)) == ("plan-mode", "Do it in two steps.", true)
            # The checklist and the Markdown plan are two parts of the turn.
            texts = [AssistantModule._part_text(part) for part in collect(collect(a.conversation.turns)[4].parts)]
            @test length(texts) == 2
            @test occursin("[x] Write the code", texts[1]) && !occursin("two steps", texts[1])
            @test occursin("Do it in two steps.", texts[2])
            # A removal takes the plan out and leaves the checklist of the turn.
            _submit_to_agent!(a, "Drop it")
            @test [plan.id for plan in collect(a.agent_work.plans)] == ["", "plan-mode"]
            @test occursin("[x] Write the code",
                           AssistantModule._part_text(first(collect(collect(a.conversation.turns)[4].parts))))
        end

        @testset "a background task ends after the prompt, through the queue and the feed of a real editor" begin
            connection = ScriptedAgentConnection([
                Any[AgentBackgroundTaskUpdate("bg1"; kind = :local_bash, title = "sleep 5", status = :running,
                                              tool_call_id = "t1", start_time = 100.0, can_stop = true),
                    LlmTextStart(), LlmTextDelta("Started."), LlmTextStop()],
                Any[AgentNoticeUpdate(:info, "Second", "")]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "Run it")
            feed = only(feed for feed in editor.feeds if feed isa AgentEventFeed)
            @test count(feed -> feed isa TaskFeed, editor.feeds) == 1
            document = only(collect(a.agent_work.background_tasks))
            task = document.task
            @test task isa AgentBackgroundTask
            @test (task.session_id, task.task_id, task.kind, task.title, task.can_stop) ==
                  ("scripted-session-1", "bg1", :local_bash, "sleep 5", true)
            @test get_task_document_status(document) === :running
            @test format_task_parameters(task) == "sleep 5" && format_task_column(task, "kind") == "local_bash"
            @test compute_item_facet(a, Val(:background_tasks)) == 1
            @test compute_wake_deadline(feed, editor) == 0.25
            # Stop finds the assistant of the session in the list of the assistants.
            list = get_session_assistant_list()
            previous = list.source
            set_assistant_list_source!(list, () -> [a])
            try
                labels = [first(action) for action in get_task_actions(task)]
                @test labels == ["Stop"]
                last(only(get_task_actions(task)))(editor, task)
                @test timedwait(() -> !isempty(connection.background_task_stops), 10.0; pollint = 0.01) === :ok
                @test connection.background_task_stops == ["scripted-session-1" => "bg1"]
            finally
                set_assistant_list_source!(list, previous)
            end
            # The task ends after the prompt: the agent puts its end into the queue.
            queue = only(connection.sessions).events
            put_agent_event!(queue, AgentBackgroundTaskUpdate("bg1"; status = :completed, end_time = 103.0,
                                                              summary = "slept",
                                                              output_uri = "file:///tmp/output.txt"))
            drain_feeds!(editor)
            drain_task_feed!()
            @test get_task_document_status(document) === :done
            result = get_task_document_result(document)
            @test result isa AgentBackgroundTaskResult
            @test (result.result, result.expected_result, result.elapsed_wall_time) == ("DONE", "DONE", 3.0)
            task = document.task
            @test (task.summary, task.output_uri, task.can_stop) == ("slept", "file:///tmp/output.txt", false)
            @test format_task_details(task, result) ==
                  ["kind: local_bash", "tool call: t1", "output: /tmp/output.txt", "summary: slept"]
            @test [first(action) for action in get_task_actions(task)] == ["Open the output"]
            @test compute_item_facet(a, Val(:background_tasks)) == 0
            # An event in the queue before a prompt applies before the events of
            # the prompt.
            put_agent_event!(queue, AgentNoticeUpdate(:info, "First", ""))
            _work_submit!(editor, a, "Next")
            @test [notice.title for notice in collect(a.agent_work.notices)] == ["First", "Second"]
            # The window sleeps when nothing runs and no prompt ended lately.
            @test compute_wake_deadline(feed, editor) == 0.25
            a.agent_session.prompt_end_time = -Inf
            @test compute_wake_deadline(feed, editor) === nothing
            # The queue leaves the feed when the assistant ends its session.
            stop_external_agent!(a)
            drain_feeds!(editor)
            @test isempty(feed.sources)
        end

        @testset "a notice and a compaction" begin
            connection = ScriptedAgentConnection([Any[
                AgentNoticeUpdate(:warning, "Retrying", "The model is busy"),
                AgentCompactionUpdate("k1", :completed, "What came before"),
                AgentSubagentUpdate("sub1"; state = :running, event = AgentNoticeUpdate(:error, "Failed", ""))]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            notices = collect(a.agent_work.notices)
            @test [(notice.severity, notice.title, notice.description) for notice in notices] ==
                  [(:warning, "Retrying", "The model is busy"), (:info, "The context was compacted", "What came before")]
            @test all(notice -> notice.time > 0, notices)
            child = only(collect(a.agent_work.subagents))
            @test only(collect(child.notices)).title == "Failed"
        end

        @testset "the process of the session makes a tree of the processes" begin
            connection = ScriptedAgentConnection([Any[AgentSessionInfoUpdate("Cleanup"; process_id = getpid())],
                                                  Any[AgentSessionInfoUpdate(nothing; process_id = getpid())],
                                                  Any[AgentSessionInfoUpdate(nothing; process_id = 1)]])
            a = _make_agent_assistant(connection)
            @test a.agent_work.processes === nothing
            _submit_to_agent!(a, "Go")
            tree = a.agent_work.processes
            @test tree isa SystemProcessTree && collect(tree.root_process_ids) == [getpid()]
            @test a.agent_title == "Cleanup"
            _submit_to_agent!(a, "Again")
            @test a.agent_work.processes === tree && a.agent_title == "Cleanup"
            _submit_to_agent!(a, "Once more")
            @test a.agent_work.processes !== tree && collect(a.agent_work.processes.root_process_ids) == [1]
        end

        @testset "a turn that the agent starts by itself between two prompts" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "First")
            queue = only(connection.sessions).events
            for event in Any[LlmTextStart(), LlmTextDelta("The tests passed."),
                             AgentToolCallUpdate("r1"; name = "Read", status = :completed,
                                                 input = Dict{String,Any}("file_path" => "/a.txt"), output = "a"),
                             AgentUsageUpdate(20, 100, nothing, "")]
                put_agent_event!(queue, event)
            end
            drain_feeds!(editor)
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant, :assistant]
            parts = collect(turns[3].parts)
            @test occursin("The tests passed.", AssistantModule._part_text(parts[1]))
            @test parts[2].content isa EvaluatorForm && parts[2].content.tool_name == "Read"
            # The usage at its end ended the turn.
            @test turns[3].stop_reason === :end_turn && turns[3].finish_time > 0
            @test a.agent_session.agent_turn === nothing && a.agent_usage.used == 20
            # A turn that no usage ended ends at the next prompt, above it.
            put_agent_event!(queue, LlmTextStart())
            put_agent_event!(queue, LlmTextDelta("Still going."))
            drain_feeds!(editor)
            _work_submit!(editor, a, "Second")
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant, :assistant, :assistant, :user, :assistant]
            @test occursin("Still going.", AssistantModule._part_text(only(turns[4].parts)))
            @test turns[4].finish_time > 0
            @test occursin("Two.", AssistantModule._part_text(only(turns[6].parts)))
        end

        @testset "a question of a subagent shows in its transcript and in the turn, and the answer reaches it" begin
            options = [AgentPermissionOption("allow", "Allow", :allow_once),
                       AgentPermissionOption("reject", "Reject", :reject_once)]
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("Let me look."),
                _work_subagent_permission_step("sub1", "Explore", AgentToolCallUpdate("p1"; title = "rm x.txt"),
                                               options),
                AgentSubagentUpdate("sub1"; state = :idle)]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Clean up"; wait = false)
            request = _wait_for_permission_request(a)
            @test request.title == "The subagent “Explore” asks to run: rm x.txt"
            child = only(collect(a.agent_work.subagents))
            shown = [part.content for turn in collect(child.conversation.turns) for part in collect(turn.parts)
                     if part.content isa ConversationPermissionRequest]
            @test only(shown) === request
            @test compute_assistant_turn_side(a) === :person
            answer_permission_request!(request, "allow")
            _wait_for_idle(a)
            @test connection.answers == Any["allow"]
            @test request.answer == "Allow"
            # The text of the session closed before the card.
            parts = collect(collect(a.conversation.turns)[2].parts)
            @test occursin("Let me look.", AssistantModule._part_text(parts[1])) && parts[2].content === request
        end

        @testset "a question of the agent between two prompts waits until the end of the next prompt" begin
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                                                  Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "First")
            queue = only(connection.sessions).events
            replies = Any[]
            put_agent_event!(queue, AgentPermissionRequest(AgentToolCallUpdate("p1"; title = "Run the tests"),
                                                           [AgentPermissionOption("allow", "Allow", :allow_once)],
                                                           option -> (push!(replies, option); true)))
            put_agent_event!(queue, AgentUsageUpdate(10, 100, nothing, ""))
            drain_feeds!(editor)
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant, :assistant]
            request = only(part.content for part in collect(turns[3].parts))
            @test request isa ConversationPermissionRequest
            @test request.title == "The agent asks to run: Run the tests"
            # The turn ended, and the question still waits.
            @test turns[3].finish_time > 0 && is_permission_request_open(request)
            _work_submit!(editor, a, "Second")
            @test replies == Any[nothing]
            @test request.answer == "Cancelled"
        end

        @testset "a duplicate and a reset start with an empty work, and a file keeps none" begin
            connection = ScriptedAgentConnection([Any[AgentSubagentUpdate("sub1"; title = "Explore", state = :running),
                                                      AgentNoticeUpdate(:info, "Note", "")]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            @test length(collect(a.agent_work.subagents)) == 1
            fork = copy_document(DuplicatePolicy(), a)
            @test fork.agent_work !== a.agent_work
            @test fork.agent_work.id == "" && isempty(collect(fork.agent_work.subagents)) &&
                  isempty(collect(fork.agent_work.notices))
            @test !any(pair -> first(pair) === :agent_work, last(pred_arguments(a)))
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test isempty(collect(a.agent_work.subagents))
        end

        @testset "the facets of an assistant and of the work of an agent" begin
            a = Assistant(; backend = :acp)
            editor = (document = a,)
            apply_agent_event!(editor, a, AgentPlanUpdate([AgentPlanEntry("A", :high, :completed; id = "1"),
                                                           AgentPlanEntry("B", :medium, :in_progress; id = "2"),
                                                           AgentPlanEntry("C", :low, :pending; id = "3")]; id = "tasks"))
            apply_agent_event!(editor, a, AgentSubagentUpdate("s1"; state = :running, token_count = 300,
                                                              last_tool = "Grep"))
            apply_agent_event!(editor, a, AgentSubagentUpdate("s2"; state = :idle))
            apply_agent_event!(editor, a, AgentBackgroundTaskUpdate("b1"; title = "watch", status = :running))
            @test compute_item_facet(a, Val(:plan)) == "1/3"
            @test compute_item_facet(a, Val(:subagents)) == 1
            @test compute_item_facet(a, Val(:background_tasks)) == 1
            @test [first(pair) for pair in get_item_facets(Assistant)] ==
                  ["title", "turn", "tokens", "plan", "subagents", "background_tasks"]
            @test compute_item_facet(Assistant(), Val(:plan)) == ""
            work = first(collect(a.agent_work.subagents))
            @test compute_item_facet(work, Val(:tokens)) == 300
            @test compute_item_facet(AgentWork("x"), Val(:tokens)) == 0
            @test [first(pair) for pair in get_item_facets(AgentWork)] == ["tokens"]
            # The task ends, so the feed of the tasks of the session lets it go.
            apply_agent_event!(editor, a, AgentBackgroundTaskUpdate("b1"; status = :stopped))
            drain_task_feed!()
            @test get_task_document_result(only(collect(a.agent_work.background_tasks))).result == "CANCEL"
            @test compute_item_facet(a, Val(:background_tasks)) == 0
        end
    end
end

# An editor with no loop, on the assistant, whose feeds a test drains.
_work_editor(a::Assistant) = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[])

# Submit `text` as a prose turn in `editor`, and wait for the turn to end.
function _work_submit!(editor, a::Assistant, text::AbstractString)
    a.input.value = text
    evaluate_operation(editor, SubmitProseOperation(a))
    _wait_for_idle(a)
    nothing
end

# A step of a script in which the subagent `id` asks the person whether it can
# run `tool_call`, and waits at most ten seconds for the answer, which goes to the
# `answers` of the connection.
function _work_subagent_permission_step(id::AbstractString, title::AbstractString,
                                        tool_call::AgentToolCallUpdate, options)
    function (connection, on_event)
        choice = Channel{Any}(1)
        reply = option_id -> (isready(choice) ? false : (put!(choice, option_id); true))
        on_event(AgentSubagentUpdate(id; title = title, state = :running,
                                     event = AgentPermissionRequest(tool_call, collect(options), reply)))
        answer = timedwait(() -> isready(choice), 10.0; pollint = 0.01) === :ok ? take!(choice) : nothing
        push!(connection.answers, answer)
        nothing
    end
end
