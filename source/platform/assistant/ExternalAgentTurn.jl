# Fragment of `AssistantModule` — a turn of an external agent: an agent that
# runs its own loop in another process, such as Claude through ACP.
#
# The agent owns its model, its tools and its history. The assistant sends it
# what the person said since the last answer, and draws what the agent reports:
# its text and its reasoning as parts, each tool call as an `EvaluatorForm` that
# its updates fill, its plan as one part that each update replaces, and each
# question for the person as a `ConversationPermissionRequest`. The agent
# reaches the tools of this editor through the MCP server that the assistant
# starts for it, with a secret, so each edit of the agent is an operation of the
# editor.

"""
    ExternalAgentSession(connection; session_id = "", tool_server = nothing)

The live link of an assistant to its external agent: the connection that the
kernel's `make_agent_connection` made, the id of the session of the agent, empty
until the first turn opens it, and the agent server through which the agent
reaches the tools of this editor, or `nothing`. It is no data: a save does not
write it, and a duplicate of the assistant does not share it.
"""
mutable struct ExternalAgentSession
    connection::Any
    session_id::String
    tool_server::Any
end

ExternalAgentSession(connection; session_id::AbstractString = "", tool_server = nothing) =
    ExternalAgentSession(connection, String(session_id), tool_server)

"""
    is_external_agent_turn_running(assistant) -> Bool

Whether a turn of the external agent of `assistant` runs now.
"""
is_external_agent_turn_running(a::Assistant) =
    a.status === :streaming && a.backend === :acp && a.agent_session isa ExternalAgentSession

"""
    CancelAssistantTurnOperation(assistant)

Ask the external agent of `assistant` to stop its turn. The agent answers each
question that waits as cancelled, and the turn ends. It does nothing when no
turn of an external agent runs.
"""
struct CancelAssistantTurnOperation <: Operation
    assistant::Assistant
end

function evaluate_operation(editor, op::CancelAssistantTurnOperation)
    a = op.assistant
    is_external_agent_turn_running(a) || return nothing
    session = a.agent_session
    isempty(session.session_id) && return nothing
    errormonitor(@async Base.invokelatest(cancel_agent_prompt!, session.connection, session.session_id))
    nothing
end

# One turn: start the agent and its session when this is the first turn, send
# what the person said since the last answer, and draw each event as it arrives.
# Every write to the assistant goes through `run_on_editor_task!`, as the writes
# of a turn of a model do.
function _run_external_agent_turn!(editor, a::Assistant)
    session = _start_external_agent_session!(editor, a)
    prompt = run_on_editor_task!(() -> _make_external_agent_prompt(a.conversation), editor)
    turn = ConversationTurn(:assistant)
    run_on_editor_task!(() -> push!(a.conversation.turns, turn), editor; wait = false)
    state = Dict{Symbol,Any}(:current_block => nothing, :current_thinking => nothing,
                             :tool_forms => Dict{String,EvaluatorForm}(), :plan_part => nothing,
                             :permission_requests => ConversationPermissionRequest[])
    stop_reason = try
        Base.invokelatest(send_agent_prompt!, session.connection, session.session_id, prompt;
            on_event = event -> run_on_editor_task!(editor; wait = false) do
                _handle_external_agent_event!(event, a, turn, state)
            end)
    finally
        # A question that the person did not answer before the end is cancelled.
        run_on_editor_task!(editor; wait = false) do
            foreach(request -> answer_permission_request!(request, nothing), state[:permission_requests])
        end
    end
    run_on_editor_task!(() -> _finish_turn!(a, turn, stop_reason), editor; wait = false)
    nothing
end

# The session of the assistant, started. The first turn makes the connection
# from `agent_command` and `agent_session_meta`, starts the MCP server of the editor when its package is
# loaded, and opens a session that names it. A session that a test gives is
# used as it is.
function _start_external_agent_session!(editor, a::Assistant)
    session = a.agent_session
    if session === nothing
        :acp in Base.invokelatest(get_agent_connection_names) ||
            error("The backend :acp needs the package ProjecturedACP. Load it with `using ProjecturedACP`.")
        command = Base.shell_split(a.agent_command)
        isempty(command) && error("The assistant has no agent command.")
        connection = Base.invokelatest(make_agent_connection, :acp; command, directory = pwd(),
                                       session_meta = a.agent_session_meta)
        session = ExternalAgentSession(connection)
        run_on_editor_task!(() -> a.agent_session = session, editor)
    end
    Base.invokelatest(start_agent_connection!, session.connection)
    if isempty(session.session_id)
        server = _start_agent_tool_server!(editor, session)
        servers = server === nothing ? Any[] : Any[Base.invokelatest(get_agent_server_access, server)]
        session.session_id = Base.invokelatest(open_agent_session!, session.connection;
                                               directory = pwd(), mcp_servers = servers)
    end
    session
end

# The MCP server through which the agent reaches the tools of this editor: on a
# free port, with a secret that only this agent gets. With no MCP package loaded
# the agent has its own tools only.
function _start_agent_tool_server!(editor, session::ExternalAgentSession)
    session.tool_server === nothing || return session.tool_server
    :mcp in Base.invokelatest(get_agent_server_names) || return nothing
    server = Base.invokelatest(make_agent_server, :mcp, editor; port = 0, secret = true)
    Base.invokelatest(start_agent_server!, server)
    session.tool_server = server
