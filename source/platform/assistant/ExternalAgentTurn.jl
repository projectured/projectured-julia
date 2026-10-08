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

The live link of an assistant to its external agent:

- `connection`  — the connection that the kernel's `make_agent_connection` made;
- `session_id`  — the id of the session of the agent, empty until a turn opens
                  it, and empty again after a turn that failed;
- `tool_server` — the agent server through which the agent reaches the tools of
                  this editor, or `nothing`;
- `sent_turn_count` — how many turns of the conversation the agent has seen, so
                  a prompt holds each user turn once, and `-1` until the first
                  turn counts them;
- `is_cancelled` — whether the person stopped the turn that runs; the end of
                  the turn clears it;
- `start_lock`  — held while the agent starts and its session opens, so a turn
                  and a start from the option bar open one session.

It is no data: a save does not write it, and a duplicate of the assistant does
not share it.
"""
mutable struct ExternalAgentSession
    connection::Any
    session_id::String
    tool_server::Any
    sent_turn_count::Int
    is_cancelled::Bool
    start_lock::ReentrantLock
end

ExternalAgentSession(connection; session_id::AbstractString = "", tool_server = nothing) =
    ExternalAgentSession(connection, String(session_id), tool_server, -1, false, ReentrantLock())

"""
    is_external_agent_turn_running(assistant) -> Bool

Whether a turn of the external agent of `assistant` runs now.
"""
is_external_agent_turn_running(a::Assistant) =
    a.status === :streaming && a.backend === :acp && a.agent_session isa ExternalAgentSession

"""
    CancelAssistantTurnOperation(assistant)

Ask the external agent of `assistant` to stop its turn. The agent answers each
question that waits as cancelled, and the turn ends. A turn that is still
starting its session sends no prompt. It does nothing when no turn of an
external agent runs.
"""
struct CancelAssistantTurnOperation <: Operation
    assistant::Assistant
end

function evaluate_operation(editor, operation::CancelAssistantTurnOperation)
    a = operation.assistant
    is_external_agent_turn_running(a) || return nothing
    session = a.agent_session
    session.is_cancelled = true
    isempty(session.session_id) && return nothing
    errormonitor(@async Base.invokelatest(cancel_agent_prompt!, session.connection, session.session_id))
    nothing
end

# One turn: start the agent and its session when this is the first turn, send
# what the person said since the agent last saw the conversation, and draw each
# event as it arrives. Every write to the assistant goes through
# `run_on_editor_task!`, as the writes of a turn of a model do.
#
# A turn that fails closes the connection and forgets the session, so the next
# turn starts the agent again. The count of the turns that the agent saw stays,
# so a turn that never reached the agent is in the next prompt.
function _run_external_agent_turn!(editor, a::Assistant)
    session = _make_external_agent_session!(editor, a)
    turn = ConversationTurn(:assistant)
    state = Dict{Symbol,Any}(:current_block => nothing, :current_thinking => nothing,
                             :tool_forms => Dict{String,EvaluatorForm}(), :plan_part => nothing,
                             :permission_requests => ConversationPermissionRequest[])
    stop_reason = try
        _start_external_agent_session!(editor, a, session)
        prompt, turn_count = run_on_editor_task!(editor) do
            _make_external_agent_prompt(a.conversation, session.sent_turn_count)
        end
        if session.is_cancelled
            session.sent_turn_count = turn_count
            return nothing
        end
        run_on_editor_task!(() -> push!(a.conversation.turns, turn), editor; wait = false)
        reason = Base.invokelatest(send_agent_prompt!, session.connection, session.session_id, prompt;
            on_event = event -> run_on_editor_task!(editor; wait = false) do
                _handle_external_agent_event!(event, a, turn, state)
            end)
        session.sent_turn_count = turn_count
        reason
    catch
        _close_external_agent_session!(session)
        rethrow()
    finally
        # A cancel holds for the turn that it stopped, and the next turn starts
        # with none.
        session.is_cancelled = false
        # A question that the person did not answer before the end is cancelled.
        run_on_editor_task!(editor; wait = false) do
            foreach(request -> answer_permission_request!(request, nothing), state[:permission_requests])
        end
    end
    run_on_editor_task!(() -> _finish_turn!(a, turn, stop_reason), editor; wait = false)
    nothing
end

# The session of the assistant, made at the first turn from `agent_command` and
# `agent_session_meta`. A session that a test gives is used as it is. The count
# of the turns that the agent saw starts at the last assistant turn: the greeting
# of a pane, or the note of a duplicate, is no turn of this agent.
function _make_external_agent_session!(editor, a::Assistant)
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
    if session.sent_turn_count < 0
        session.sent_turn_count = run_on_editor_task!(editor) do
            something(findlast(turn -> turn.role === :assistant, collect(a.conversation.turns)), 0)
        end
    end
    session
end

# The agent started, with the MCP server of the editor when its package is
# loaded, and a session open that names it. The options of the new session
# reach `agent_options`.
function _start_external_agent_session!(editor, a::Assistant, session::ExternalAgentSession)
    lock(session.start_lock) do
        Base.invokelatest(start_agent_connection!, session.connection)
        if isempty(session.session_id)
            server = _start_agent_tool_server!(editor, session)
            servers = server === nothing ? Any[] : Any[Base.invokelatest(get_agent_server_access, server)]
            session.session_id = Base.invokelatest(open_agent_session!, session.connection;
                directory = pwd(), mcp_servers = servers,
                on_event = event -> _post_agent_options!(editor, a, event))
        end
    end
    session
end

_post_agent_options!(editor, a::Assistant, event) =
    event isa AgentOptionsUpdate &&
        run_on_editor_task!(() -> a.agent_options = event.options, editor; wait = false)

"""
    StartExternalAgentOperation(assistant)

