# Fragment of `AcpModule` — `AcpConnection`, the client side of one agent: its
# start and the agreement on the protocol, its sessions, its prompts, and the
# answers to what the agent asks. A connection of `AgentClientProtocol` carries
# the messages.

"""
    AcpConnection

A connection to one agent that speaks ACP. `make_agent_connection(:acp; …)` makes
one, and the generics of the kernel's `AgentModule` drive it.

- `command`     — the program of the agent and its arguments, as
                  `["claude-agent-acp"]`.
- `environment` — the variables that the agent gets beside the environment of
                  this process.
- `directory`   — where the agent starts, and where a session works when the
                  caller names no other place.
- `session_meta` — the `_meta` that `session/new` sends, for an agent that reads
                  options there: a dictionary, or its JSON text. Empty sends none.
                  `claude-agent-acp` reads `claudeCode.options` there, so
                  `{"claudeCode": {"options": {"thinking": {"type": "adaptive",
                  "display": "summarized"}}}}` makes it send the summary of its
                  reasoning.
- `streams`     — `(input, output)` to talk on instead of a process, for an
                  agent in this process; `nothing` starts `command`.

`transport` is the connection of `AgentClientProtocol` while the agent runs.
`agent_info`, `agent_capabilities` and `auth_methods` hold what the agent said in
`initialize`. `turns` holds the prompt that runs in each session.
`session_options` holds the last options of each session, and
`waiting_session_events` the latest update of each kind of the session — its
options, its usage, its title, its commands — that came while no prompt ran,
for the next prompt.
"""
mutable struct AcpConnection
    command::Vector{String}
    environment::Dict{String,String}
    directory::String
    session_meta::Dict{String,Any}
    streams::Union{Nothing,Tuple{IO,IO}}
    transport::Union{Nothing,ACP.Connection}
    agent_info::Union{Nothing,ACP.Implementation}
    agent_capabilities::ACP.AgentCapabilities
    auth_methods::Vector{ACP.AuthMethod}
    turns::Dict{String,AcpTurn}
    session_options::Dict{String,Vector{AgentOption}}
    waiting_session_events::Dict{String,Dict{DataType,Any}}
    turns_lock::ReentrantLock
end

make_agent_connection(::Val{:acp}; command::AbstractVector{<:AbstractString} = String[],
                      environment::AbstractDict = Dict{String,String}(),
                      directory::AbstractString = pwd(),
                      session_meta::Union{AbstractDict,AbstractString} = Dict{String,Any}(),
                      streams::Union{Nothing,Tuple{IO,IO}} = nothing) =
    AcpConnection(String.(command), Dict{String,String}(environment), String(directory),
                  _read_session_meta(session_meta), streams, nothing,
                  nothing, ACP.AgentCapabilities(), ACP.AuthMethod[],
                  Dict{String,AcpTurn}(), Dict{String,Vector{AgentOption}}(),
                  Dict{String,Dict{DataType,Any}}(), ReentrantLock())

_read_session_meta(meta::AbstractDict) = Dict{String,Any}(meta)
function _read_session_meta(text::AbstractString)
    isempty(strip(text)) && return Dict{String,Any}()
    meta = try
        ACP.read_json(text)
    catch exception
        exception isa ArgumentError || rethrow()
        nothing
    end
    meta isa Dict{String,Any} || error("The session options of the agent are no JSON object: $(text)")
    meta
end

"""
    AcpClientHandler(connection)

The handler that answers the agent of one `AcpConnection`: the updates of its
sessions, and its questions for the person.
"""
struct AcpClientHandler <: ACP.ClientHandler
    connection::AcpConnection
end

