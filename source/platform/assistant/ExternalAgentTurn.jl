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
- `directory`   — the folder of the session, empty until a turn opens it;
- `is_resumed`  — whether the session is the kept session of the assistant,
                  which the agent resumed;
- `has_answered` — whether the agent answered a prompt since the session opened;
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
    steered_turn_count::Int
    directory::String
    is_resumed::Bool
    has_answered::Bool
    is_cancelled::Bool
    start_lock::ReentrantLock
end

ExternalAgentSession(connection; session_id::AbstractString = "", tool_server = nothing) =
    ExternalAgentSession(connection, String(session_id), tool_server, -1, 0, "", false, false, false,
                         ReentrantLock())

"""
    is_external_agent_turn_running(assistant) -> Bool

Whether a turn of the external agent of `assistant` runs now.
"""
is_external_agent_turn_running(a::Assistant) =
    a.status === :streaming && a.backend === :acp && a.agent_session isa ExternalAgentSession

# The external agent stops the turn that runs. A turn that is still starting its
# session sends no prompt, and an open session gets `cancel_agent_prompt!`; the
# agent answers each question that waits as cancelled, and the turn ends.
function _cancel_external_agent_turn!(a::Assistant)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
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
# A turn that fails closes the connection, so the next turn starts the agent again
# and resumes the kept session. The count of the turns that the agent saw stays,
# so a turn that never reached the agent is in the next prompt. Each answer of the
# agent makes the assistant keep the session and that count.
function _run_external_agent_turn!(editor, a::Assistant; control::AssistantTurnControl = AssistantTurnControl())
    session = _make_external_agent_session!(editor, a)
    conversation = run_on_editor_task!(() -> a.conversation, editor)
    turn = ConversationTurn(:assistant; start_time = time())
    state = Dict{Symbol,Any}(:current_block => nothing, :current_thinking => nothing,
                             :tool_forms => Dict{String,EvaluatorForm}(), :plan_part => nothing,
                             :permission_requests => ConversationPermissionRequest[],
                             :question_requests => ConversationQuestionRequest[],
                             :tools => _find_editor_tool_set(editor), :live_results => Set{String}(),
                             :turn => turn)
    # The start of an agent takes seconds, and its first turn in a process takes
    # longer, so the turn shows at once with a part that says that the agent
    # starts. When the session is open, the turn leaves the conversation and comes
    # back after the prompt, below a message that the person sent meanwhile.
    starting = isempty(session.session_id) ? ConversationPart(_get_agent_starting_text(a)) : nothing
    if starting !== nothing
        push!(turn.parts, starting)
        run_on_editor_task!(() -> push!(a.conversation.turns, turn), editor; wait = false)
    end
    is_open = false
    stop_reason = try
        _start_external_agent_session!(editor, a, session)
        is_open = true
        starting === nothing || run_on_editor_task!(editor) do
            _remove_part!(turn, starting)
            _remove_empty_turn!(a, turn)
        end
        prompt, turn_count = run_on_editor_task!(editor) do
            _make_external_agent_prompt(a.conversation, session.sent_turn_count)
        end
        # A stop that came before the session existed is in the control of the
        # turn; one that came later is in the session too.
        if session.is_cancelled || control.is_cancelled
            session.sent_turn_count = turn_count
            return nothing
        end
        run_on_editor_task!(() -> push!(a.conversation.turns, turn), editor; wait = false)
        reason = Base.invokelatest(send_agent_prompt!, session.connection, session.session_id, prompt;
            on_event = event -> run_on_editor_task!(editor; wait = false) do
                _split_steered_turn!(a, state, control)
                _handle_external_agent_event!(event, a, state[:turn], state)
            end)
        session.sent_turn_count = max(turn_count, session.steered_turn_count)
        session.has_answered = true
        run_on_editor_task!(() -> _keep_agent_session!(a, conversation, session), editor; wait = false)
        reason
    catch exception
        # A resumed session whose first prompt fails is no session that the
        # agent has, as for a session in which the agent never answered. A
        # sign-in that the prompt needs says nothing about the session.
        session.is_resumed && !session.has_answered && !(exception isa AgentSignInException) &&
            run_on_editor_task!(() -> _drop_agent_session_folder!(a, conversation), editor; wait = false)
        # A start that failed leaves no turn of its own.
        (starting === nothing || is_open) || run_on_editor_task!(editor) do
            _remove_part!(turn, starting)
            _remove_empty_turn!(a, turn)
        end
        _close_external_agent_session!(session)
        rethrow()
    finally
        # A cancel holds for the turn that it stopped, and the next turn starts
        # with none.
        session.is_cancelled = false
        # A question that the person did not answer before the end is cancelled.
        run_on_editor_task!(editor; wait = false) do
            foreach(request -> answer_permission_request!(request, nothing), state[:permission_requests])
            foreach(request -> answer_question_request!(request, nothing), state[:question_requests])
        end
    end
    run_on_editor_task!(() -> _finish_turn!(a, state[:turn], stop_reason), editor; wait = false)
    nothing
