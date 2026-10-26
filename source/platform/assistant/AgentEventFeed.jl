# Fragment of `AssistantModule` — the events of the session of an external agent
# and of a turn of the built-in assistant, applied to their assistant, and the feed
# of a window that applies them. Each event of a session goes into the queue of the
# session, in a prompt and between two prompts, so the events apply in the order in
# which they came: the text, the reasoning and the tool calls into the turn that
# takes them, and the work of the agent into the `AgentWork` of the assistant. Each
# event of a turn goes into the queue of the turn in the same way.

# ── One event ────────────────────────────────────────────────────────────────

# The events of the work of an agent, of its session or of a subagent.
const _AgentWorkUpdate = Union{AgentSubagentUpdate,AgentBackgroundTaskUpdate,
                               AgentNoticeUpdate,AgentCompactionUpdate}

"""
    apply_agent_event!(editor, assistant, event)

Apply one event of the session of the external agent of `assistant`, on the task
of `editor`.

- The text, the reasoning, the tool calls, the plans and the questions of the
  agent go into the transcript: into the turn of the prompt that runs, else into
  a turn that the agent started by itself, which ends at the next prompt or at
  the usage that the agent reports at its end.
- The options, the usage, the title and the commands of the session go into the
  fields of the assistant that hold them.
- The work of the agent goes into `agent_work`: a subagent with a transcript of
  its own, a plan as a `WorkPlan`, a background task as a `TaskDocument`, a
  notice or a compaction as an `AgentNotice`, and the process of the session as
  a `SystemProcessTree`.

The feed of the window calls it for each event in the queue of a session, in the
order in which the events came ([`AgentEventFeed`](@ref)).

# Example

    apply_agent_event!(editor, assistant,
                       AgentNoticeUpdate(:warning, "The model is busy", ""))
"""
function apply_agent_event!(editor, a::Assistant, event)
    session = a.agent_session
    if event isa AgentOptionsUpdate
        a.agent_options = event.options
    elseif event isa AgentUsageUpdate
        a.agent_usage = event
        # The usage that the agent reports between two prompts ends the turn that
        # it started by itself.
        session isa ExternalAgentSession && session.prompt_turn === nothing &&
            _end_agent_turn!(a, session)
    elseif event isa AgentCommandsUpdate
        a.agent_commands = event.commands
    elseif event isa AgentSessionInfoUpdate
        event.title === nothing || (a.agent_title = event.title)
        event.process_id === nothing ||
            _set_agent_work_process!(a.agent_work, event.process_id)
    elseif event isa _AgentWorkUpdate
        _apply_agent_work_update!(editor, a, a.agent_work, event)
    else
        state = session isa ExternalAgentSession ?
                _find_session_turn!(a, session, event) : nothing
        state === nothing ||
            _handle_external_agent_event!(event, a, state[:turn], state,
                                          _find_editor_tool_set(editor))
        event isa AgentPlanUpdate && _apply_work_plan_update!(a.agent_work, event)
    end
    nothing
end

# ── The turns ────────────────────────────────────────────────────────────────

# The state of the turn that takes a transcript event of the session: the turn of
# the prompt that runs, else the turn that the agent started by itself, which an
# event that puts a part begins.
function _find_session_turn!(a::Assistant, session::ExternalAgentSession, event)
    state = session.prompt_turn
    if state !== nothing
        _split_steered_turn!(a, state, state[:control])
        return state
    end
    state = session.agent_turn
    state === nothing || return state
    _opens_agent_turn(event) || return nothing
    session.agent_turn = _open_agent_turn!(a.conversation)
end

# Whether `event` begins a turn when none is open: an event that ends a block, or
# a plan that does not show, does not.
_opens_agent_turn(event) =
    !(event isa Union{LlmTextStop,LlmThinkingStop,LlmThinkingSignature}) &&
    !(event isa AgentPlanUpdate && !_has_plan_part(event))

