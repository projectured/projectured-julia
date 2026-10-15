# Fragment of `AssistantModule` — the events of the session of an external agent
# applied to its assistant, and the feed of a window that applies them. Each event
# of a session goes into the queue of the session, in a prompt and between two
# prompts, so the events apply in the order in which they came: the text, the
# reasoning and the tool calls into the turn that takes them, and the work of the
# agent into the `AgentWork` of the assistant.

# ── One event ────────────────────────────────────────────────────────────────

# The events of the work of an agent, of its session or of a subagent.
const _AgentWorkUpdate = Union{AgentSubagentUpdate,AgentBackgroundTaskUpdate,AgentNoticeUpdate,
                               AgentCompactionUpdate}

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

    apply_agent_event!(editor, assistant, AgentNoticeUpdate(:warning, "The model is busy", ""))
"""
function apply_agent_event!(editor, a::Assistant, event)
    session = a.agent_session
    if event isa AgentOptionsUpdate
        a.agent_options = event.options
    elseif event isa AgentUsageUpdate
        a.agent_usage = event
        # The usage that the agent reports between two prompts ends the turn that
        # it started by itself.
        session isa ExternalAgentSession && session.prompt_turn === nothing && _end_agent_turn!(a, session)
    elseif event isa AgentCommandsUpdate
        a.agent_commands = event.commands
    elseif event isa AgentSessionInfoUpdate
        event.title === nothing || (a.agent_title = event.title)
        event.process_id === nothing || _set_agent_work_process!(a.agent_work, event.process_id)
    elseif event isa _AgentWorkUpdate
        _apply_agent_work_update!(editor, a, a.agent_work, event)
    else
        state = session isa ExternalAgentSession ? _find_session_turn!(a, session, event) : nothing
        state === nothing ||
            _handle_external_agent_event!(event, a, state[:turn], state, _find_editor_tool_set(editor))
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
function _end_agent_turn_state!(a::Assistant, conversation::ConversationConversation, state,
                                stop_reason::Symbol)
    _close_agent_blocks!(a, state)
    _finish_turn!(conversation, state[:turn], stop_reason)
end

function _cancel_agent_questions!(state)
    foreach(request -> answer_permission_request!(request, nothing), state[:permission_requests])
    foreach(request -> answer_question_request!(request, nothing), state[:question_requests])
    nothing
end

# The turn that the agent started by itself between two prompts ends. Its
# questions still wait for the person, until the end of the next prompt.
function _end_agent_turn!(a::Assistant, session::ExternalAgentSession)
    state = session.agent_turn
    state === nothing && return nothing
    session.agent_turn = nothing
    append!(session.waiting_requests, state[:permission_requests], state[:question_requests])
    _end_agent_turn_state!(a, a.conversation, state, :end_turn)
end

# ── A prompt ─────────────────────────────────────────────────────────────────

# A queue for the events of the session, which joins the feed of the window.
function _make_agent_event_queue!(editor, a::Assistant, session::ExternalAgentSession)
    queue = AgentEventQueue()
    session.events = queue
    run_on_editor_task!(() -> _register_agent_event_queue!(editor, a, session, queue), editor)
    queue
end

# The work of the session `session_id`: the work that the assistant has when it is
# the work of that session, as after a resume, else an empty one.
function _start_agent_work!(a::Assistant, session::ExternalAgentSession, session_id::AbstractString)
    a.agent_work.id == session_id && return nothing
    empty!(session.subagent_turns)
    a.agent_work = AgentWork(session_id)
    nothing
end

# The prompt begins to take the events of the session: the events that came
# before it apply first, a turn that the agent started by itself ends, and the
# turn of the prompt joins the conversation. The questions of the agent between
# two prompts that still wait end with this prompt.
function _start_agent_prompt_turn!(editor, a::Assistant, session::ExternalAgentSession, state,
                                   queue::AgentEventQueue)
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
function _end_agent_prompt_turn!(editor, a::Assistant, session::ExternalAgentSession, state, queue)
    _drain_agent_event_queue!(editor, a, queue)
    _cancel_agent_questions!(state)
    if session.prompt_turn === state
        session.prompt_turn = nothing
        session.prompt_end_time = time()
    end
    nothing
end

# An event of a prompt goes into the queue of its session, behind the events that
# came before it. An editor whose loop runs on another task applies the queue in
# its next frame, for which the event asks; another editor, such as the one of a
# test, applies the queue at once, on this task.
function _post_agent_event!(editor, a::Assistant, queue::AgentEventQueue, event)
    put_agent_event!(queue, event)
    if editor isa Editor && editor.loop_task !== nothing && editor.loop_task !== current_task()
        wake_editor!(editor)
    else
        _drain_agent_event_queue!(editor, a, queue)
    end
    nothing
end

# Apply every event that waits in `queue`, the oldest first, and answer how many
# there were. An event that fails to apply is a fault of the editor, and the next
# event still applies.
function _drain_agent_event_queue!(editor, a::Assistant, queue)
    queue === nothing && return 0
    events = take_agent_events!(queue)
    for event in events
        try
            apply_agent_event!(editor, a, event)
        catch exception
            is_fault_exception(exception) || rethrow()
            traceback = catch_backtrace()
            record_fault!(get_fault_store(editor), :evaluate; origin = :Assistant, exception, traceback)
            @error "An event of the agent did not apply." exception = (exception, traceback)
        end
    end
    length(events)
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
        severity, title = get(_COMPACTION_NOTICES, event.status, (:info, "The context was compacted"))
        _add_agent_notice!(work, severity, title, something(event.summary, ""))
    end
    nothing
end

# The notice of a compaction of the context, by its status.
const _COMPACTION_NOTICES = Dict(:in_progress => (:info, "The context is being compacted"),
                                 :completed => (:info, "The context was compacted"),
                                 :failed => (:warning, "The compaction of the context failed"),
                                 :cancelled => (:info, "The compaction of the context was cancelled"))

# The subagent of an update under `parent`, found by its id or added, with the
# fields that the update gives, and the event of the update applied to it. A
# subagent that becomes idle ends its turn.
function _apply_subagent_update!(editor, a::Assistant, parent::AgentWork, update::AgentSubagentUpdate)
    child = _find_subagent(parent, update.id)
    if child === nothing
        child = AgentWork(update.id)
        push!(parent.subagents, child)
    end
    for (name, value) in (:title => update.title, :description => update.description, :state => update.state,
                          :stop_reason => update.stop_reason, :token_count => update.token_count,
                          :tool_call_count => update.tool_call_count, :duration => update.duration,
                          :last_tool => update.last_tool, :summary => update.summary,
                          :can_cancel => update.can_cancel)
        value === nothing || isequal(getproperty(child, name), value) || setproperty!(child, name, value)
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
    elseif !(event isa Union{AgentOptionsUpdate,AgentUsageUpdate,AgentCommandsUpdate,AgentSessionInfoUpdate})
        state = _find_subagent_turn!(a, child, event)
        state === nothing ||
            _handle_external_agent_event!(event, a, state[:turn], state, _find_editor_tool_set(editor))
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
    _end_agent_turn_state!(a, child.conversation, state, something(child.stop_reason, :end_turn))
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
    shown = session isa ExternalAgentSession ? _find_session_turn!(a, session, event) : nothing
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
    parts = Any[ConversationPart(content.text) for content in message.content if content isa LlmText]
    isempty(parts) || push!(child.conversation.turns, _make_instant_turn(:user, parts))
    nothing
end

# The result code of a background task that ended, by its status.
const _BACKGROUND_TASK_CODES = Dict(:completed => "DONE", :failed => "ERROR", :stopped => "CANCEL")

# The task of an update in the work, found by its task id or added as a
# `TaskDocument`, with the fields that the update gives.
function _apply_background_task_update!(a::Assistant, work::AgentWork, update::AgentBackgroundTaskUpdate)
    document = _find_background_task_document(work, update.id)
    if document === nothing
        blank = AgentBackgroundTask(a.agent_work.id, update.id, :other, "", "", "", "", "", false)
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
function _merge_background_task(task::AgentBackgroundTask, update::AgentBackgroundTaskUpdate)
    is_ended = update.status !== nothing && haskey(_BACKGROUND_TASK_CODES, update.status)
    AgentBackgroundTask(task.session_id, task.task_id, something(update.kind, task.kind),
                        something(update.title, task.title), something(update.tool_call_id, task.tool_call_id),
                        something(update.subagent_id, task.subagent_id),
                        something(update.output_uri, task.output_uri), something(update.summary, task.summary),
                        !is_ended && something(update.can_stop, task.can_stop))
end

# The execution of the task follows its status. The first status starts an
# execution that has no process, and a status that ends the task ends it, with the
# times that the agent gives. The feed of the tasks syncs the shadow of the
# execution, as for any execution.
function _follow_background_task_status!(document::TaskDocument, task::AgentBackgroundTask,
                                         update::AgentBackgroundTaskUpdate)
    update.status === nothing && return nothing
    execution = document.running
    if execution === nothing
        execution = TaskExecution(task)
        started = something(update.start_time, time())
        update_task_execution!(e -> (e.status = :running; e.start_time = started), execution)
        shadow = make_task_execution_shadow(execution)
        add_task_execution!(document, execution, shadow)
        register_task_execution!(get_session_task_feed_store(), execution, document; shadow)
    end
    code = get(_BACKGROUND_TASK_CODES, update.status, nothing)
    (code === nothing || execution.result !== nothing) && return nothing
    ended = something(update.end_time, time())
    elapsed = ended - something(execution.start_time, ended)
    finish_task_execution!(execution, AgentBackgroundTaskResult(task, code, "DONE", nothing, elapsed))
    update.end_time === nothing || update_task_execution!(e -> (e.end_time = ended), execution)
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
    (length(current) == length(steps) && all(k -> current[k] === steps[k], eachindex(steps))) ||
        set_work_plan_steps!(plan, steps)
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
                                description = entry.description, status, priority, blocked_by = entry.blocked_by)
        else
            for (name, value) in (:title => entry.content, :active_title => entry.active_title,
                                  :description => entry.description, :status => status, :priority => priority)
                isequal(getproperty(step, name), value) || setproperty!(step, name, value)
            end
            collect(step.blocked_by) == entry.blocked_by || (step.blocked_by = copy(entry.blocked_by))
        end
        push!(steps, step)
    end
    steps
end

# ── The feed ─────────────────────────────────────────────────────────────────

"""
    AgentEventFeed()