end

# What the person said since the last answer: the text of each user turn after
# the last assistant turn, one block for each. The agent holds the history
# before it, so nothing earlier is sent again.
function _make_external_agent_prompt(conversation::ConversationConversation)
    turns = collect(conversation.turns)
    last_answer = findlast(turn -> turn.role === :assistant, turns)
    first_new = last_answer === nothing ? 1 : last_answer + 1
    LlmContent[LlmText(_make_user_turn_text(turn)) for turn in turns[first_new:end] if turn.role === :user]
end

# One event of the agent, applied to the turn on the editor task. The stop of a
# text block reads the text part again in place of the last part, so a part of
# another kind closes the open blocks before it comes, and text after it opens a
# new block.
function _handle_external_agent_event!(event, a::Assistant, turn::ConversationTurn, state)
    if event isa LlmTextDelta && state[:current_block] === nothing
        _handle_agent_event!(LlmTextStart(), a, turn, state, nothing)
    elseif event isa LlmThinkingDelta && state[:current_thinking] === nothing
        _handle_agent_event!(LlmThinkingStart(), a, turn, state, nothing)
    elseif !(event isa LlmEvent) && !(event isa AgentToolCallUpdate && haskey(state[:tool_forms], event.id))
        state[:current_block] === nothing || _handle_agent_event!(LlmTextStop(), a, turn, state, nothing)
        state[:current_thinking] === nothing || _handle_agent_event!(LlmThinkingStop(), a, turn, state, nothing)
    end
    if event isa LlmEvent
        _handle_agent_event!(event, a, turn, state, nothing)
    elseif event isa AgentToolCallUpdate
        _apply_tool_call_update!(turn, state, event)
    elseif event isa AgentPlanUpdate
        _apply_plan_update!(turn, state, event)
    elseif event isa AgentPermissionRequest
        title = _remove_agent_tool_prefix(something(event.tool_call.title, event.tool_call.name, "a tool"))
        request = ConversationPermissionRequest("The agent asks to run: " * title, event.options;
                                                reply = event.reply)
        push!(state[:permission_requests], request)
        push!(turn.parts, Cell(ConversationPart(request)))
    end
    nothing
end

# A tool call becomes a form at its first event, and each update fills it: the
# input, the text that the tool answered, and a failure.
function _apply_tool_call_update!(turn::ConversationTurn, state, update::AgentToolCallUpdate)
    forms = state[:tool_forms]
    form = get(forms, update.id, nothing)
    if form === nothing
        name = _get_agent_tool_name(update)
        input = something(update.input, Dict{String,Any}())
        output = something(update.output, "")
        form = EvaluatorForm(_eval_form_doc(LlmToolUse(update.id, name, input));
                             source = name == "execute_julia_code" ? string(get(input, "code", "")) : "",
                             result = make_evaluator_result_text(output), output,
                             is_error = update.status === :failed,
                             tool_use_id = update.id, tool_name = name, input)
        forms[update.id] = form
        push!(turn.parts, Cell(ConversationPart(form; collapsed = _collapse_tool_default(name))))
        return nothing
    end
    if update.input !== nothing
        form.input = update.input
        if form.tool_name == "execute_julia_code"
            form.source = string(get(update.input, "code", ""))
            form.form = _eval_form_doc(form.source)
        else
            form.form = make_evaluator_arguments_text(update.input)
        end
    end
    if update.output !== nothing
        form.output = update.output
        form.result = make_evaluator_result_text(update.output)
    end
    update.status === :failed && (form.is_error = true)
    nothing
end

# The name of a tool for a person: the name that the agent gives, or its title.
# A tool of this editor's MCP server comes back with the prefix the agent gives
# a server's tools, `mcp__projectured__`, and the form and the question name it
# as the tool it is.
_get_agent_tool_name(update::AgentToolCallUpdate) =
    _remove_agent_tool_prefix(something(update.name, update.title, "tool"))

_remove_agent_tool_prefix(name::AbstractString) =
    startswith(name, AGENT_TOOL_PREFIX) ? String(name[(length(AGENT_TOOL_PREFIX) + 1):end]) : String(name)

const AGENT_TOOL_PREFIX = "mcp__projectured__"

# The plan of the agent is one part of the turn, a list of its steps, which
# each update replaces.
function _apply_plan_update!(turn::ConversationTurn, state, update::AgentPlanUpdate)
    lines = String["**Plan**", ""]
    for entry in update.entries
        mark = entry.status === :completed ? "[x]" : "[ ]"
        suffix = entry.status === :in_progress ? " *(in progress)*" : ""
        push!(lines, "- " * mark * " " * entry.content * suffix)
    end
    content = _prose_part(join(lines, '\n')).content
    part = state[:plan_part]
    if part === nothing
        state[:plan_part] = ConversationPart(content)
        push!(turn.parts, Cell(state[:plan_part]))
    else
        part.content = content
    end
    nothing
end