# A new assistant turn at the end of `conversation`, and the state that its events
# fill.
function _open_agent_turn!(conversation::ConversationConversation)
    turn = ConversationTurn(:assistant; start_time = time())
    push!(conversation.turns, turn)
    _make_agent_turn_state(turn)
end

# The turn of `state` ends: its open blocks close, and it gets its stop reason and
# the time of its end. An empty turn leaves `conversation`.
function _end_agent_turn_state!(a::Assistant, conversation::ConversationConversation,
                                state, stop_reason::Symbol)
    _close_agent_blocks!(a, state)
    _finish_turn!(conversation, state[:turn], stop_reason)
end

function _cancel_agent_questions!(state)
    foreach(_cancel_agent_request!, state[:permission_requests])
    foreach(_cancel_agent_request!, state[:question_requests])
    nothing
end

# The turn that the agent started by itself between two prompts ends. Its
# questions still wait for the person, until the end of the next prompt.
function _end_agent_turn!(a::Assistant, session::ExternalAgentSession)
    state = session.agent_turn
    state === nothing && return nothing
    session.agent_turn = nothing
    append!(session.waiting_requests, state[:permission_requests],
            state[:question_requests])
    _end_agent_turn_state!(a, a.conversation, state, :end_turn)
end

# ── A prompt ─────────────────────────────────────────────────────────────────

# A queue for the events of the session, which joins the feed of the window. The
# join is posted and not waited for, so the start of a session waits for the
# editor under no lock; the posts of a task apply before a later call of that task
# that waits, such as the start of the prompt.
function _make_agent_event_queue!(editor, a::Assistant, session::ExternalAgentSession)
    queue = AgentEventQueue()
    session.events = queue
    run_on_editor_task!(editor; wait = false) do
        _register_agent_event_queue!(editor, a, session, queue)
    end
    queue
end

# The work of the session `session_id`: the work that the assistant has when it is
# the work of that session, as after a resume, else an empty one.
function _start_agent_work!(a::Assistant, session::ExternalAgentSession,
                            session_id::AbstractString)
    a.agent_work.id == session_id && return nothing
    empty!(session.subagent_turns)
    a.agent_work = AgentWork(session_id)
    nothing
end

# The prompt begins to take the events of the session: the events that came
# before it apply first, a turn that the agent started by itself ends, and the
# turn of the prompt joins the conversation. The questions of the agent between
# two prompts that still wait end with this prompt.
function _start_agent_prompt_turn!(editor, a::Assistant, session::ExternalAgentSession,
                                   state, queue::AgentEventQueue)
    _drain_agent_event_queue!(editor, a, queue)
    _end_agent_turn!(a, session)
    foreach(request -> _hold_agent_request!(state, request), session.waiting_requests)
    empty!(session.waiting_requests)
    push!(a.conversation.turns, state[:turn])
    session.prompt_turn = state
    nothing
end

# The prompt ends: its events that wait apply, and a question that the person did
# not answer is cancelled. The events after it begin a turn of their own.
function _end_agent_prompt_turn!(editor, a::Assistant, session::ExternalAgentSession,
                                 state, queue)
    _drain_agent_event_queue!(editor, a, queue)
    _cancel_agent_questions!(state)
    if session.prompt_turn === state
        session.prompt_turn = nothing
        session.prompt_end_time = time()
    end
    nothing
end

# An event of a prompt goes into the queue of its session, behind the events that
# came before it. An editor whose loop runs applies the queue in its next frame,
# for which the event asks, and the turn never waits for it. With no loop, such
# as in a test, a call through the door runs at once on the task that makes it,
# and so does the queue: the turn then runs on the thread of its caller.
function _post_agent_event!(editor, a::Assistant, queue::AgentEventQueue, event)
    put_agent_event!(queue, event)
    if editor isa Editor && is_editor_loop_running(editor)
        wake_editor!(editor)
    else
        _drain_agent_event_queue!(editor, a, queue)
    end
    nothing
end

