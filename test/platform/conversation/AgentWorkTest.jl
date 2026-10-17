"""
    test_agent_work()

The work of an external agent, against a scripted connection: a subagent and
its transcript, a subagent of a subagent, the plans, a background task that
ends after the prompt through the queue and the feed of a real editor, the
notices, the process of the session, a turn that the agent starts by itself, a
question of a subagent and a question between two prompts, the order of the
events, a live loop that applies them, the end of the work with its connection,
the duplicate, and the facets.
"""
function test_agent_work()
    @testset "the work of an external agent" begin
        @testset "a subagent fills its work and its transcript, and goes idle" begin
            prompt = LlmMessage(:user, [LlmText("Find the files")])
            grep = AgentToolCallUpdate("c1"; name = "Grep", status = :completed,
                                       input = Dict{String,Any}("pattern" => "x"),
                                       output = "a.jl")
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("I ask "),
                AgentSubagentUpdate("sub1"; title = "Explore",
                                    description = "Look around", state = :running,
                                    can_cancel = true),
                AgentSubagentUpdate("sub1"; event = prompt),
                AgentSubagentUpdate("sub1"; event = LlmTextStart()),
                AgentSubagentUpdate("sub1"; event = LlmTextDelta("I look.")),
                AgentSubagentUpdate("sub1"; event = grep),
                AgentSubagentUpdate("sub1"; state = :idle, stop_reason = :end_turn,
                                    token_count = 1200, tool_call_count = 1,
                                    duration = 2.5, last_tool = "Grep",
                                    summary = "Found a.jl"),
                LlmTextDelta("a subagent."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Explore")
            @test a.agent_work.id == "scripted-session-1"
            child = only(collect(a.agent_work.subagents))
            @test (child.id, child.title, child.description) ==
                  ("sub1", "Explore", "Look around")
            @test (child.state, child.stop_reason) == (:idle, :end_turn)
            @test (child.token_count, child.tool_call_count, child.duration) ==
                  (1200, 1, 2.5)
            # It started to run, so it keeps the time; it ended, so its node says how
            # long it worked.
            @test child.start_time isa Float64
            @test format_tree_node_label(child) == "Explore" && get_document_decoration(child).detail == "idle · 2 s · 1k tokens"
            @test (child.last_tool, child.summary, child.can_cancel) ==
                  ("Grep", "Found a.jl", true)
            turns = collect(child.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            @test occursin("Find the files", _work_text(only(turns[1].parts)))
            parts = collect(turns[2].parts)
            @test occursin("I look.", _work_text(parts[1]))
            form = parts[2].content
            @test form isa EvaluatorForm
            @test (form.tool_name, form.output) == ("Grep", "a.jl")
            # Idle ended its turn.
            @test turns[2].stop_reason === :end_turn && turns[2].finish_time > 0
            # The work of the subagent leaves the transcript of the session alone,
            # and its text block stays one.
            main = collect(a.conversation.turns)
            @test [turn.role for turn in main] == [:user, :assistant]
            @test occursin("I ask a subagent.", _work_text(only(main[2].parts)))
            @test isempty(collect(a.agent_work.conversation.turns))
        end

        @testset "a subagent of a subagent" begin
            prompt = LlmMessage(:user, [LlmText("Dig")])
            connection = ScriptedAgentConnection([Any[
                AgentSubagentUpdate("sub1"; title = "Outer", state = :running,
                    event = AgentSubagentUpdate("sub2"; title = "Inner", state = :running,
                                                event = prompt)),
                AgentSubagentUpdate("sub1";
                    event = AgentSubagentUpdate("sub2"; event = LlmTextDelta("Deep."))),
                AgentSubagentUpdate("sub1";
                    event = AgentSubagentUpdate("sub2"; state = :idle))]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            outer = only(collect(a.agent_work.subagents))
            inner = only(collect(outer.subagents))
            @test (outer.title, outer.state, inner.title, inner.state) ==
                  ("Outer", :running, "Inner", :idle)
            @test isempty(collect(outer.conversation.turns))
            turns = collect(inner.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant]
            @test occursin("Deep.", _work_text(only(turns[2].parts)))
            @test compute_item_facet(a, Val(:subagents)) == 1
        end

        @testset "a plan: a blocked step, an update, Markdown and a removal" begin
            make_plan(writing, testing) =
                [AgentPlanEntry("Read the code", :high, :completed; id = "1"),
                 AgentPlanEntry("Write the code", :medium, writing; id = "2",
                                active_title = "Writing the code",
                                description = "All of it"),
                 AgentPlanEntry("Run the tests", :low, testing; id = "3",
                                blocked_by = ["2"])]
            first_plan = make_plan(:in_progress, :pending)
            second_plan = make_plan(:completed, :in_progress)
            only_plan = AgentPlanUpdate([AgentPlanEntry("Only", :medium, :pending)])
            markdown_plan = AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode",
                                            markdown = "Do it in two steps.")
            connection = ScriptedAgentConnection([
                Any[AgentPlanUpdate(first_plan; id = "tasks"), only_plan],
                Any[AgentPlanUpdate(second_plan; id = "tasks"), markdown_plan],
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
            @test is_work_plan_step_blocked(plan, steps[3])
            @test !is_work_plan_step_blocked(plan, steps[2])
            @test only(collect(plans[2].steps)).id == "1"
            @test compute_item_facet(a, Val(:plan)) == "1/3"
            # The second update writes the statuses of the same steps.
            _submit_to_agent!(a, "Go on")
            @test all(k -> collect(plan.steps)[k] === steps[k], 1:3)
            @test [step.status for step in steps] ==
                  [:completed, :completed, :in_progress]
            @test !is_work_plan_step_blocked(plan, steps[3])
            @test compute_item_facet(a, Val(:plan)) == "2/3"
            markdown = collect(a.agent_work.plans)[3]
            @test (markdown.id, markdown.text, isempty(markdown.steps)) ==
                  ("plan-mode", "Do it in two steps.", true)
            # The checklist and the Markdown plan are two parts of the turn.
            turn = collect(a.conversation.turns)[4]
            texts = [_work_text(part) for part in collect(turn.parts)]
            @test length(texts) == 2
            @test occursin("[x] Write the code", texts[1])
            @test !occursin("two steps", texts[1])
            @test occursin("Do it in two steps.", texts[2])
            # A removal takes the plan out and leaves the checklist of the turn.
            _submit_to_agent!(a, "Drop it")
            @test [plan.id for plan in collect(a.agent_work.plans)] == ["", "plan-mode"]
            checklist = first(collect(collect(a.conversation.turns)[4].parts))
            @test occursin("[x] Write the code", _work_text(checklist))
        end

        @testset "a background task ends after the prompt, through the queue" begin
            started = AgentBackgroundTaskUpdate("bg1"; kind = :local_bash,
                                                title = "sleep 5", status = :running,
                                                tool_call_id = "t1", start_time = 100.0,
                                                can_stop = true)
            connection = ScriptedAgentConnection([
                Any[started,
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
            @test format_task_parameters(task) == "sleep 5"
            @test format_task_column(task, "kind") == "local_bash"
            @test compute_item_facet(a, Val(:background_tasks)) == 1
            @test compute_wake_deadline(feed, editor) == 0.25
            # Stop finds the assistant of the session in the list of the assistants.
            list = get_session_assistant_list(; editor)
            previous = list.source
            set_assistant_list_source!(list, () -> [a])
            try
                @test [first(action) for action in get_task_actions(task)] == ["Stop"]
                last(only(get_task_actions(task)))(editor, task)
                is_stopped() = !isempty(connection.background_task_stops)
                @test timedwait(is_stopped, 10.0; pollint = 0.01) === :ok
                @test connection.background_task_stops == ["scripted-session-1" => "bg1"]
            finally
                set_assistant_list_source!(list, previous)
            end
            # The task ends after the prompt: the agent puts its end into the queue.
            queue = only(connection.sessions).events
            ended = AgentBackgroundTaskUpdate("bg1"; status = :completed,
                                              end_time = 103.0, summary = "slept",
                                              output_uri = "file:///tmp/output.txt")
            put_agent_event!(queue, ended)
            drain_feeds!(editor)
            drain_task_feed!()
            @test get_task_document_status(document) === :done
            result = get_task_document_result(document)
            @test result isa AgentBackgroundTaskResult
            @test (result.result, result.expected_result, result.elapsed_wall_time) ==
                  ("DONE", "DONE", 3.0)
            task = document.task
            @test (task.summary, task.output_uri, task.can_stop) ==
                  ("slept", "file:///tmp/output.txt", false)
            @test format_task_details(task, result) ==
                  ["kind: local_bash", "tool call: t1", "output: /tmp/output.txt",
                   "summary: slept"]
            @test [first(action) for action in get_task_actions(task)] ==
                  ["Open the output"]
            @test compute_item_facet(a, Val(:background_tasks)) == 0
            # An event in the queue before a prompt applies before the events of
            # the prompt.
            put_agent_event!(queue, AgentNoticeUpdate(:info, "First", ""))
            _work_submit!(editor, a, "Next")
            @test [notice.title for notice in collect(a.agent_work.notices)] ==
                  ["First", "Second"]
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
                AgentSubagentUpdate("sub1"; state = :running,
                                    event = AgentNoticeUpdate(:error, "Failed", ""))]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            notices = collect(a.agent_work.notices)
            @test [(notice.severity, notice.title, notice.description)
                   for notice in notices] ==
                  [(:warning, "Retrying", "The model is busy"),
                   (:info, "The context was compacted", "What came before")]
            @test all(notice -> notice.time > 0, notices)
            child = only(collect(a.agent_work.subagents))
            @test only(collect(child.notices)).title == "Failed"
        end

        @testset "the process of the session makes a tree of the processes" begin
            connection = ScriptedAgentConnection([
                Any[AgentSessionInfoUpdate("Cleanup"; process_id = getpid())],
                Any[AgentSessionInfoUpdate(nothing; process_id = getpid())],
                Any[AgentSessionInfoUpdate(nothing; process_id = 1)]])
            a = _make_agent_assistant(connection)
            @test a.agent_work.processes === nothing
            _submit_to_agent!(a, "Go")
            tree = a.agent_work.processes
            @test tree isa SystemProcessTree
            @test collect(tree.root_process_ids) == [getpid()]
            @test a.agent_title == "Cleanup"
            _submit_to_agent!(a, "Again")
            @test a.agent_work.processes === tree && a.agent_title == "Cleanup"
            _submit_to_agent!(a, "Once more")
            @test a.agent_work.processes !== tree
            @test collect(a.agent_work.processes.root_process_ids) == [1]
        end

        @testset "a turn that the agent starts by itself between two prompts" begin
            connection = ScriptedAgentConnection([
                Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "First")
            queue = only(connection.sessions).events
            reading = AgentToolCallUpdate("r1"; name = "Read", status = :completed,
                                       input = Dict{String,Any}("file_path" => "/a.txt"),
                                       output = "a")
            for event in Any[LlmTextStart(), LlmTextDelta("The tests passed."), reading,
                             AgentUsageUpdate(20, 100, nothing, "")]
                put_agent_event!(queue, event)
            end
            drain_feeds!(editor)
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] == [:user, :assistant, :assistant]
            parts = collect(turns[3].parts)
            @test occursin("The tests passed.", _work_text(parts[1]))
            @test parts[2].content isa EvaluatorForm
            @test parts[2].content.tool_name == "Read"
            # The usage at its end ended the turn.
            @test turns[3].stop_reason === :end_turn && turns[3].finish_time > 0
            @test a.agent_session.agent_turn === nothing && a.agent_usage.used == 20
            # A turn that no usage ended ends at the next prompt, above it.
            put_agent_event!(queue, LlmTextStart())
            put_agent_event!(queue, LlmTextDelta("Still going."))
            drain_feeds!(editor)
            _work_submit!(editor, a, "Second")
            turns = collect(a.conversation.turns)
            @test [turn.role for turn in turns] ==
                  [:user, :assistant, :assistant, :assistant, :user, :assistant]
            @test occursin("Still going.", _work_text(only(turns[4].parts)))
            @test turns[4].finish_time > 0
            @test occursin("Two.", _work_text(only(turns[6].parts)))
        end

        @testset "a live loop applies the events of a prompt in its own frames" begin
            # The step reads the work just after the agent sent a notice: the turn
            # only queued it, and the feed of the loop applies it in a frame.
            seen = Int[]
            notice = AgentNoticeUpdate(:info, "Queued", "")
            observe = (connection, on_event) -> begin
                on_event(notice)
                push!(seen, length(collect(a.agent_work.notices)))
            end
            connection = ScriptedAgentConnection([Any[
                observe, LlmTextStart(), LlmTextDelta("Live."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            loop = @async run_editor!(editor)
            is_running() = editor.loop_task !== nothing
            @test timedwait(is_running, 5.0; pollint = 0.01) === :ok
            a.input.value = "Go"
            post_operation!(editor, SubmitProseOperation(a))
            is_answered() =
                a.status === :idle && length(collect(a.conversation.turns)) == 2
            @test timedwait(is_answered, 10.0; pollint = 0.01) === :ok
            @test seen == [0]
            @test [notice.title for notice in collect(a.agent_work.notices)] == ["Queued"]
            answer = collect(a.conversation.turns)[2]
            @test occursin("Live.", _work_text(only(collect(answer.parts))))
            @test any(feed -> feed isa AgentEventFeed, editor.feeds)
            post_operation!(editor, QuitEditorOperation())
            @test timedwait(() -> istaskdone(loop), 5.0; pollint = 0.01) === :ok
            @test !istaskfailed(loop)
        end

        @testset "a question of a subagent shows in two places, and its answer" begin
            options = [AgentPermissionOption("allow", "Allow", :allow_once),
                       AgentPermissionOption("reject", "Reject", :reject_once)]
            remove = AgentToolCallUpdate("p1"; title = "rm x.txt")
            connection = ScriptedAgentConnection([Any[
                LlmTextStart(), LlmTextDelta("Let me look."),
                _work_subagent_permission_step("sub1", "Explore", remove, options),
                AgentSubagentUpdate("sub1"; state = :idle)]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Clean up"; wait = false)
            request = _wait_for_permission_request(a)
            @test request.title == "The subagent “Explore” asks to run: rm x.txt"
            child = only(collect(a.agent_work.subagents))
            shown = [part.content for turn in collect(child.conversation.turns)
                     for part in collect(turn.parts)
                     if part.content isa ConversationPermissionRequest]
            @test only(shown) === request
            @test compute_assistant_turn_side(a) === :person
            answer_permission_request!(request, "allow")
            _wait_for_idle(a)
            @test connection.answers == Any["allow"]
            @test request.answer == "Allow"
            # The text of the session closed before the card.
            parts = collect(collect(a.conversation.turns)[2].parts)
            @test occursin("Let me look.", _work_text(parts[1]))
            @test parts[2].content === request
        end

        @testset "a question between two prompts waits for the next prompt" begin
            connection = ScriptedAgentConnection([
                Any[LlmTextStart(), LlmTextDelta("One."), LlmTextStop()],
                Any[LlmTextStart(), LlmTextDelta("Two."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "First")
            queue = only(connection.sessions).events
            replies = Any[]
            put_agent_event!(queue, AgentPermissionRequest(
                AgentToolCallUpdate("p1"; title = "Run the tests"),
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

        @testset "the end of the connection ends the work that runs" begin
            connection = ScriptedAgentConnection([Any[
                AgentBackgroundTaskUpdate("bg1"; title = "watch", status = :running,
                                          can_stop = true),
                AgentSubagentUpdate("sub1"; title = "Explore", state = :running,
                                    event = LlmTextDelta("Looking"))]])
            a = _make_agent_assistant(connection)
            editor = _work_editor(a)
            _work_submit!(editor, a, "Go")
            feed = only(feed for feed in editor.feeds if feed isa AgentEventFeed)
            replies = Any[]
            question = AgentPermissionRequest(
                AgentToolCallUpdate("p1"; title = "Run"),
                [AgentPermissionOption("allow", "Allow", :allow_once)],
                option -> (push!(replies, option); true))
            put_agent_event!(only(connection.sessions).events, question)
            drain_feeds!(editor)
            last_turn = last(collect(a.conversation.turns))
            request = only(part.content for part in collect(last_turn.parts))
            @test is_permission_request_open(request)
            @test compute_wake_deadline(feed, editor) == 0.25
            stop_external_agent!(a)
            drain_task_feed!()
            document = only(collect(a.agent_work.background_tasks))
            result = get_task_document_result(document)
            @test (result.result, result.reason) == ("CANCEL", "The agent ended.")
            @test is_expected(result)
            @test !document.task.can_stop && isempty(get_task_actions(document.task))
            child = only(collect(a.agent_work.subagents))
            @test (child.state, child.stop_reason) == (:idle, :cancelled)
            @test only(collect(child.conversation.turns)).stop_reason === :cancelled
            @test replies == Any[nothing] && request.answer == "Cancelled"
            # The feed wakes nothing for the session that ended, and lets it go.
            @test compute_wake_deadline(feed, editor) === nothing
            drain_feeds!(editor)
            @test isempty(feed.sources)
            # A connection that fails ends the work of its prompt too.
            failing = ScriptedAgentConnection([Any[
                AgentBackgroundTaskUpdate("bg2"; title = "build", status = :running),
                AgentSubagentUpdate("sub2"; state = :running),
                (connection, on_event) -> error("The agent died.")]])
            b = _make_agent_assistant(failing)
            _submit_to_agent!(b, "Build")
            @test b.status === :error
            drain_task_feed!()
            build = only(collect(b.agent_work.background_tasks))
            @test get_task_document_result(build).reason == "The agent ended."
            @test only(collect(b.agent_work.subagents)).stop_reason === :cancelled
        end

        @testset "a duplicate and a reset start an empty work; a file keeps none" begin
            connection = ScriptedAgentConnection([Any[
                AgentSubagentUpdate("sub1"; title = "Explore", state = :running),
                AgentNoticeUpdate(:info, "Note", "")]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Go")
            @test length(collect(a.agent_work.subagents)) == 1
            fork = copy_document(DuplicatePolicy(), a)
            @test fork.agent_work !== a.agent_work
            @test fork.agent_work.id == ""
            @test isempty(collect(fork.agent_work.subagents))
            @test isempty(collect(fork.agent_work.notices))
            @test !any(pair -> first(pair) === :agent_work, last(pred_arguments(a)))
            evaluate_operation((document = a,), ResetConversationOperation(a))
            @test isempty(collect(a.agent_work.subagents))
        end

        @testset "the facets of an assistant and of the work of an agent" begin
            a = Assistant(; backend = :acp)
            editor = (document = a,)
            entries = [AgentPlanEntry("A", :high, :completed; id = "1"),
                       AgentPlanEntry("B", :medium, :in_progress; id = "2"),
                       AgentPlanEntry("C", :low, :pending; id = "3")]
            apply_agent_event!(editor, a, AgentPlanUpdate(entries; id = "tasks"))
            apply_agent_event!(editor, a, AgentSubagentUpdate("s1"; state = :running,
                                                              token_count = 300,
                                                              last_tool = "Grep"))
            apply_agent_event!(editor, a, AgentSubagentUpdate("s2"; state = :idle))
            apply_agent_event!(editor, a, AgentBackgroundTaskUpdate("b1"; title = "watch",
                                                                    status = :running))
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
            # The task ends, so the feed of the tasks of the session lets it go. A
            # stop ends a task on purpose, so CANCEL is the code that it expects.
            stopped = AgentBackgroundTaskUpdate("b1"; status = :stopped)
            apply_agent_event!(editor, a, stopped)
            drain_task_feed!()
            watch = only(collect(a.agent_work.background_tasks))
            result = get_task_document_result(watch)
            @test (result.result, result.expected_result) == ("CANCEL", "CANCEL")
            @test is_expected(result)
            @test !occursin("unexpected", format_task_result(result))
            @test compute_item_facet(a, Val(:background_tasks)) == 0
            # A task that failed is an unexpected ERROR.
            for status in (:running, :failed)
                update = AgentBackgroundTaskUpdate("b2"; title = "build", status)
                apply_agent_event!(editor, a, update)
            end
            drain_task_feed!()
            build = last(collect(a.agent_work.background_tasks))
            result = get_task_document_result(build)
            @test (result.result, is_expected(result)) == ("ERROR", false)
            @test occursin("(unexpected)", format_task_result(result))
        end
    end
end

# An editor with no loop, on the assistant, whose feeds a test drains.
_work_editor(a::Assistant) =
    Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[])

# The text of a part of a transcript.
_work_text(part) = AssistantModule._part_text(part)

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
        request = AgentPermissionRequest(tool_call, collect(options), reply)
        on_event(AgentSubagentUpdate(id; title = title, state = :running,
                                     event = request))
        is_answered() = isready(choice)
        is_ready = timedwait(is_answered, 10.0; pollint = 0.01) === :ok
        answer = is_ready ? take!(choice) : nothing
        push!(connection.answers, answer)
        nothing
    end
end
