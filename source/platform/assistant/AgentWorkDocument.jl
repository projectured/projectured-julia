# Fragment of `AssistantModule` — the work of an external agent as documents: the
# work of one session or of one subagent, a notice of the agent, and a background
# task of the agent as a task of the task slice; and what a roster reads of them.

"""
    AgentNotice(severity, title, description, time)

A note of an external agent for a person, which needs no answer, such as a
request to its model that it tries again, or a compaction of its context.
`severity` is `:info`, `:warning` or `:error`, `title` and `description` say
it, and `time` is when it came, in seconds of `time()`.
"""
@document struct AgentNotice <: Document
    severity::Symbol
    title::String
    description::String
    time::Float64
end

get_document_title(notice::AgentNotice) = notice.title

"""
    AgentWork(id)

The work of one session of an external agent, or of one of its subagents. The
events of the agent fill it ([`apply_agent_event!`](@ref)).

# Fields
- `id` — the id of the session, or the id of the subagent.
- `title`, `description` — what a subagent is for, in words for a person.
- `state` — `:running`, `:idle` (it waits for work), `:requires_action` (it
  waits for a person) or `:unknown`.
- `stop_reason` — why its last work ended, such as `:end_turn`, or `nothing`.
- `token_count`, `tool_call_count`, `duration` — how many tokens and tool calls
  its work used, and how many seconds it worked; `nothing` until the agent says.
- `start_time` — when the window saw it start to run, in seconds of `time()`, or
  `nothing` before.
- `last_tool` — the name of the last tool that it called; empty before.
- `summary` — what it did, in a few words; empty before.
- `can_cancel` — whether its work can be cancelled.
- `conversation` — the transcript of a subagent: its prompt, its text, its
  reasoning, its tool calls and its plan. The transcript of the session of an
  assistant is the conversation of the assistant, so there it stays empty, and
  so do the title, the state and the usage, which the assistant holds.
- `plans` — its plans, each a `WorkPlan`, in the order in which they came.
- `background_tasks` — its background tasks, each a `TaskDocument` of an
  [`AgentBackgroundTask`](@ref).
- `subagents` — its subagents, each an `AgentWork`.
- `notices` — its notices, each an [`AgentNotice`](@ref), the oldest first.
- `processes` — the `SystemProcessTree` of the process that does the work of
  the session, or `nothing` while the agent names none.

It is the live state of a session, as the session itself is: a file does not
keep it, and a duplicate of an assistant and a new session start with an empty
one.
"""
@document struct AgentWork <: Document
    id::String
    title::String
    description::String
    state::Symbol
    stop_reason::Union{Nothing,Symbol}
    token_count::Union{Nothing,Int}
    tool_call_count::Union{Nothing,Int}
    duration::Union{Nothing,Float64}
    start_time::Union{Nothing,Float64}
    last_tool::String
    summary::String
    can_cancel::Bool
    conversation::ConversationConversation
    plans::CellVector
    background_tasks::CellVector
    subagents::CellVector
    notices::CellVector
    processes::Union{Nothing,SystemProcessTree}
end

AgentWork(id::AbstractString) =
    AgentWork(String(id), "", "", :unknown, nothing, nothing, nothing, nothing, nothing,
              "", "", false, ConversationConversation(),
              (CellVector(Any[]) for _ in 1:4)..., nothing)

# The title is one line, as a tab, a node and the bar of a navigator show it.
get_document_title(work::AgentWork) =
    isempty(work.title) ? "Agent" : _format_one_line(work.title)

# The work of a session is a record of the agent: a duplicate of it would be a
# copy of a live state, and a paste does not replace it.
has_document_duplicate(::AgentWork) = false
accepts_pasted_document(::AgentWork) = false

# ── The nodes of a tree ──────────────────────────────────────────────────────

# The work of an agent is a node whose children are its subagents, then its
# background tasks.
get_tree_children_steps(::AgentWork) =
    ((FieldReferenceStep("subagents"),), (FieldReferenceStep("background_tasks"),))