# Apply every event that waits in `queue`, the oldest first, and answer how many
# there were.
function _drain_agent_event_queue!(editor, a::Assistant, queue)
    queue === nothing && return 0
    _apply_agent_events!(event -> apply_agent_event!(editor, a, event), editor,
                         take_agent_events!(queue))
end

# Apply each of `events` with `apply`, the oldest first, and answer how many there
# were. An event that fails to apply is a fault of the editor, and the next event
# still applies.
function _apply_agent_events!(apply, editor, events)
    for event in events
        try
            apply(event)
        catch exception
            is_fault_exception(exception) || rethrow()
            traceback = catch_backtrace()
            record_fault!(get_fault_store(editor), :evaluate; origin = :Assistant,
                          exception, traceback)
            @error("An event of the agent did not apply.",
                   exception = (exception, traceback))
        end
    end
    length(events)
end

# ── A turn of the built-in assistant ─────────────────────────────────────────

# The queue of a turn of the built-in assistant. The model streams the events of
# the turn into it off the loop, and the feed of the window applies them to the
# turn, as it applies the events of a session of an external agent. The turn joins
# the source to the feed before its first event, and removes it at its end.
struct _TurnEventSource
    assistant::Assistant
    queue::AgentEventQueue
    turn::ConversationTurn
    # The blocks that stream: the text part and the thinking part.
    state::Dict{Symbol,Any}
    # The `ToolSet` of the editor, which makes the result of a tool a document.
    tools::Any
end

_TurnEventSource(a::Assistant, turn::ConversationTurn, state, tools) =
    _TurnEventSource(a, AgentEventQueue(), turn, state, tools)

# Apply one event to the turn of `source`.
_handle_turn_event!(source::_TurnEventSource, event) =
    _handle_agent_event!(event, source.assistant, source.turn, source.state, source.tools)

# An event of the turn goes into its queue, behind the events before it. An editor
# whose loop runs applies the queue in its next frame, and the turn does not wait.
# With no loop, as in a test, the event applies at once.
function _post_turn_event!(editor, source::_TurnEventSource, event)
    put_agent_event!(source.queue, event)
    if editor isa Editor && is_editor_loop_running(editor)
        wake_editor!(editor)
    else
        _drain_agent_event_source!(editor, source)
    end
    nothing
end

# `events` with each run of text deltas, and each run of thinking deltas, joined
# into one delta of their text. Each delta type has the one field `text`, so a
# joined delta is the type of the first delta of its run, made from the texts.
function _join_stream_deltas(events)
    joined = Any[]
    texts = String[]
    for event in events
        if !isempty(texts) && typeof(event) !== typeof(last(joined))
            joined[end] = typeof(last(joined))(join(texts))
            empty!(texts)
        end
        if event isa Union{LlmTextDelta, LlmThinkingDelta}
            isempty(texts) && push!(joined, event)
            push!(texts, event.text)
        else
            push!(joined, event)
        end
    end
    isempty(texts) || (joined[end] = typeof(last(joined))(join(texts)))
    joined
end

# Run `f` on the task of the editor, as a call of the turn, after every event that
# the turn posted before the call. So the call reads a conversation that holds
# each part that the turn streamed before it. The keywords are those of
# `run_on_editor_task!`, such as `wait` and `timeout`.
_run_turn_call!(f, editor, source::_TurnEventSource; keywords...) =
    run_on_editor_task!(editor; keywords...) do
        _drain_agent_event_source!(editor, source)
        f()
    end

# ── The work of the agent ────────────────────────────────────────────────────

function _apply_agent_work_update!(editor, a::Assistant, work::AgentWork, event)
    if event isa AgentSubagentUpdate
        _apply_subagent_update!(editor, a, work, event)
    elseif event isa AgentBackgroundTaskUpdate
        _apply_background_task_update!(a, work, event)
    elseif event isa AgentNoticeUpdate
        _add_agent_notice!(work, event.severity, event.title, event.description)
    elseif event isa AgentCompactionUpdate
        severity, title = get(_COMPACTION_NOTICES, event.status,
                              (:info, "The context was compacted"))
        _add_agent_notice!(work, severity, title, something(event.summary, ""))
    end
    nothing