Start the external agent of `assistant` and open its session, with no prompt,
so its options show before the first message. A failure shows in the
conversation, as the failure of a turn does. It does nothing for an assistant
whose backend is not `:acp`, or whose session is open.
"""
struct StartExternalAgentOperation <: Operation
    assistant::Assistant
end

function evaluate_operation(editor, operation::StartExternalAgentOperation)
    a = operation.assistant
    a.backend === :acp || return nothing
    session = a.agent_session
    session isa ExternalAgentSession && !isempty(session.session_id) && return nothing
    errormonitor(@async try
        _start_external_agent_session!(editor, a, _make_external_agent_session!(editor, a))
    catch exception
        a.agent_session isa ExternalAgentSession && _close_external_agent_session!(a.agent_session)
        message = sprint(showerror, exception)
        run_on_editor_task!(editor; wait = false) do
            push!(a.conversation.turns, ConversationTurn(:assistant, [ConversationPart("Error: " * message)]))
        end
    end)
    nothing
end

"""
    SetAgentOptionOperation(assistant, option_id, value)

Set the option `option_id` of the session of the external agent of `assistant`
to `value`, such as the model or how much it reasons. The agent answers with all
its options, and they replace `agent_options`. It does nothing while no session
is open.
"""
struct SetAgentOptionOperation <: Operation
    assistant::Assistant
    option_id::String
    value::String
end

function evaluate_operation(editor, operation::SetAgentOptionOperation)
    a = operation.assistant
    session = a.agent_session
    (session isa ExternalAgentSession && !isempty(session.session_id)) || return nothing
    errormonitor(@async try
        Base.invokelatest(set_agent_option!, session.connection, session.session_id,
                          operation.option_id, operation.value;
                          on_event = event -> _post_agent_options!(editor, a, event))
    catch exception
        @warn "The agent did not set its option." option = operation.option_id exception
    end)
    nothing
end

# The agent stopped and its session forgotten; the next turn starts both again.
# The MCP server stays, because its port and its secret still serve a new
# session.
function _close_external_agent_session!(session::ExternalAgentSession)
    session.session_id = ""
    try
        Base.invokelatest(stop_agent_connection!, session.connection)
    catch exception
        @warn "The agent did not stop." exception
    end
    nothing
end

"""
    stop_external_agent!(assistant)

Stop the external agent of `assistant` and its MCP server, and forget its
session, so the next turn starts a new agent with a new session. It does
nothing for an assistant with no agent.
"""
function stop_external_agent!(a::Assistant)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    a.agent_session = nothing
    a.agent_options = AgentOption[]
    a.agent_title = ""
    a.agent_usage = nothing
    errormonitor(@async begin
        _close_external_agent_session!(session)
        session.tool_server === nothing || Base.invokelatest(stop_agent_server!, session.tool_server)
    end)
    nothing
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

# What the person said since the agent last saw the conversation: the text of
# each user turn after the first `sent_turn_count` turns, one block for each,
# and the count of the turns now. The agent holds the history before them, so
# nothing is sent twice.
function _make_external_agent_prompt(conversation::ConversationConversation, sent_turn_count::Integer)
    turns = collect(conversation.turns)
    first_new = max(sent_turn_count, 0) + 1
    prompt = LlmContent[LlmText(_make_user_turn_text(turn))
                        for turn in turns[min(first_new, length(turns) + 1):end] if turn.role === :user]
    prompt, length(turns)
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
    elseif !(event isa Union{LlmEvent,AgentOptionsUpdate,AgentUsageUpdate,AgentSessionInfoUpdate}) &&
           !(event isa AgentToolCallUpdate && haskey(state[:tool_forms], event.id))
        state[:current_block] === nothing || _handle_agent_event!(LlmTextStop(), a, turn, state, nothing)
        state[:current_thinking] === nothing || _handle_agent_event!(LlmThinkingStop(), a, turn, state, nothing)
    end
    if event isa LlmEvent
        _handle_agent_event!(event, a, turn, state, nothing)
    elseif event isa AgentOptionsUpdate
        a.agent_options = event.options
    elseif event isa AgentUsageUpdate
        a.agent_usage = event
    elseif event isa AgentSessionInfoUpdate
        event.title === nothing || (a.agent_title = event.title)
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
    # An update can name the tool that an earlier update left unnamed.
    name = update.name !== nothing ? _remove_agent_tool_prefix(update.name) :
           update.title !== nothing && form.tool_name == "tool" ? _remove_agent_tool_prefix(update.title) :
           nothing
    is_renamed = name !== nothing && name != form.tool_name
    is_renamed && (form.tool_name = name)
    if update.input !== nothing || is_renamed
        input = something(update.input, form.input)
        form.input = input
        if form.tool_name == "execute_julia_code"
            form.source = string(get(input, "code", ""))
            form.form = _eval_form_doc(form.source)
        else
            form.source = ""
            form.form = make_evaluator_arguments_text(input)
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