end

# What the part of a turn says while its agent starts: the name of the built-in
# agent, or the agent of a command of the person.
_get_agent_starting_text(a::Assistant) =
    isempty(a.agent_command) ? "Starting Claude Code…" : "Starting the agent…"

function _remove_part!(turn::ConversationTurn, part::ConversationPart)
    index = findfirst(candidate -> candidate === part, collect(turn.parts))
    index === nothing || deleteat!(turn.parts, index)
    nothing
end

# A turn that holds no part leaves the conversation.
function _remove_empty_turn!(a::Assistant, turn::ConversationTurn)
    isempty(turn.parts) || return nothing
    index = findfirst(candidate -> candidate === turn, collect(a.conversation.turns))
    index === nothing || deleteat!(a.conversation.turns, index)
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
        # An empty command starts the built-in agent of `ProjecturedACP`.
        command = Base.shell_split(a.agent_command)
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
# loaded, and a session open that names it. The session that the assistant kept
# resumes in its folder while the folder exists, so the agent has the history
# that the transcript shows. The options of the session reach `agent_options`.
function _start_external_agent_session!(editor, a::Assistant, session::ExternalAgentSession)
    lock(session.start_lock) do
        Base.invokelatest(start_agent_connection!, session.connection)
        if isempty(session.session_id)
            server = _start_agent_tool_server!(editor, session)
            servers = server === nothing ? Any[] : Any[Base.invokelatest(get_agent_server_access, server)]
            conversation, kept_id, kept_directory, kept_count = run_on_editor_task!(editor) do
                a.conversation, a.agent_session_id, a.agent_session_directory, a.agent_session_turn_count
            end
            is_resumable = !isempty(kept_id) && isdir(kept_directory)
            session.directory = is_resumable ? kept_directory : pwd()
            session.is_resumed = false
            session.has_answered = false
            session_id = Base.invokelatest(open_agent_session!, session.connection;
                directory = session.directory, mcp_servers = servers, instructions = DEFAULT_AGENT_INSTRUCTIONS,
                session_id = is_resumable ? kept_id : "",
                on_event = event -> _post_agent_options!(editor, a, event))
            session.session_id = session_id
            session.is_resumed = is_resumable && session_id == kept_id
            if session.is_resumed
                session.sent_turn_count = kept_count
            elseif !isempty(kept_id)
                run_on_editor_task!(() -> _forget_agent_session!(a, conversation), editor; wait = false)
            end
        end
    end
    session
end

# The assistant keeps the session in which the agent answered, and how many turns
# that session saw. A write for a conversation that a reset replaced does nothing.
function _keep_agent_session!(a::Assistant, conversation::ConversationConversation,
                              session::ExternalAgentSession)
    a.conversation === conversation || return nothing
    a.agent_session_id = session.session_id
    a.agent_session_directory = session.directory
    a.agent_session_turn_count = session.sent_turn_count
    nothing
end