end

# The notice of a compaction of the context, by its status.
const _COMPACTION_NOTICES = Dict(
    :in_progress => (:info, "The context is being compacted"),
    :completed => (:info, "The context was compacted"),
    :failed => (:warning, "The compaction of the context failed"),
    :cancelled => (:info, "The compaction of the context was cancelled"))

# The subagent of an update under `parent`, found by its id or added, with the
# fields that the update gives, and the event of the update applied to it. A
# subagent that starts to run keeps the time, and one that becomes idle ends its
# turn.
function _apply_subagent_update!(editor, a::Assistant, parent::AgentWork,
                                 update::AgentSubagentUpdate)
    child = _find_subagent(parent, update.id)
    if child === nothing
        child = AgentWork(update.id)
        push!(parent.subagents, child)
    end
    update.state === :running && child.state !== :running && (child.start_time = time())
    for (name, value) in (:title => update.title, :description => update.description,
                          :state => update.state, :stop_reason => update.stop_reason,
                          :token_count => update.token_count,
                          :tool_call_count => update.tool_call_count,
                          :duration => update.duration, :last_tool => update.last_tool,
                          :summary => update.summary, :can_cancel => update.can_cancel)
        value === nothing || isequal(getproperty(child, name), value) ||
            setproperty!(child, name, value)
    end
    update.event === nothing || _apply_subagent_event!(editor, a, child, update.event)
    update.state === :idle && _end_subagent_turn!(a, child)
    nothing
end

function _find_subagent(work::AgentWork, id::AbstractString)
    for child in collect(work.subagents)
        child.id == id && return child
    end
    nothing
end

# One event of a subagent: a subagent of it, its prompt, its work, or its
# transcript. The options, the usage, the title and the commands of the session of
# a subagent are in the fields of its update.
function _apply_subagent_event!(editor, a::Assistant, child::AgentWork, event)
    if event isa _AgentWorkUpdate
        _apply_agent_work_update!(editor, a, child, event)
    elseif event isa LlmMessage
        event.role === :user && _add_subagent_prompt!(a, child, event)
    elseif event isa Union{AgentPermissionRequest,AgentQuestionRequest}
        _add_subagent_request!(a, child, event)
    elseif !(event isa Union{AgentOptionsUpdate,AgentUsageUpdate,AgentCommandsUpdate,
                             AgentSessionInfoUpdate})
        state = _find_subagent_turn!(a, child, event)
        state === nothing ||
            _handle_external_agent_event!(event, a, state[:turn], state,
                                          _find_editor_tool_set(editor))
        event isa AgentPlanUpdate && _apply_work_plan_update!(child, event)
    end
    nothing
end

# The state of the open turn of `child`, which takes its transcript, else of a new
# turn that an event that puts a part begins. The session of the assistant keeps
# the states.
function _find_subagent_turn!(a::Assistant, child::AgentWork, event)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    state = get(session.subagent_turns, child, nothing)
    state === nothing || return state
    _opens_agent_turn(event) || return nothing
    session.subagent_turns[child] = _open_agent_turn!(child.conversation)
end

# The open turn of `child` ends, with the stop reason of the subagent, and a
# question of the subagent that nobody answered is cancelled.
function _end_subagent_turn!(a::Assistant, child::AgentWork)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    state = pop!(session.subagent_turns, child, nothing)
    state === nothing && return nothing
    _cancel_agent_questions!(state)
    _end_agent_turn_state!(a, child.conversation, state,
                           something(child.stop_reason, :end_turn))
end