The feed of a window whose assistants talk to external agents. An assistant
registers there the queue of each session that it opens, and each drain applies
the events that wait in each queue, the oldest first, with
[`apply_agent_event!`](@ref). The events of a prompt and the events between two
prompts take this one path, so they apply in the order in which they came. A
drain also samples each tree of the processes of the work of an agent that a
view reads. A queue leaves the feed at the drain after its session closed, its
connection stopped or its assistant ended it.

The assistant adds the feed to the `feeds` of the editor when the window opens
its first session, and a `TaskFeed` when the window has none, which syncs the
background tasks of the agents. An event of a prompt asks for a frame itself.
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

# The queue of a session of `a` joins the feed of the editor, which the first
# session of the window adds, with a feed of the tasks when the window has none.
# An editor with no feeds, as in a test, applies the events of a prompt at once
# and drains no queue between two prompts.
function _register_agent_event_queue!(editor, a::Assistant, session::ExternalAgentSession,
                                      queue::AgentEventQueue)
    hasproperty(editor, :feeds) || return nothing
    feeds = editor.feeds
    index = findfirst(feed -> feed isa AgentEventFeed, feeds)
    if index === nothing
        push!(feeds, AgentEventFeed())
        any(feed -> feed isa TaskFeed, feeds) || push!(feeds, TaskFeed())
        index = findfirst(feed -> feed isa AgentEventFeed, feeds)
    end
    push!(feeds[index].sources, (assistant = a, session = session, queue = queue))
    nothing