# A new session in place of the kept one has none of its history: the assistant
# forgets the kept session and its title, and a note says so.
function _forget_agent_session!(a::Assistant, conversation::ConversationConversation)
    a.conversation === conversation || return nothing
    a.agent_session_id = ""
    a.agent_session_directory = ""
    a.agent_session_turn_count = 0
    a.agent_title = ""
    push!(a.conversation.turns, ConversationTurn(:assistant, [ConversationPart(NEW_SESSION_AGENT_NOTE)]))
    nothing
end

# A kept session without its folder does not resume, so the next turn opens a new
# session, and the note of a new session says that it has none of the history.
function _drop_agent_session_folder!(a::Assistant, conversation::ConversationConversation)
    a.conversation === conversation || return nothing
    a.agent_session_directory = ""
    nothing
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
        if exception isa AgentSignInException
            run_on_editor_task!(() -> _add_agent_sign_in_request!(a, exception), editor; wait = false)
        else
            message = sprint(showerror, exception)
            run_on_editor_task!(editor; wait = false) do
                push!(a.conversation.turns, _make_instant_turn(:assistant, [ConversationPart("Error: " * message)]))
            end
        end
    end)
    nothing
end

# ── A message while the agent works ──────────────────────────────────────────

# Send the user turn `turn` into the turn that runs, when the agent takes a prompt
# there. When it took it, the turn counts the message as read, the session as
# seen, and the answer goes on in a new turn below it; else the message waits for
# the next turn. The request to the agent runs on a task of its own.
function _steer_external_agent!(editor, a::Assistant, turn::ConversationTurn)
    session = a.agent_session
    control = a.turn_control
    (session isa ExternalAgentSession && !isempty(session.session_id) && control isa AssistantTurnControl) ||
        return nothing
    index = something(findfirst(candidate -> candidate === turn, collect(a.conversation.turns)), 0)
    prompt = _make_user_turn_content(turn)
    errormonitor(@async begin
        is_taken = try
            Base.invokelatest(has_agent_steering, session.connection) &&
                Base.invokelatest(steer_agent_prompt!, session.connection, session.session_id, prompt)
        catch exception
            is_fault_exception(exception) || rethrow()
            false
        end
        is_taken && run_on_editor_task!(editor; wait = false) do
            session.steered_turn_count = max(session.steered_turn_count, index)
            control.seen_turn_count = max(control.seen_turn_count, index)
            control.is_split_asked = true
        end
    end)
    nothing
end

# After a message that the agent took into the turn, the answer goes on in a new
# turn below the message. The open blocks close in the turn above it, which ends;
# an empty turn above goes, and the counts of the turns after it move down by one.
function _split_steered_turn!(a::Assistant, state, control::AssistantTurnControl)
    control.is_split_asked || return nothing
    control.is_split_asked = false
    above = state[:turn]
    state[:current_block] === nothing || _handle_agent_event!(LlmTextStop(), a, above, state, nothing)
    state[:current_thinking] === nothing || _handle_agent_event!(LlmThinkingStop(), a, above, state, nothing)
    index = findfirst(turn -> turn === above, collect(a.conversation.turns))
    if isempty(above.parts) && index !== nothing
        deleteat!(a.conversation.turns, index)
        control.seen_turn_count -= control.seen_turn_count >= index
        session = a.agent_session
        session isa ExternalAgentSession && (session.steered_turn_count -= session.steered_turn_count >= index)
    else
        above.stop_reason = :end_turn
        above.finish_time = time()
    end
    below = ConversationTurn(:assistant; start_time = time())
    push!(a.conversation.turns, below)
    state[:turn] = below
    nothing
end

# ── The sign-in of the agent ─────────────────────────────────────────────────

# The part that a sign-in needs, at the end of the conversation: the message and
# the methods of the agent, a start that runs a method, and a retry that starts
# the agent again.
function _add_agent_sign_in_request!(a::Assistant, exception::AgentSignInException)
    request = ConversationSignInRequest(exception.message, exception.methods)
    request.start = (editor, method_id) -> _start_agent_sign_in!(editor, a, request, method_id)
    request.retry = editor -> evaluate_operation(editor, StartExternalAgentOperation(a))
    push!(a.conversation.turns, _make_instant_turn(:assistant, [ConversationPart(request)]))
    nothing