# A question of a subagent for the person shows in two places that hold the one
# request: in the transcript of the subagent, whose end cancels it when nobody
# answered, and in the turn of the session that runs, where the person looks. An
# answer in either place is the answer of both, and its reply goes to the agent.
function _add_subagent_request!(a::Assistant, child::AgentWork,
                                event::Union{AgentPermissionRequest,AgentQuestionRequest})
    asker = isempty(child.title) ? "A subagent" : "The subagent “" * child.title * "”"
    request = _make_agent_request(event, asker)
    state = _find_subagent_turn!(a, child, event)
    if state !== nothing
        _close_agent_blocks!(a, state)
        _add_agent_request!(state, request)
    end
    session = a.agent_session
    shown = session isa ExternalAgentSession ? _find_session_turn!(a, session, event) :
            nothing
    if shown !== nothing
        _close_agent_blocks!(a, shown)
        push!(shown[:turn].parts, Cell(ConversationPart(request)))
    end
    nothing
end

# The prompt of a subagent is a turn of the person in its transcript, after the
# turn of the subagent before it.
function _add_subagent_prompt!(a::Assistant, child::AgentWork, message::LlmMessage)
    _end_subagent_turn!(a, child)
    parts = Any[ConversationPart(content.text) for content in message.content
                if content isa LlmText]
    isempty(parts) || push!(child.conversation.turns, _make_instant_turn(:user, parts))
    nothing
end

# The result code of a background task that ended, by its status.
const _BACKGROUND_TASK_CODES =
    Dict(:completed => "DONE", :failed => "ERROR", :stopped => "CANCEL")

# The task of an update in the work, found by its task id or added as a
# `TaskDocument`, with the fields that the update gives.
function _apply_background_task_update!(a::Assistant, work::AgentWork,
                                        update::AgentBackgroundTaskUpdate)
    document = _find_background_task_document(work, update.id)
    if document === nothing
        blank = AgentBackgroundTask(a.agent_work.id, update.id, :other, "", "", "", "",
                                    "", false)
        task = _merge_background_task(blank, update)
        document = TaskDocument(task)
        push!(work.background_tasks, document)
    else
        task = _merge_background_task(document.task, update)
        isequal(task, document.task) || (document.task = task)
    end
    _follow_background_task_status!(document, task, update)
end

function _find_background_task_document(work::AgentWork, task_id::AbstractString)
    for document in collect(work.background_tasks)
        document.task.task_id == task_id && return document
    end
    nothing
end

# The task with what an update gives. A field that the update leaves out keeps its
# value, and a task that ended can not be stopped.
function _merge_background_task(task::AgentBackgroundTask,
                                update::AgentBackgroundTaskUpdate)
    is_ended = update.status !== nothing && haskey(_BACKGROUND_TASK_CODES, update.status)
    AgentBackgroundTask(task.session_id, task.task_id, something(update.kind, task.kind),
                        something(update.title, task.title),
                        something(update.tool_call_id, task.tool_call_id),
                        something(update.subagent_id, task.subagent_id),
                        something(update.output_uri, task.output_uri),
                        something(update.summary, task.summary),
                        !is_ended && something(update.can_stop, task.can_stop))
end

# The execution of the task follows its status. The first status starts an
# execution that has no process, and a status that ends the task ends it, with the
# times that the agent gives. The feed of the tasks syncs the shadow of the
# execution, as for any execution.
function _follow_background_task_status!(document::TaskDocument,
                                         task::AgentBackgroundTask,
                                         update::AgentBackgroundTaskUpdate)
    update.status === nothing && return nothing
    execution = document.running
    if execution === nothing
        execution = TaskExecution(task)
        started = something(update.start_time, time())
        update_task_execution!(execution) do e
            e.status = :running
            e.start_time = started
        end
        shadow = make_task_execution_shadow(execution)
        add_task_execution!(document, execution, shadow)
        register_task_execution!(get_session_task_feed_store(), execution, document;
                                 shadow)
    end
    code = get(_BACKGROUND_TASK_CODES, update.status, nothing)
    (code === nothing || execution.result !== nothing) && return nothing
    ended = something(update.end_time, time())
    elapsed = ended - something(execution.start_time, ended)
    # A stop ends a task on purpose: a stopped task expects CANCEL, and a task
    # that failed expects DONE.
    expected = code == "CANCEL" ? code : "DONE"
    result = AgentBackgroundTaskResult(task, code, expected, nothing, elapsed)
    finish_task_execution!(execution, result)
    update.end_time === nothing ||
        update_task_execution!(e -> (e.end_time = ended), execution)
    nothing
