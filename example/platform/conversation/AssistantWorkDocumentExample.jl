# The work page example: an assistant whose external agent works on a task, and
# the page that shows that work. The work has a plan of steps, a plan of the plan
# mode, a subagent with a short transcript, a background task that ended, the
# processes of the agent and a notice. It needs no agent and reads no clock: the
# events of the agent apply as the feed of a window applies them, and each time
# that the page shows is fixed.

# The time at which the background task of the example started, in seconds since
# the epoch.
const _EXAMPLE_WORK_START = 1_760_004_500.0

"""
    make_assistant_work_document_example() -> AssistantWork

The work page of an assistant whose agent fixes a parser: the plan "tasks" with
a step in progress and a blocked step, the plan of the plan mode, a subagent
"Explore" that ended, with its prompt and its answer, a background task
`make test` that ended, the tree of the processes of the agent, and a notice.
"""
function make_assistant_work_document_example()
    conversation = ConversationConversation([
        ConversationTurn(:user,
            [ConversationPart("Fix the parser: a trailing comma breaks the parse.")]),
        ConversationTurn(:assistant,
            [ConversationPart("I read the failing test first, then change the rule.")])])
    a = Assistant(; backend = :acp, agent_title = "Fix the parser", conversation,
                  agent_usage = AgentUsageUpdate(41_000, 200_000, nothing, ""))
    steps = [AgentPlanEntry("Read the failing test", :high, :completed; id = "1"),
             AgentPlanEntry("Fix the parser", :high, :in_progress; id = "2",
                            active_title = "Fixing the parser"),
             AgentPlanEntry("Run the parser tests", :medium, :pending; id = "3",
                            blocked_by = ["2"])]
    plan_mode = "Read the failing test, then change the rule of the comma."
    summary = "The tests of the parser are in test/parser/."
    prompt = LlmMessage(:user, [LlmText("Find the tests of the parser.")])
    # No editor: none of these events reads a tool.
    for event in (AgentPlanUpdate(steps; id = "tasks"),
                  AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode",
                                  markdown = plan_mode),
                  AgentSubagentUpdate("explore"; title = "Explore",
                                      description = "Find the tests of the parser",
                                      event = prompt),
                  AgentSubagentUpdate("explore"; state = :idle, stop_reason = :end_turn,
                                      token_count = 12_400, tool_call_count = 6,
                                      duration = 18.5, last_tool = "Grep",
                                      summary))
        apply_agent_event!(nothing, a, event)
    end
    work = a.agent_work
    # The text of a subagent goes into the turn of a session that runs, and the
    # example has no session, so its answer is a turn of its transcript.
    answer = ConversationPart(summary)
    push!(work.subagents[1].conversation.turns, ConversationTurn(:assistant, [answer]))
    push!(work.background_tasks, _make_example_background_task())
    notice = AgentNotice(:warning, "Retrying", "The model is busy.",
                         _EXAMPLE_WORK_START + 10)
    push!(work.notices, notice)
    work.processes = make_system_process_tree_document_example()
    AssistantWork(a)
end

# The background task `make test` that ran 42 seconds and passed, as its document
# is once a window synced its end. An event of a background task registers its
# execution with the feed of the tasks of the session, which only a window drains,
# so the example builds the document of the task itself.
function _make_example_background_task()
    task = AgentBackgroundTask("", "build", :local_bash, "make test", "", "", "",
                               "All 214 tests pass.", false)
    execution = TaskExecution(task)
    update_task_execution!(execution) do e
        e.status = :running
        e.start_time = _EXAMPLE_WORK_START
    end
    result = AgentBackgroundTaskResult(task, "DONE", "DONE", nothing, 42.0)
    finish_task_execution!(execution, result)
    update_task_execution!(e -> (e.end_time = _EXAMPLE_WORK_START + 42), execution)
    shadow = make_task_execution_shadow(execution)
    add_task_execution!(TaskDocument(task), execution, shadow)
end

# The subagent of the work page, for the catalog: its page shows its facts, its
# transcript and its links.
make_agent_work_document_example() = make_assistant_work_document_example().subagents[1]