function start_agent_connection!(connection::AcpConnection)
    # An agent that ended is started again. Its sessions ended with it.
    transport = connection.transport
    if transport !== nothing
        ACP.is_connection_open(transport) && return connection
        stop_agent_connection!(connection)
    end
    connection.transport = _open_connection_transport(connection)
    result = try
        ACP.send_request!(connection.transport, ACP.InitializeRequest(
            protocol_version = ACP.PROTOCOL_VERSION,
            client_capabilities = ACP.ClientCapabilities(
                fs = ACP.FileSystemCapabilities(read_text_file = false, write_text_file = false),
                terminal = false),
            client_info = ACP.Implementation(
                name = "projectured", title = "ProjecturEd",
                version = string(something(pkgversion(Base.moduleroot(@__MODULE__)), v"0.0.0"))));
            timeout = 60)
    catch
        stop_agent_connection!(connection)
        rethrow()
    end
    version = get(ACP.get_json(result), "protocolVersion", nothing)
    if version != ACP.PROTOCOL_VERSION
        stop_agent_connection!(connection)
        error("The agent speaks ACP version $(something(version, "unknown")), " *
              "and this client speaks version $(ACP.PROTOCOL_VERSION).")
    end
    # A field that does not follow the schema reads as absent, so such an agent
    # still starts.
    connection.agent_info = _read_or_default(() -> result.agent_info, nothing)
    connection.agent_capabilities = _read_or_default(() -> result.agent_capabilities, ACP.AgentCapabilities())
    connection.auth_methods = _read_or_default(() -> result.auth_methods, ACP.AuthMethod[])
    connection
end

function _read_or_default(read::Function, default)
    try
        read()
    catch exception
        exception isa ArgumentError || rethrow()
        default
    end
end

function _open_connection_transport(connection::AcpConnection)
    handler = AcpClientHandler(connection)
    if connection.streams !== nothing
        input, output = connection.streams
        return ACP.open_connection(handler, output, input)
    end
    isempty(connection.command) && error("The agent has no command.")
    command = addenv(Cmd(Cmd(connection.command); dir = connection.directory), connection.environment)
    try
        ACP.open_connection(handler, command; log_line = _log_agent_line)
    catch exception
        exception isa Base.IOError || rethrow()
        error("The agent command `$(join(connection.command, ' '))` can not start: " *
              sprint(showerror, exception) * ". Install the agent, or set its command " *
              "in the settings of the assistant.")
    end
end

# The standard error of an agent holds its own log. It goes to the debug log, so
# a person who asks for it sees it, and nobody else does.
_log_agent_line(line) = @debug "agent" line

function open_agent_session!(connection::AcpConnection; directory::AbstractString = connection.directory,
                             mcp_servers::AbstractVector = Any[], on_event = nothing)
    transport = _get_started_transport(connection)
    request = ACP.NewSessionRequest(
        cwd = String(directory),
        mcp_servers = ACP.McpServer[_make_mcp_server(server) for server in mcp_servers],
        meta = isempty(connection.session_meta) ? nothing : connection.session_meta)
    result = try
        ACP.send_request!(transport, request; timeout = 120)
    catch exception
        exception isa ACP.ProtocolException && exception.code == ACP.AUTHENTICATION_REQUIRED &&
            error(_format_sign_in_message(connection))
        rethrow()
    end
    session_id = result.session_id
    _store_session_options!(connection, session_id, get(ACP.get_json(result), "configOptions", Any[]), on_event)
    session_id
end

function set_agent_option!(connection::AcpConnection, session_id::AbstractString,
                           option_id::AbstractString, value::AbstractString; on_event = nothing)
    result = ACP.send_request!(_get_started_transport(connection),
        ACP.SetSessionConfigOptionRequestValueId(session_id = String(session_id),
                                                 config_id = String(option_id), value = String(value));
        timeout = 60)
    _store_session_options!(connection, session_id, get(ACP.get_json(result), "configOptions", Any[]), on_event)
    nothing
end

# The options of an answer, kept for the session and given to `on_event`.
function _store_session_options!(connection::AcpConnection, session_id::AbstractString, list, on_event)
    options = _read_agent_options(list)
    lock(() -> connection.session_options[String(session_id)] = options, connection.turns_lock)
    on_event === nothing || on_event(AgentOptionsUpdate(options))
    nothing
end

_make_mcp_server(server) = ACP.McpServerHttp(
    name = String(server.name), url = String(server.url),
    headers = [ACP.HttpHeader(name = String(first(header)), value = String(last(header)))
               for header in server.headers])