# The node of a subagent: its title. Its decoration says its state as its icon,
# and as its detail its state with the time when it started while it runs, the
# tool that it calls then, how long it worked once it ended, and the tokens that
# it used. It reads no clock.
format_tree_node_label(work::AgentWork) = get_document_title(work)

function get_document_decoration(work::AgentWork)
    words = String[_describe_agent_work_time(work)]
    work.state === :running && !isempty(work.last_tool) && push!(words, work.last_tool)
    tokens = work.token_count
    tokens === nothing || push!(words, _format_token_count(tokens) * " tokens")
    condition = work.state === :running ? DocumentCondition(:running) :
                work.state === :requires_action ? DocumentCondition(:waiting; count = 1) :
                work.state === :idle ? DocumentCondition(:done) : nothing
    icon = work.state === :running ? :loader : work.state === :idle ? :circle_check :
           work.state === :requires_action ? :warning : :bot
    DocumentDecoration(; icon, conditions = condition === nothing ? DocumentCondition[] : [condition],
                       detail = join(words, " · "), work_item = true)
end

# The state of the work, with the time when it started while it runs, or with how
# long it worked once it ended and the agent says.
function _describe_agent_work_time(work::AgentWork)
    state = _describe_agent_work_state(work.state)
    started = work.start_time
    work.state === :running && started !== nothing &&
        return state * " since " * Libc.strftime("%H:%M:%S", started)
    work.state === :running || work.duration === nothing ? state :
        state * " · " * _format_assistant_duration(work.duration)
end

# A text in one line: each line break, with the blanks around it, is a space.
_format_one_line(text::AbstractString) = replace(text, r"\s*\R\s*" => " ")

# The state of the work of an agent in words for a person: "running", "idle",
# "waits for you" or "unknown".
_describe_agent_work_state(state::Symbol) =
    state === :requires_action ? "waits for you" : replace(String(state), "_" => " ")

# ── A background task ────────────────────────────────────────────────────────

"""
    AgentBackgroundTask(session_id, task_id, kind, title, tool_call_id, subagent_id,
                        output_uri, summary, can_stop)

A background task of an external agent as a task of the task slice: work that
the agent started and that runs after the call that started it, such as a
command in the background. The agent runs it, and this editor only watches it,
so its `TaskExecution` has no process: the events of the agent write its status,
its times and its result.

`session_id` and `task_id` name the session and the task. `kind`, `title`,
`tool_call_id`, `subagent_id`, `output_uri` and `summary` are what the agent
said of it, each empty when the agent said nothing, and `can_stop` whether the
agent can stop it now. It holds no session, no connection and no editor: Stop
finds the session of `session_id` when it is pressed.
"""
struct AgentBackgroundTask <: AbstractTask
    session_id::String
    task_id::String
    kind::Symbol
    title::String
    tool_call_id::String
    subagent_id::String
    output_uri::String
    summary::String
    can_stop::Bool
end

"""
    AgentBackgroundTaskResult

What a background task of an agent ended with: `DONE` when it completed, `ERROR`
when it failed and `CANCEL` when it was stopped, of `RUN_RESULT_CODES`, with the
seconds that it ran. A stop ends a task on purpose, so a task that ends as
`CANCEL` expects `CANCEL`; one that fails expects `DONE`.
"""
struct AgentBackgroundTaskResult <: TaskResult
    task::AgentBackgroundTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

get_result_codes(::AgentBackgroundTask) = RUN_RESULT_CODES
format_task_parameters(task::AgentBackgroundTask) =
    isempty(task.title) ? task.task_id : _format_one_line(task.title)
get_task_columns(::AgentBackgroundTask) = ["kind" => 2]
format_task_column(task::AgentBackgroundTask, column::AbstractString) =
    column == "kind" ? String(task.kind) : ""