end

# The tree of the processes of the work: the process that the agent names, and a
# new tree when it names another one.
function _set_agent_work_process!(work::AgentWork, process_id::Int)
    tree = work.processes
    tree !== nothing && collect(tree.root_process_ids) == [process_id] && return nothing
    work.processes = SystemProcessTree([process_id])
    nothing
end

# The plan of an update in the work, found by its id or added: its steps, its text
# and its file, each written only when it changed. A removal takes the plan out.
function _apply_work_plan_update!(work::AgentWork, update::AgentPlanUpdate)
    plans = work.plans
    index = findfirst(plan -> plan.id == update.id, collect(plans))
    if update.is_removed
        index === nothing || deleteat!(plans, index)
        return nothing
    end
    if index === nothing
        plan = WorkPlan(update.id; title = isempty(update.id) ? "Plan" : update.id)
        push!(plans, plan)
    else
        plan = plans[index]
    end
    steps = _build_work_plan_steps(plan, update.entries)
    current = collect(plan.steps)
    is_same = length(current) == length(steps) &&
              all(k -> current[k] === steps[k], eachindex(steps))
    is_same || set_work_plan_steps!(plan, steps)
    text = something(update.markdown, "")
    plan.text == text || (plan.text = text)
    uri = something(update.uri, "")
    plan.uri == uri || (plan.uri = uri)
    nothing
end

# The steps of the entries of a plan update. A step keeps its document from one
# update to the next by its id, with the fields of its entry written, so a view of
# the plan keeps its open steps. An entry with no id is named by its place.
function _build_work_plan_steps(plan::WorkPlan, entries)
    known = Dict{String,Any}(step.id => step for step in collect(plan.steps))
    steps = Any[]
    for (index, entry) in enumerate(entries)
        id = isempty(entry.id) ? string(index) : entry.id
        status = entry.status in WORK_PLAN_STEP_STATUSES ? entry.status : :pending
        priority = entry.priority in (:high, :medium, :low) ? entry.priority : :medium
        step = get(known, id, nothing)
        if step === nothing
            step = WorkPlanStep(id, entry.content; active_title = entry.active_title,
                                description = entry.description, status, priority,
                                blocked_by = entry.blocked_by)
        else
            for (name, value) in (:title => entry.content,
                                  :active_title => entry.active_title,
                                  :description => entry.description, :status => status,
                                  :priority => priority)
                isequal(getproperty(step, name), value) || setproperty!(step, name, value)
            end
            collect(step.blocked_by) == entry.blocked_by ||
                (step.blocked_by = copy(entry.blocked_by))
        end
        push!(steps, step)
    end
    steps
end

# ── The end of the work ──────────────────────────────────────────────────────

# The connection of the session ended: the agent stopped, its connection failed
# or stopped, the agent starts again, or the assistant was reset. The agent may
# send nothing more, as when its process died, so the work that ran ends here: a
# turn that the agent started by itself ends, a question that waits is
# cancelled, and the work of the assistant ends (`_end_running_agent_work!`).
function _end_agent_work!(a::Assistant, session::ExternalAgentSession)
    _end_agent_turn!(a, session)
    foreach(_cancel_agent_request!, session.waiting_requests)
    empty!(session.waiting_requests)
    _end_running_agent_work!(a, a.agent_work)
    empty!(session.subagent_turns)
    nothing
end

# A question that waits is answered as cancelled.
_cancel_agent_request!(request::ConversationPermissionRequest) =
    answer_permission_request!(request, nothing)