end

# Run the sign-in of the method `method_id` in a terminal. When it ends with the
# status 0, the agent starts again; the line of the request says how it went. A
# sign-in that a person stopped did not sign in, whatever its status: a program
# such as `claude auth login` ends with 0 at Ctrl+C.
function _start_agent_sign_in!(editor, a::Assistant, request::ConversationSignInRequest,
                               method_id::AbstractString)
    index = findfirst(method -> method.id == method_id, request.methods)
    index === nothing && return nothing
    terminal = TerminalDocument(request.methods[index].command; on_exit = (editor, status) -> begin
        request.is_signing_in = false
        is_stopped = is_terminal_stopped(terminal)
        request.state = is_stopped ? "The sign-in was stopped." :
                        status == 0 ? "Signed in." : "The sign-in ended with the status $(status)."
        status == 0 && !is_stopped && evaluate_operation(editor, StartExternalAgentOperation(a))
    end)
    request.terminal = terminal
    request.is_signing_in = true
    request.state = "The sign-in runs below. Click in it to type, such as a code to paste."
    start_terminal!(editor, terminal)
    terminal.status === :failed && (request.is_signing_in = false; request.state = "The sign-in could not start.")
    nothing
end

# The sign-ins that run in the conversation of `a` end with it.
function _release_agent_sign_ins!(editor, a::Assistant)
    for turn in collect(a.conversation.turns), part in collect(turn.parts)
        content = part.content
        content isa ConversationSignInRequest && content.terminal isa TerminalDocument &&
            release_document!(editor, content.terminal)
    end
    nothing
end

# Whether the agent of `a` signs out when asked.
_has_agent_sign_out(a::Assistant) =
    (session = a.agent_session; session isa ExternalAgentSession &&
                                Base.invokelatest(has_agent_sign_out, session.connection))

"""
    SignOutAgentOperation(assistant)

Sign the external agent of `assistant` out. The agent forgets the sign-in of the
person, and its next prompt gives a sign-in request. A note in the conversation
says how it went. The request to the agent runs on a task of its own, so the
editor does not wait for it.
"""
struct SignOutAgentOperation <: Operation
    assistant::Assistant
end