# What the agent said about its sign-in, as a sentence for a person. The
# client starts no sign-in itself: the person signs in with the flow of the agent.
function _format_sign_in_message(connection::AcpConnection)
    info = connection.agent_info === nothing ? Dict{String,Any}() : ACP.get_json(connection.agent_info)
    title = string(get(info, "title", get(info, "name", "The agent")))
    ways = String[]
    for method in connection.auth_methods
        json = ACP.get_json(method)
        description = get(json, "description", nothing)
        push!(ways, description isa AbstractString ? String(description) :
                    string(get(json, "name", get(json, "id", ""))))
    end
    title * " needs a sign-in." *
        (isempty(ways) ? "" : " " * join(ways, " Or: ") * (endswith(last(ways), ".") ? "" : "."))
end

function send_agent_prompt!(connection::AcpConnection, session_id::AbstractString,
                            prompt::AbstractVector; on_event::Function)
    transport = _get_started_transport(connection)
    request = ACP.PromptRequest(session_id = String(session_id),
                                prompt = ACP.ContentBlock[_make_prompt_content(content) for content in prompt])
    turn = AcpTurn(on_event)
    # The updates of the session that came while no prompt ran go first, under
    # the lock, so a newer update that the reader gives the turn comes after them.
    lock(connection.turns_lock) do
        connection.turns[session_id] = turn
        waiting = pop!(connection.waiting_session_events, session_id, nothing)
        waiting === nothing || foreach(on_event, values(waiting))
    end
    try
        result = ACP.send_request!(transport, request)
        Symbol(string(get(ACP.get_json(result), "stopReason", "end_turn")))
    finally
        lock(() -> delete!(connection.turns, session_id), connection.turns_lock)
        _cancel_waiting_replies!(turn)
        foreach(on_event, _close_open_block!(Any[], turn))
    end
end

_make_prompt_content(content::LlmText) = ACP.TextContent(text = content.text)
_make_prompt_content(content) =
    throw(ArgumentError("An ACP prompt takes text, not a $(nameof(typeof(content)))."))

function cancel_agent_prompt!(connection::AcpConnection, session_id::AbstractString)
    transport = _get_started_transport(connection)
    ACP.send_notification!(transport, ACP.CancelNotification(session_id = String(session_id)))
    turn = lock(() -> get(connection.turns, session_id, nothing), connection.turns_lock)
    turn === nothing || _cancel_waiting_replies!(turn)
    nothing
end

function close_agent_session!(connection::AcpConnection, session_id::AbstractString)
    lock(connection.turns_lock) do
        delete!(connection.session_options, session_id)
        delete!(connection.waiting_session_events, session_id)
    end
    transport = connection.transport
    transport === nothing && return nothing
    capabilities = get(ACP.get_json(connection.agent_capabilities), "sessionCapabilities", nothing)
    capabilities isa AbstractDict && haskey(capabilities, "close") || return nothing
    try
        ACP.send_request!(transport, ACP.CloseSessionRequest(session_id = String(session_id)); timeout = 30)
    catch exception
        @warn "The agent did not close its session." exception
    end
    nothing
end

function stop_agent_connection!(connection::AcpConnection)
    turns = lock(() -> collect(values(connection.turns)), connection.turns_lock)
    foreach(_cancel_waiting_replies!, turns)
    transport = connection.transport
    connection.transport = nothing
    transport === nothing || ACP.close_connection!(transport)
    nothing
end

function _get_started_transport(connection::AcpConnection)
    transport = connection.transport
    transport === nothing && error("The agent connection is not started.")
    transport
end