_cancel_agent_request!(request::ConversationQuestionRequest) =
    answer_question_request!(request, nothing)

# Each background task of the work that runs ends as CANCEL, "The agent ended.",
# and each subagent that runs becomes idle with the stop reason `:cancelled`, its
# turn ends and its questions are cancelled; at every depth.
function _end_running_agent_work!(a::Assistant, work::AgentWork)
    for document in collect(work.background_tasks)
        execution = document.running
        (execution === nothing || execution.result !== nothing) && continue
        stop = AgentBackgroundTaskUpdate(document.task.task_id; can_stop = false)
        task = _merge_background_task(document.task, stop)
        isequal(task, document.task) || (document.task = task)
        ended = time()
        elapsed = ended - something(execution.start_time, ended)
        result = AgentBackgroundTaskResult(task, "CANCEL", "CANCEL", "The agent ended.",
                                           elapsed)
        finish_task_execution!(execution, result)
    end
    for child in collect(work.subagents)
        if child.state in (:running, :requires_action)
            child.state = :idle
            child.stop_reason = :cancelled
        end
        _end_subagent_turn!(a, child)
        _end_running_agent_work!(a, child)
    end
    nothing
end

# ── The feed ─────────────────────────────────────────────────────────────────

"""
    AgentEventFeed()

The feed of a window whose assistants stream events: the sessions of external
agents and the turns of the built-in assistant. An assistant registers there the
queue of each session that it opens and of each turn that it runs, and each drain
applies the events that wait in each queue, the oldest first: an event of a
session with [`apply_agent_event!`](@ref), an event of a turn to its turn. The
events of a prompt and the events between two prompts take this one path, so they
apply in the order in which they came. A drain also samples each tree of the
processes of the work of an agent that a view reads. The queue of a session
leaves the feed at the drain after its session closed, its connection stopped or
its assistant ended it; the queue of a turn leaves it when its turn ends.

The wrapper `agent_event` of `build_editor` gives the feed, and is on by
default; the `TaskFeed` of the wrapper `task` syncs the background tasks of the
agents. An editor whose loop runs needs the feed to apply the events; with no
loop, as in a test, the events apply at once. An event of a prompt or of a turn
asks for a frame itself.
Between two prompts the window wakes four times a second while an agent has a
subagent or a background task that runs, and for five seconds after a prompt
ends, because an agent reports more after its answer; it wakes for the next
sample of a tree of processes that a view reads; and else it sleeps, so an idle
window draws nothing.
"""
struct AgentEventFeed <: Feed
    sources::Vector{Any}
end

AgentEventFeed() = AgentEventFeed(Any[])

# How often a window wakes while the work of an agent runs, and how long after the
# end of a prompt it still wakes, in seconds.
const _AGENT_EVENT_INTERVAL = 0.25
const _AGENT_EVENT_LINGER = 5.0

# The queue of a session of `a` joins the feed of the editor.
_register_agent_event_queue!(editor, a::Assistant, session::ExternalAgentSession,
                             queue::AgentEventQueue) =
    _add_agent_event_source!(editor, (assistant = a, session = session, queue = queue))

# `source` joins the feed of the editor, which the editor got when it was made. An
# editor with no feed and no loop, as in a test, applies the events of a prompt or
# a turn at once and drains no queue between two prompts. An editor whose loop
# runs applies an event only through the feed, so it must have one.
function _add_agent_event_source!(editor, source)
    hasproperty(editor, :feeds) || return nothing
    index = findfirst(feed -> feed isa AgentEventFeed, editor.feeds)
    if index === nothing
        editor isa Editor && is_editor_loop_running(editor) &&
            throw(ArgumentError("The editor has no AgentEventFeed, so no event of the " *
                                "agent reaches its window. Make it with build_editor, " *
                                "whose wrapper agent_event gives the feed."))
        return nothing
    end
    push!(editor.feeds[index].sources, source)
    nothing
end

