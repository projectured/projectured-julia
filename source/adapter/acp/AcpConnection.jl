# Fragment of `AcpModule` — `AcpConnection`, the client side of one agent: its
# start and the agreement on the protocol, its sessions, its prompts, and the
# answers to what the agent asks.

# The version of ACP that this client speaks.
const ACP_PROTOCOL_VERSION = 1

# The JSON-RPC code with which an agent says that it needs a sign-in.
const ACP_AUTHENTICATION_REQUIRED = -32000

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

`agent_info`, `agent_capabilities` and `auth_methods` hold what the agent said in
`initialize`. `turns` holds the prompt that runs in each session, and
`withdrawable_replies` the reply of each request that waits for a person, by
its JSON-RPC id, so the agent can withdraw it with `\$/cancel_request`.
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
    transport::Union{Nothing,AcpTransport}
    agent_info::Dict{String,Any}
    agent_capabilities::Dict{String,Any}
    auth_methods::Vector{Any}
    turns::Dict{String,AcpTurn}
    withdrawable_replies::Dict{Any,Function}
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
                  Dict{String,Any}(), Dict{String,Any}(), Any[],
                  Dict{String,AcpTurn}(), Dict{Any,Function}(),
                  Dict{String,Vector{AgentOption}}(), Dict{String,Dict{DataType,Any}}(),
                  ReentrantLock())

_read_session_meta(meta::AbstractDict) = Dict{String,Any}(meta)
function _read_session_meta(text::AbstractString)
    isempty(strip(text)) && return Dict{String,Any}()
    meta = try
        _make_plain(JSON3.read(text))
    catch exception
        exception isa ArgumentError || rethrow()
        nothing
    end
    meta isa Dict{String,Any} || error("The session options of the agent are no JSON object: $(text)")
    meta
end

function start_agent_connection!(connection::AcpConnection)
    # An agent that ended is started again. Its sessions ended with it.
    transport = connection.transport
    if transport !== nothing
        _is_transport_open(transport) && return connection
        stop_agent_connection!(connection)
    end
    connection.transport = _open_connection_transport(connection)
    result = try
        send_acp_request!(connection.transport, "initialize", Dict{String,Any}(
            "protocolVersion" => ACP_PROTOCOL_VERSION,
            "clientCapabilities" => Dict{String,Any}(
                "fs" => Dict{String,Any}("readTextFile" => false, "writeTextFile" => false),
                "terminal" => false),
            "clientInfo" => Dict{String,Any}(
                "name" => "projectured", "title" => "ProjecturEd",
                "version" => string(something(pkgversion(Base.moduleroot(@__MODULE__)), v"0.0.0"))));
            timeout = 60)
    catch
        stop_agent_connection!(connection)
        rethrow()
    end
    version = get(result, "protocolVersion", nothing)
    if version != ACP_PROTOCOL_VERSION
        stop_agent_connection!(connection)
        error("The agent speaks ACP version $(something(version, "unknown")), " *
              "and this client speaks version $(ACP_PROTOCOL_VERSION).")
    end
    connection.agent_info = _get_object(result, "agentInfo")
    connection.agent_capabilities = _get_object(result, "agentCapabilities")
    authentication = get(result, "authMethods", nothing)
    connection.auth_methods = authentication isa Vector{Any} ? authentication : Any[]
    connection
end

function _open_connection_transport(connection::AcpConnection)
    handlers = (; on_notification = (method, params) -> _receive_notification(connection, method, params),
                  on_request = (method, params, id) -> _answer_request(connection, method, params, id))
    connection.streams === nothing ||
        return open_acp_transport(connection.streams...; handlers...)
    isempty(connection.command) && error("The agent has no command.")
    command = addenv(Cmd(Cmd(connection.command); detach = true, dir = connection.directory),
                     connection.environment)
    try
        open_acp_transport(command; handlers...)
    catch exception
        exception isa Base.IOError || rethrow()
        error("The agent command `$(join(connection.command, ' '))` can not start: " *
              sprint(showerror, exception) * ". Install the agent, or set its command " *
              "in the settings of the assistant.")
    end