function evaluate_operation(editor, operation::SignOutAgentOperation)
    a = operation.assistant
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    errormonitor(@async begin
        note = try
            Base.invokelatest(sign_out_agent!, session.connection) ?
                "Signed out. The next message needs a sign-in." : "The agent can not sign out."
        catch exception
            "The sign-out failed: " * sprint(showerror, exception)
        end
        run_on_editor_task!(editor; wait = false) do
            push!(a.conversation.turns, _make_instant_turn(:assistant, [ConversationPart(note)]))
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

# The agent stopped, and the session object holds no open session; the next turn
# starts the agent again and resumes the kept session. The MCP server stays,
# because its port and its secret still serve the next session.
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

Stop the external agent of `assistant` and its MCP server. The assistant keeps
the id, the folder and the title of the session, so the next turn starts the
agent again and resumes that session. It does nothing for an assistant with no
agent.
"""
function stop_external_agent!(a::Assistant)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    a.agent_session = nothing
    a.agent_options = AgentOption[]
    a.agent_usage = nothing
    a.agent_commands = AgentCommand[]
    errormonitor(@async begin
        _close_external_agent_session!(session)
        session.tool_server === nothing || Base.invokelatest(stop_agent_server!, session.tool_server)
    end)
    nothing
end

# An assistant whose tab closes stops its external agent and its sign-ins, so no
# agent, no MCP server and no program of a sign-in outlive the tab. An undo of the close brings the assistant back, and
# its next turn starts the agent again and resumes the session.
release_document!(editor, a::Assistant) = (_release_agent_sign_ins!(editor, a); stop_external_agent!(a))

# The MCP server through which the agent reaches the tools of this editor: on a
# free port, with a secret that only this agent gets. With no MCP package loaded
# the agent has its own tools only.
function _start_agent_tool_server!(editor, session::ExternalAgentSession)
    session.tool_server === nothing || return session.tool_server
    :mcp in Base.invokelatest(get_agent_server_names) || return nothing
    server = Base.invokelatest(make_agent_server, :mcp, editor; port = 0, secret = true,
                               instructions = DEFAULT_AGENT_INSTRUCTIONS)
    Base.invokelatest(start_agent_server!, server)
    session.tool_server = server
end

# What the person said since the agent last saw the conversation: the content of
# each user turn after the first `sent_turn_count` turns, a block of text for
# each and its pictures, and the count of the turns now. The agent holds the
# history before them, so nothing is sent twice.
function _make_external_agent_prompt(conversation::ConversationConversation, sent_turn_count::Integer)
    turns = collect(conversation.turns)
    first_new = max(sent_turn_count, 0) + 1
    prompt = LlmContent[]
    for turn in turns[min(first_new, length(turns) + 1):end]
        turn.role === :user && append!(prompt, _make_user_turn_content(turn))
    end
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
    elseif !(event isa Union{LlmEvent,AgentOptionsUpdate,AgentUsageUpdate,AgentSessionInfoUpdate,
                             AgentCommandsUpdate}) &&
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
    elseif event isa AgentCommandsUpdate
        a.agent_commands = event.commands
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
    elseif event isa AgentQuestionRequest
        request = ConversationQuestionRequest(event.message, event.fields; reply = event.reply)
        push!(state[:question_requests], request)
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
                             result = _make_agent_tool_result(state, update.id, name, output,
                                                              update.status === :failed;
                                                              mime_type = update.output_mime_type,
                                                              uri = update.output_uri),
                             output,
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
        # A live result stays when a later update repeats the output.
        update.id in state[:live_results] ||
            (form.result = _make_agent_tool_result(state, update.id, form.tool_name, update.output,
                                                   update.status === :failed || form.is_error;
                                                   mime_type = update.output_mime_type,
                                                   uri = update.output_uri))
    end
    update.status === :failed && (form.is_error = true)
    nothing
end

# The result of a tool. The document that an evaluation of this editor returned,
# which the MCP server kept under the id of the call, is the live result, as in a
# turn of a model. A result that the agent gives with a media type or a uri, as
# the text of a file that a tool read, is a document of the format that they
# name. A tool of this editor, which the agent reaches through the MCP server of
# the editor, otherwise gets the document that a turn of a model makes of its
# text, from the media type that the tool declares: a Markdown page for a
# documentation tool. Another tool, and an error, keep their text.
function _make_agent_tool_result(state, id::AbstractString, name::AbstractString, output::AbstractString,
                                 is_error::Bool; mime_type = nothing, uri = nothing)
    tools = state[:tools]
    if tools !== nothing && !is_error && name == "execute_julia_code"
        value = take_tool_call_value!(tools, id)
        if value !== nothing
            push!(state[:live_results], String(id))
            return value
        end
    end
    if !is_error
        document = _make_resource_document(output, mime_type, uri)
        document === nothing || return document
    end
    _make_tool_result_document(tools === nothing ? nothing : find_tool(tools, name), output, is_error)
end

# The document of a text that the agent gave with its media type or its uri: a
# document of the natural format that the media type names, or else the
# extension of the uri. `nothing` when no parser of the session reads that
# format, or the text does not parse, so the text stays text.
function _make_resource_document(text::AbstractString, mime_type, uri)
    format = mime_type === nothing ? nothing : _find_result_format(mime_type)
    format === nothing && mime_type === nothing && uri !== nothing && (format = _find_uri_format(uri))
    (format !== nothing && has_natural_parser(format)) || return nothing
    try
        parse_natural_text(format, text)
    catch exception
        is_fault_exception(exception) || rethrow()
        nothing
    end
end

# The natural format that the extension of a uri names, or `nothing`.
function _find_uri_format(uri::AbstractString)
    extension = lowercase(lstrip(last(splitext(uri)), '.'))
    isempty(extension) ? nothing : Symbol(extension)
end

# The tool set of the editor, or `nothing` for an editor that has none.
_find_editor_tool_set(editor) = hasproperty(editor, :tools) ? editor.tools : nothing

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