# The turn of `source` ended: the source leaves the feed at once, also in an editor
# whose feeds no loop drains.
function _remove_agent_event_source!(editor, source::_TurnEventSource)
    hasproperty(editor, :feeds) || return nothing
    for feed in editor.feeds
        feed isa AgentEventFeed && filter!(other -> other !== source, feed.sources)
    end
    nothing
end

# Whether the queue of `source` is still the queue of an open session of its
# assistant. The source of a turn is open while it is in the feed: its turn removes
# it at its end.
_is_agent_event_source_open(source) =
    source.session.events === source.queue &&
    source.assistant.agent_session === source.session
_is_agent_event_source_open(::_TurnEventSource) = true

# Apply the events that wait in the queue of `source`. The queue of a turn applies
# each run of text deltas and each run of thinking deltas as one delta, so a frame
# appends to a part once.
_drain_agent_event_source!(editor, source) =
    _drain_agent_event_queue!(editor, source.assistant, source.queue)
_drain_agent_event_source!(editor, source::_TurnEventSource) =
    _apply_agent_events!(event -> _handle_turn_event!(source, event), editor,
                         _join_stream_deltas(take_agent_events!(source.queue)))

# A turn of the built-in assistant has no tree of processes to sample.
_drain_agent_source_processes!(source, now) = _drain_agent_work_processes!(source.assistant.agent_work, now)
_drain_agent_source_processes!(::_TurnEventSource, now) = 0

function drain_changes!(feed::AgentEventFeed, editor)
    now = time()
    count = 0
    for source in copy(feed.sources)
        count += _drain_agent_event_source!(editor, source)
        if _is_agent_event_source_open(source)
            count += _drain_agent_source_processes!(source, now)
        else
            filter!(other -> other !== source, feed.sources)
        end
    end
    count
end

function compute_wake_deadline(feed::AgentEventFeed, editor)
    now = time()
    deadline = nothing
    for source in feed.sources
        # Each event of a turn of the built-in assistant wakes the editor itself.
        source isa _TurnEventSource && continue
        # A session that closed wakes nothing; its source leaves at the next drain.
        _is_agent_event_source_open(source) || continue
        work = source.assistant.agent_work
        is_awake = _count_running_subagents(work) > 0 ||
                   _count_running_background_tasks(work) > 0 ||
                   now - source.session.prompt_end_time < _AGENT_EVENT_LINGER
        is_awake && return _AGENT_EVENT_INTERVAL
        deadline = _get_earlier_deadline(deadline,
                                         _compute_agent_work_process_deadline(work, now))
    end
    deadline
end

"""
    agent_event = true

The wrapper of `build_editor` that gives the editor an [`AgentEventFeed`](@ref),
so the events of each session of an agent and of each turn of the built-in
assistant reach the window. It is on by default: a feed with no source asks for
no frame.
"""
function wrap_editor!(::Val{:agent_event}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, AgentEventFeed())
    parts
end

get_wrapper_layers(::Val{:agent_event}) = (:screen => 20,)
is_wrapper_default(::Val{:agent_event}) = true

# Each tree of the processes of the work and of its subagents takes its sample,
# and the count of the reads that were synced.
function _drain_agent_work_processes!(work::AgentWork, now)
    tree = work.processes
    count = tree === nothing ? 0 : drain_system_process_tree!(tree; now)
    for child in collect(work.subagents)
        count += _drain_agent_work_processes!(child, now)
    end
    count
end

# The seconds until the next sample of a tree of the processes of the work that a
# view reads, or `nothing`.
function _compute_agent_work_process_deadline(work::AgentWork, now)
    tree = work.processes
    deadline = tree === nothing ? nothing :
               compute_system_process_tree_deadline(tree; now)
    for child in collect(work.subagents)
        deadline = _get_earlier_deadline(deadline,
                                         _compute_agent_work_process_deadline(child, now))
    end
    deadline
end

_get_earlier_deadline(first, second) =
    first === nothing ? second : second === nothing ? first : min(first, second)