end

function open_agent_session!(connection::AcpConnection; directory::AbstractString = connection.directory,
                             mcp_servers::AbstractVector = Any[], on_event = nothing)
    transport = _get_started_transport(connection)
    params = Dict{String,Any}("cwd" => String(directory),
                              "mcpServers" => Any[_render_mcp_server(server) for server in mcp_servers])
    isempty(connection.session_meta) || (params["_meta"] = connection.session_meta)
    result = try
        send_acp_request!(transport, "session/new", params; timeout = 120)
    catch exception
        exception isa AcpRequestException && exception.code == ACP_AUTHENTICATION_REQUIRED &&
            error(_format_sign_in_message(connection))
        rethrow()
    end
    session_id = string(result["sessionId"])
    _store_session_options!(connection, session_id, get(result, "configOptions", Any[]), on_event)
    session_id
end

function set_agent_option!(connection::AcpConnection, session_id::AbstractString,
                           option_id::AbstractString, value::AbstractString; on_event = nothing)
    result = send_acp_request!(_get_started_transport(connection), "session/set_config_option",
        Dict{String,Any}("sessionId" => String(session_id), "configId" => String(option_id),
                         "value" => String(value)); timeout = 60)
    _store_session_options!(connection, session_id, get(result, "configOptions", Any[]), on_event)
    nothing
end

# The options of an answer, kept for the session and given to `on_event`.
function _store_session_options!(connection::AcpConnection, session_id::AbstractString, list, on_event)
    options = _read_agent_options(list)
    lock(() -> connection.session_options[String(session_id)] = options, connection.turns_lock)
    on_event === nothing || on_event(AgentOptionsUpdate(options))
    nothing
end

_render_mcp_server(server) = Dict{String,Any}(
    "type" => "http", "name" => String(server.name), "url" => String(server.url),
    "headers" => Any[Dict{String,Any}("name" => String(first(header)), "value" => String(last(header)))
                     for header in server.headers])

# What the agent said about its sign-in, as a sentence for a person. The
# client starts no sign-in itself: the person signs in with the flow of the agent.
function _format_sign_in_message(connection::AcpConnection)
    title = string(get(connection.agent_info, "title", get(connection.agent_info, "name", "The agent")))
    ways = String[]
    for method in connection.auth_methods
        method isa Dict{String,Any} || continue
        description = get(method, "description", nothing)
        push!(ways, description isa AbstractString ? String(description) :
                    string(get(method, "name", get(method, "id", ""))))
    end
    title * " needs a sign-in." *
        (isempty(ways) ? "" : " " * join(ways, " Or: ") * (endswith(last(ways), ".") ? "" : "."))
end

function send_agent_prompt!(connection::AcpConnection, session_id::AbstractString,
                            prompt::AbstractVector; on_event::Function)
    transport = _get_started_transport(connection)
    turn = AcpTurn(on_event)
    # The updates of the session that came while no prompt ran go first, under
    # the lock, so a newer update that the reader gives the turn comes after them.
    lock(connection.turns_lock) do
        connection.turns[session_id] = turn
        waiting = pop!(connection.waiting_session_events, session_id, nothing)
        waiting === nothing || foreach(on_event, values(waiting))
    end
    try
        result = send_acp_request!(transport, "session/prompt", Dict{String,Any}(
            "sessionId" => String(session_id),
            "prompt" => Any[_render_prompt_content(content) for content in prompt]))
        Symbol(string(get(result, "stopReason", "end_turn")))
    finally
        lock(() -> delete!(connection.turns, session_id), connection.turns_lock)
        _cancel_waiting_replies!(turn)
        foreach(on_event, _close_open_block!(Any[], turn))
    end
end

_render_prompt_content(content::LlmText) = Dict{String,Any}("type" => "text", "text" => content.text)
_render_prompt_content(content) =
    throw(ArgumentError("An ACP prompt takes text, not a $(nameof(typeof(content)))."))