end

# Whether the queue of `source` is still the queue of an open session of its
# assistant.
_is_agent_event_source_open(source) =
    source.session.events === source.queue && source.assistant.agent_session === source.session

function drain_changes!(feed::AgentEventFeed, editor)
    now = time()
    count = 0
    for source in copy(feed.sources)
        count += _drain_agent_event_queue!(editor, source.assistant, source.queue)
        if _is_agent_event_source_open(source)
            count += _drain_agent_work_processes!(source.assistant.agent_work, now)
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
        work = source.assistant.agent_work
        (_count_running_subagents(work) > 0 || _count_running_background_tasks(work) > 0 ||
         now - source.session.prompt_end_time < _AGENT_EVENT_LINGER) && return _AGENT_EVENT_INTERVAL
        deadline = _get_earlier_deadline(deadline, _compute_agent_work_process_deadline(work, now))
    end
    deadline
end

# Each tree of the processes of the work and of its subagents takes its sample,
# and the count of the reads that were synced.
function _drain_agent_work_processes!(work::AgentWork, now)
    tree = work.processes
    count = tree === nothing ? 0 : drain_system_process_tree!(tree; now)
    count + sum((_drain_agent_work_processes!(child, now) for child in collect(work.subagents)); init = 0)
end

# The seconds until the next sample of a tree of the processes of the work that a
# view reads, or `nothing`.
function _compute_agent_work_process_deadline(work::AgentWork, now)
    tree = work.processes
    deadline = tree === nothing ? nothing : compute_system_process_tree_deadline(tree; now)
    for child in collect(work.subagents)
        deadline = _get_earlier_deadline(deadline, _compute_agent_work_process_deadline(child, now))
    end
    deadline
end

_get_earlier_deadline(first, second) =
    first === nothing ? second : second === nothing ? first : min(first, second)