function format_task_details(task::AgentBackgroundTask, result)
    lines = String["kind: " * String(task.kind)]
    isempty(task.tool_call_id) || push!(lines, "tool call: " * task.tool_call_id)
    isempty(task.subagent_id) || push!(lines, "subagent: " * task.subagent_id)
    isempty(task.output_uri) ||
        push!(lines, "output: " * chopprefix(task.output_uri, "file://"))
    isempty(task.summary) || push!(lines, "summary: " * _format_one_line(task.summary))
    lines
end

# Stop while the agent can stop the task, and a link that opens the file of its
# output once the agent names one.
function get_task_actions(task::AgentBackgroundTask)
    actions = Pair{String,Function}[]
    task.can_stop && push!(actions, "Stop" => _stop_agent_background_task)
    isempty(task.output_uri) ||
        push!(actions, "Open the output" => _open_agent_background_task_output)
    actions
end

_open_agent_background_task_output(editor, task::AgentBackgroundTask) =
    evaluate_operation(editor, OpenFileOperation(chopprefix(task.output_uri, "file://")))

# A press of Stop: the assistant of the window whose session runs the task asks
# its agent to stop it, as background work. The answer of the agent says whether
# it stopped; a later update of the task reports the end, and a refusal is a
# notice of the work of the assistant, which the work posts to the editor. With
# no loop, the work runs on the thread of the press, as a turn does.
function _stop_agent_background_task(editor, task::AgentBackgroundTask)
    a = _find_session_assistant(editor, task.session_id)
    a === nothing && return nothing
    session = a.agent_session
    stop = () -> begin
        is_stopped = try
            Base.invokelatest(stop_agent_background_task!, session.connection,
                              task.session_id, task.task_id)
        catch exception
            is_fault_exception(exception) || rethrow()
            @warn("The agent did not stop its background task.", task = task.task_id,
                  exception)
            false
        end
        title = "The agent did not stop " * format_task_parameters(task) * "."
        is_stopped || run_on_editor_task!(editor; wait = false) do
            _add_agent_notice!(a.agent_work, :warning, title, "")
        end
    end
    start_background_work(stop; description = "the stop of a background task", editor,
                          parent = nothing, is_sticky = !is_editor_loop_running(editor))
    nothing
end

# The assistant whose open session has the id `session_id`, among the assistants
# that the list of the assistants of `editor` shows, or `nothing`.
function _find_session_assistant(editor, session_id::AbstractString)
    for a in collect(get_session_assistant_list(; editor).assistants)
        session = a.agent_session
        session isa ExternalAgentSession && session.session_id == session_id && return a
    end
    nothing
end

_add_agent_notice!(work::AgentWork, severity::Symbol, title::AbstractString,
                   description::AbstractString) =
    push!(work.notices, AgentNotice(severity, String(title), String(description), time()))

# ── What a roster reads ──────────────────────────────────────────────────────

# How many subagents of the work run, at every depth.
function _count_running_subagents(work::AgentWork)
    count = 0
    for child in collect(work.subagents)
        count += Int(child.state === :running) + _count_running_subagents(child)
    end
    count
end

# How many background tasks of the work and of its subagents run.
function _count_running_background_tasks(work::AgentWork)
    running = count(document -> get_task_document_status(document) === :running,
                    collect(work.background_tasks))
    for child in collect(work.subagents)
        running += _count_running_background_tasks(child)
    end
    running
end

# The progress of the first plan of the work that has steps, as its completed
# steps over all its steps, such as "3/7"; empty without such a plan.
function _format_agent_plan_progress(work::AgentWork)
    for plan in collect(work.plans)
        isempty(plan.steps) && continue
        progress = compute_work_plan_progress(plan)
        return string(progress.completed, "/", progress.total)
    end
    ""
end

# The facet of the work in a roster. Its state and its last tool are its fields.
get_item_facets(::Type{AgentWork}) =
    ["tokens" => "how many tokens the work used, or 0 before the agent says"]
compute_item_facet(work::AgentWork, ::Val{:tokens}) = something(work.token_count, 0)