function cancel_agent_prompt!(connection::AcpConnection, session_id::AbstractString)
    transport = _get_started_transport(connection)
    send_acp_notification!(transport, "session/cancel", Dict{String,Any}("sessionId" => String(session_id)))
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
    capabilities = _get_object(connection.agent_capabilities, "sessionCapabilities")
    haskey(capabilities, "close") || return nothing
    try
        send_acp_request!(transport, "session/close", Dict{String,Any}("sessionId" => String(session_id));
                         timeout = 30)
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
    transport === nothing || close_acp_transport!(transport)
    nothing
end

function _get_started_transport(connection::AcpConnection)
    transport = connection.transport
    transport === nothing && error("The agent connection is not started.")
    transport
end

# A `session/update` goes to the prompt that runs in its session, and a
# `$/cancel_request` withdraws the request of the agent that it names. An update
# outside a prompt, and every other notification, is dropped unread.
function _receive_notification(connection::AcpConnection, method::String, params::Dict{String,Any})
    if method == "\$/cancel_request"
        request_id = get(params, "requestId", nothing)
        reply = lock(() -> get(connection.withdrawable_replies, request_id, nothing), connection.turns_lock)
        reply === nothing || reply(nothing)
        return nothing
    end
    method == "session/update" || return nothing
    session_id = string(get(params, "sessionId", ""))
    turn = lock(() -> get(connection.turns, session_id, nothing), connection.turns_lock)
    update = get(params, "update", nothing)
    update isa Dict{String,Any} || return nothing
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

# The requests of the agent that the client answers. A request for a file or a
# terminal gets "method not found", because the client offers neither in
# `initialize`.
function _answer_request(connection::AcpConnection, method::String, params::Dict{String,Any}, id)
    method == "session/request_permission" && return _answer_permission_request(connection, params, id)
    throw(AcpRequestException(ACP_METHOD_NOT_FOUND, "The client has no method `$(method)`."))
end

const ACP_CANCELLED_OUTCOME = Dict{String,Any}("outcome" => Dict{String,Any}("outcome" => "cancelled"))

# The request goes to the person as an `AgentPermissionRequest`, and the task of
# the request waits for the reply. A request outside a prompt is cancelled, and
# so is a request that the agent withdraws.
function _answer_permission_request(connection::AcpConnection, params::Dict{String,Any}, id)
    session_id = string(get(params, "sessionId", ""))
    turn = lock(() -> get(connection.turns, session_id, nothing), connection.turns_lock)
    turn === nothing && return ACP_CANCELLED_OUTCOME
    tool_call = get(params, "toolCall", nothing)
    options = AgentPermissionOption[
        AgentPermissionOption(string(get(option, "optionId", "")), string(get(option, "name", "")),
                              something(_find_symbol(option, "kind"), :allow_once))
        for option in get(params, "options", Any[]) if option isa Dict{String,Any}]
    choice = Channel{Union{Nothing,String}}(1)
    is_answered = Threads.Atomic{Bool}(false)
    reply = function (option_id)
        Threads.atomic_xchg!(is_answered, true) && return false
        put!(choice, option_id === nothing ? nothing : String(option_id))
        true
    end
    lock(connection.turns_lock) do
        push!(turn.waiting_replies, reply)
        connection.withdrawable_replies[id] = reply
    end
    turn.on_event(AgentPermissionRequest(
        tool_call isa Dict{String,Any} ? _read_tool_call(tool_call) : AgentToolCallUpdate(""),
        options, reply))
    option_id = take!(choice)
    lock(connection.turns_lock) do
        filter!(waiting -> waiting !== reply, turn.waiting_replies)
        delete!(connection.withdrawable_replies, id)
    end
    option_id === nothing && return ACP_CANCELLED_OUTCOME
    Dict{String,Any}("outcome" => Dict{String,Any}("outcome" => "selected", "optionId" => option_id))
end

function _cancel_waiting_replies!(turn::AcpTurn)
    for reply in copy(turn.waiting_replies)
        reply(nothing)
    end
    nothing
end

function _get_object(object, key::String)
    value = object isa Dict{String,Any} ? get(object, key, nothing) : nothing
    value isa Dict{String,Any} ? value : Dict{String,Any}()
end