# A `session/update` goes to the prompt that runs in its session. An update of
# the session that comes outside a prompt waits for the next prompt, and another
# update outside a prompt is dropped. `AgentClientProtocol` drops every other
# notification unread.
function ACP.receive_notification(handler::AcpClientHandler, notification::ACP.SessionNotification, transport)
    connection = handler.connection
    session_id = notification.session_id
    update = ACP.get_json(notification.update)
    turn = lock(() -> get(connection.turns, session_id, nothing), connection.turns_lock)
    kind = get(update, "sessionUpdate", "")
    events = kind == "current_mode_update" ? _translate_mode_update(connection, session_id, update) :
             kind == "config_option_update" ?
                 Any[AgentOptionsUpdate(_read_agent_options(get(update, "configOptions", Any[])))] :
             kind == "usage_update" ? Any[_read_usage_update(update)] :
             kind == "session_info_update" ? Any[AgentSessionInfoUpdate(_read_session_title(update))] :
             kind == "available_commands_update" ?
                 Any[AgentCommandsUpdate(_read_agent_commands(get(update, "availableCommands", Any[])))] :
             turn === nothing ? Any[] : _translate_session_update!(turn, update)
    lock(connection.turns_lock) do
        # The options of a session stay current also outside a prompt.
        for event in events
            event isa AgentOptionsUpdate && (connection.session_options[session_id] = event.options)
        end
        # The turn is read again under the lock, so an update that comes as a
        # prompt starts goes either to the waiting updates or to the prompt.
        turn = get(connection.turns, session_id, nothing)
        if turn === nothing
            waiting = get!(() -> Dict{DataType,Any}(), connection.waiting_session_events, session_id)
            for event in events
                event isa Union{AgentOptionsUpdate,AgentUsageUpdate,AgentSessionInfoUpdate,
                                AgentCommandsUpdate} &&
                    (waiting[typeof(event)] = event)
            end
        else
            foreach(turn.on_event, events)
        end
    end
    nothing
end

# A new mode, as the options of the session with the option of the category
# `:mode` set to it.
function _translate_mode_update(connection::AcpConnection, session_id::String, update::Dict{String,Any})
    mode = get(update, "currentModeId", nothing)
    options = lock(() -> get(connection.session_options, session_id, nothing), connection.turns_lock)
    (mode isa AbstractString && options !== nothing) || return Any[]
    Any[AgentOptionsUpdate(_set_current_value(options, option -> option.category === :mode, String(mode)))]
end

# The request goes to the person as an `AgentPermissionRequest`, and the task of
# the request waits for the reply. A request outside a prompt is cancelled, and
# so is a request that the agent withdraws with `$/cancel_request`. A request for
# a file or a terminal gets "method not found" from `AgentClientProtocol`,
# because the client offers neither in `initialize`.
function ACP.answer_request(handler::AcpClientHandler, request::ACP.RequestPermissionRequest, context)
    connection = handler.connection
    json = ACP.get_json(request)
    turn = lock(() -> get(connection.turns, request.session_id, nothing), connection.turns_lock)
    turn === nothing && return _make_cancelled_answer()
    tool_call = get(json, "toolCall", nothing)
    options = AgentPermissionOption[
        AgentPermissionOption(string(get(option, "optionId", "")), string(get(option, "name", "")),
                              something(_find_symbol(option, "kind"), :allow_once))
        for option in get(json, "options", Any[]) if option isa Dict{String,Any}]
    choice = Channel{Union{Nothing,String}}(1)
    is_answered = Threads.Atomic{Bool}(false)
    reply = function (option_id)
        Threads.atomic_xchg!(is_answered, true) && return false
        put!(choice, option_id === nothing ? nothing : String(option_id))
        true
    end
    lock(() -> push!(turn.waiting_replies, reply), connection.turns_lock)
    ACP.add_cancel_callback!(() -> reply(nothing), context)
    # A request that the agent withdrew already does not reach the person.
    isready(choice) || turn.on_event(AgentPermissionRequest(
        tool_call isa Dict{String,Any} ? _read_tool_call(tool_call) : AgentToolCallUpdate(""),
        options, reply))
    option_id = take!(choice)
    lock(() -> filter!(waiting -> waiting !== reply, turn.waiting_replies), connection.turns_lock)
    option_id === nothing && return _make_cancelled_answer()
    ACP.RequestPermissionResponse(outcome = ACP.SelectedPermissionOutcome(option_id = option_id))
end

_make_cancelled_answer() = ACP.RequestPermissionResponse(outcome = ACP.RequestPermissionOutcomeCancelled())

function _cancel_waiting_replies!(turn::AcpTurn)
    for reply in copy(turn.waiting_replies)
        reply(nothing)
    end
    nothing
end
