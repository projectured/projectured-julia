# Fragment of `AcpModule` — `AcpConnection`, the client side of one agent: its
# start and the agreement on the protocol, its sessions, its prompts, and the
# answers to what the agent asks. A connection of `AgentClientProtocol` carries
# the messages.

"""
    AcpConnection

A connection to one agent that speaks ACP. `make_agent_connection(:acp; …)` makes
one, and the generics of the kernel's `AgentModule` drive it.

- `command`     — the program of the agent and its arguments, as
                  `["claude-agent-acp"]`. Empty starts the built-in agent of
                  `ClaudeCodeACP` in this process, which runs the `claude`
                  program that the person installed.
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
`session_options` holds the last options of each session. `session_queues`
holds the queue of each session that opened, or `nothing` for a session that
opened with none. `session_parents` holds the parent of each child session, the
session of a subagent, while it works. `session_frames` holds the frame of the
updates of a session that runs no prompt: of a child session that works, and of
a session with a queue between two prompts. `finished_parents` holds the parent
of each child whose work ended, so its late updates still find their way, and
`finished_children` the order in which they ended, for each session that the
client opened, at most `FINISHED_SUBAGENT_LIMIT` of them. `compaction_summaries`
holds the summary of each compaction that runs, by session and compaction id,
and `message_recipients` the recipient of the last message between sessions in
each session. `opening_count` counts the opens that wait for their answer;
while one waits, `opening_frames` and `opening_events` hold the frame and the
events of a session with no queue and no parent, until the open hands them to
its session. `turns_lock` guards all of these.

The events of a session reach its queue while no prompt runs in it, and the
`on_event` of `send_agent_prompt!` while one runs. A prompt takes the events
only after the last event of the time before it is in the queue, so a caller
that puts the events of `on_event` into the same queue has all of them in their
order.
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
    has_steering::Bool
    turns::Dict{String,AcpTurn}
    session_options::Dict{String,Vector{AgentOption}}
    session_queues::Dict{String,Union{Nothing,AgentEventQueue}}
    session_parents::Dict{String,String}
    session_frames::Dict{String,AcpTurn}
    finished_parents::Dict{String,String}
    finished_children::Dict{String,Vector{String}}
    compaction_summaries::Dict{Tuple{String,String},String}
    message_recipients::Dict{String,Tuple{String,String}}
    opening_count::Int
    opening_frames::Dict{String,AcpTurn}
    opening_events::Dict{String,Vector{Any}}
    turns_lock::ReentrantLock
end

# How many children whose work ended a session that the client opened
# remembers, so a late update of one reaches the session and the record stays
# bounded.
const FINISHED_SUBAGENT_LIMIT = 256

make_agent_connection(::Val{:acp}; command::AbstractVector{<:AbstractString} = String[],
                      environment::AbstractDict = Dict{String,String}(),
                      directory::AbstractString = pwd(),
                      session_meta::Union{AbstractDict,AbstractString} = Dict{String,Any}(),
                      streams::Union{Nothing,Tuple{IO,IO}} = nothing) =
    AcpConnection(String.(command), Dict{String,String}(environment), String(directory),
                  _read_session_meta(session_meta), streams, nothing,
                  nothing, ACP.AgentCapabilities(), ACP.AuthMethod[], false,
                  Dict{String,AcpTurn}(), Dict{String,Vector{AgentOption}}(),
                  Dict{String,Union{Nothing,AgentEventQueue}}(), Dict{String,String}(), Dict{String,AcpTurn}(),
                  Dict{String,String}(), Dict{String,Vector{String}}(), Dict{Tuple{String,String},String}(),
                  Dict{String,Tuple{String,String}}(), 0, Dict{String,AcpTurn}(), Dict{String,Vector{Any}}(),
                  ReentrantLock())

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
            # The work of an agent: its subagents, its plans with an id, its
            # notices, its compactions, and its background tasks, which the
            # extension notification `_session/background_task` carries.
            client_capabilities = ACP.ClientCapabilities(
                fs = ACP.FileSystemCapabilities(read_text_file = false, write_text_file = false),
                terminal = false, auth = ACP.AuthCapabilities(terminal = true),
                elicitation = ACP.ElicitationCapabilities(form = ACP.ElicitationFormCapabilities()),
                session = ACP.ClientSessionCapabilities(notices = ACP.NoticeCapabilities(),
                                                        compaction = ACP.CompactionCapabilities()),
                subagents = ACP.SubagentCapabilities(), plan = ACP.PlanCapabilities(),
                meta = Dict{String,Any}("backgroundTasks" => Dict{String,Any}())),
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
    connection.has_steering = _has_steering_meta(get(ACP.get_json(result), "_meta", nothing))
    connection
end

# Whether the answer to `initialize` says, in `_meta.steering.supported`, that the
# agent answers the extension method `_session/steering`.
function _has_steering_meta(meta)
    meta isa AbstractDict || return false
    steering = get(meta, "steering", nothing)
    steering isa AbstractDict && get(steering, "supported", false) === true
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
    isempty(connection.command) && return _open_builtin_agent(handler)
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

# The built-in agent: `ClaudeCodeACP` on a task of this process, on two streams.
# The close of the connection ends the input of the agent, which then ends each
# of its sessions and their `claude`.
function _open_builtin_agent(handler::AcpClientHandler)
    to_agent = Base.BufferStream()
    to_client = Base.BufferStream()
    errormonitor(@async ClaudeCodeACP.serve_agent(; input = to_agent, output = to_client))
    ACP.open_connection(handler, to_client, to_agent)
end

# The standard error of an agent holds its own log. It goes to the debug log, so
# a person who asks for it sees it, and nobody else does.
_log_agent_line(line) = @debug "agent" line

# A kept session resumes with `session/resume` when the answer to `initialize`
# has `sessionCapabilities.resume`. When the answer to the resume is an error of
# the protocol, as for a session that the agent does not have any more, a new
# session opens, and the caller sees its new id. A needed sign-in, a timeout and
# a closed connection go to the caller. An agent can send an update of the
# session just after its answer, before this call has the id, so the updates of
# a session with no queue and no parent wait while an open runs, and the open
# puts them into the queue of its session.
function open_agent_session!(connection::AcpConnection; directory::AbstractString = connection.directory,
                             mcp_servers::AbstractVector = Any[], instructions::AbstractString = "",
                             session_id::AbstractString = "", on_event = nothing,
                             events::Union{Nothing,AgentEventQueue} = nothing)
    transport = _get_started_transport(connection)
    has_system_prompt = _has_session_capability(connection, "systemPrompt")
    meta = has_system_prompt ? connection.session_meta : _add_instructions(connection.session_meta, instructions)
    meta = isempty(meta) ? nothing : meta
    system_prompt = has_system_prompt ? String(instructions) : ""
    servers = ACP.McpServer[_make_mcp_server(server) for server in mcp_servers]
    lock(() -> connection.opening_count += 1, connection.turns_lock)
    try
        opened_id = nothing
        if !isempty(session_id) && _has_session_capability(connection, "resume")
            result = try
                _send_session_request!(connection, transport, _add_system_prompt!(ACP.ResumeSessionRequest(
                    session_id = String(session_id), cwd = String(directory), mcp_servers = servers, meta = meta),
                    system_prompt))
            catch exception
                exception isa ACP.ProtocolException || rethrow()
                @debug "The agent did not resume the session, so a new session opens." exception
                nothing
            end
            if result !== nothing
                opened_id = String(session_id)
                _store_session_options!(connection, opened_id, get(ACP.get_json(result), "configOptions", Any[]),
                                        on_event)
            end
        end
        if opened_id === nothing
            result = _send_session_request!(connection, transport, _add_system_prompt!(
                ACP.NewSessionRequest(cwd = String(directory), mcp_servers = servers, meta = meta), system_prompt))
            opened_id = result.session_id
            _store_session_options!(connection, opened_id, get(ACP.get_json(result), "configOptions", Any[]),
                                    on_event)
        end
        _register_session!(connection, opened_id, events)
        opened_id
    finally
        lock(connection.turns_lock) do
            connection.opening_count -= 1
            if connection.opening_count == 0
                empty!(connection.opening_frames)
                empty!(connection.opening_events)
            end
        end
    end
end

# The queue of a session that opened, and the frame and the events that came
# for it before the open had its id. A frame of an earlier open of the same id
# ends first, in its own queue. An agent in a child process gives the id of that
# process first; the built-in agent runs in this process, so only the
# `_meta.processId` of its `session_info_update` names the process that does the
# work.
function _register_session!(connection::AcpConnection, session_id::String,
                            events::Union{Nothing,AgentEventQueue})
    lock(connection.turns_lock) do
        _close_session_frames!(connection, [session_id])
        connection.session_queues[session_id] = events
        frame = pop!(connection.opening_frames, session_id, nothing)
        waiting = pop!(connection.opening_events, session_id, Any[])
        events === nothing && return nothing
        transport = connection.transport
        process_id = transport === nothing ? 0 : Int(transport.process_id)
        isempty(connection.command) || process_id <= 0 ||
            put_agent_event!(events, AgentSessionInfoUpdate(nothing; process_id))
        foreach(event -> put_agent_event!(events, event), waiting)
        if frame !== nothing
            frame.on_event = event -> put_agent_event!(events, event)
            connection.session_frames[session_id] = frame
        end
        nothing
    end
end

# A request that opens or resumes a session. An agent that needs a sign-in
# answers `AUTHENTICATION_REQUIRED`, which becomes an `AgentSignInException`.
function _send_session_request!(connection::AcpConnection, transport, request)
    try
        ACP.send_request!(transport, request; timeout = 120)
    catch exception
        _is_sign_in_error(exception) && throw(_make_sign_in_exception(connection))
        rethrow()
    end
end

_is_sign_in_error(exception) =
    exception isa ACP.ProtocolException && exception.code == ACP.AUTHENTICATION_REQUIRED

# Whether the answer to `initialize` has the session method `name` in its
# `sessionCapabilities`, such as `"resume"` or `"close"`.
function _has_session_capability(connection::AcpConnection, name::AbstractString)
    capabilities = get(ACP.get_json(connection.agent_capabilities), "sessionCapabilities", nothing)
    capabilities isa AbstractDict && haskey(capabilities, name)
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

# A request that opens or resumes a session, with `instructions` in its field
# `systemPrompt`, for an agent that advertises `sessionCapabilities.systemPrompt`:
# one text block that the agent appends to its system prompt. The field is
# unstable in the schema, and the request type has no property for it, so it
# goes into the JSON of the request.
function _add_system_prompt!(request, instructions::AbstractString)
    isempty(instructions) && return request
    ACP.get_json(request)["systemPrompt"] = Dict{String,Any}(
        "mode" => "append",
        "content" => Any[Dict{String,Any}("type" => "text", "text" => String(instructions))])
    request
end

# The `_meta` of a session with `instructions` in it, for an agent that does not
# advertise `sessionCapabilities.systemPrompt`. The instructions go where the
# Claude agents of ACP read an addition to the system prompt,
# `claudeCode.options.systemPrompt.append`, beside the other options of the
# `_meta`. Another agent ignores that key.
function _add_instructions(meta::Dict{String,Any}, instructions::AbstractString)
    isempty(instructions) && return meta
    merged = deepcopy(meta)
    claude = get!(() -> Dict{String,Any}(), merged, "claudeCode")
    claude isa Dict{String,Any} || return meta
    options = get!(() -> Dict{String,Any}(), claude, "options")
    options isa Dict{String,Any} || return meta
    options["systemPrompt"] = Dict{String,Any}("type" => "preset", "preset" => "claude_code",
                                               "append" => String(instructions))
    merged
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

# What the agent said about its sign-in: its title, the ways that this editor can
# run, and a sentence for a person. The person signs in with the flow of the
# agent, in a terminal or in the flow that the agent runs itself, such as in the
# browser; this editor shows no sign-in form of its own.
function _make_sign_in_exception(connection::AcpConnection)
    methods = AgentSignInMethod[]
    for method in connection.auth_methods
        sign_in = _make_sign_in_method(connection, method)
        sign_in === nothing || push!(methods, sign_in)
    end
    AgentSignInException(_get_agent_title(connection), methods, _format_sign_in_message(connection))
end

function _get_agent_title(connection::AcpConnection)
    info = connection.agent_info === nothing ? Dict{String,Any}() : ACP.get_json(connection.agent_info)
    string(get(info, "title", get(info, "name", "The agent")))
end

# A method as this editor runs it. A method of the type `terminal` is a command:
# the invocation of the agent with the `args` and the `env` of the method. A
# method of the type `agent`, the default type of ACP, has no command: the agent
# runs it itself at `sign_in_agent!`. A method of another type, `nothing`.
function _make_sign_in_method(connection::AcpConnection, method)
    json = ACP.get_json(method)
    type = get(json, "type", "agent")
    description = get(json, "description", nothing)
    make_method(command) = AgentSignInMethod(string(get(json, "id", "")), string(get(json, "name", get(json, "id", ""))),
                                             description isa AbstractString ? String(description) : "", command)
    type == "agent" && return make_method(nothing)
    type == "terminal" || return nothing
    arguments = get(json, "args", Any[])
    environment = get(json, "env", Dict{String,Any}())
    arguments isa AbstractVector && environment isa AbstractDict || return nothing
    command = _make_agent_invocation(connection, String[string(argument) for argument in arguments],
                                     Dict{String,String}(string(key) => string(value) for (key, value) in environment))
    command === nothing ? nothing : make_method(command)
end

# The command of the agent with `arguments` added and `environment` over its
# own, in its folder. The built-in agent runs in this process and has no command
# line. Its program answers `--login` with the command of `make_login_command`,
# so that command stands for it.
function _make_agent_invocation(connection::AcpConnection, arguments::Vector{String},
                                environment::Dict{String,String})
    if isempty(connection.command)
        arguments == ["--login"] || return nothing
        return addenv(Cmd(ClaudeCodeACP.make_login_command(); dir = connection.directory), environment)
    end
    addenv(Cmd(Cmd([connection.command..., arguments...]); dir = connection.directory),
           merge(connection.environment, environment))
end

# What the agent said about its sign-in, as a sentence for a person.
function _format_sign_in_message(connection::AcpConnection)
    title = _get_agent_title(connection)
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
                                prompt = _make_prompt_blocks(connection, prompt))
    turn = AcpTurn(on_event)
    _start_turn_delivery!(turn)
    # The block that the updates between two prompts left open ends in the queue
    # of the session, under the lock, before the prompt takes the updates.
    # A request that waits in that queue waits now until the end of the prompt.
    lock(connection.turns_lock) do
        frame = pop!(connection.session_frames, session_id, nothing)
        if frame !== nothing
            _send_turn_events!(frame, _close_open_block!(Any[], frame))
            append!(turn.waiting_replies, frame.waiting_replies)
        end
        connection.turns[session_id] = turn
    end
    try
        result = try
            ACP.send_request!(transport, request)
        catch exception
            _is_sign_in_error(exception) && throw(_make_sign_in_exception(connection))
            rethrow()
        end
        Symbol(string(get(ACP.get_json(result), "stopReason", "end_turn")))
    finally
        lock(() -> delete!(connection.turns, session_id), connection.turns_lock)
        _cancel_waiting_replies!(turn)
        _send_turn_events!(turn, _close_open_block!(Any[], turn))
        # Each event of the prompt reached `on_event` when the prompt answers.
        _end_turn_delivery!(turn)
    end
end

# The blocks of a prompt. A picture goes as an image when the agent says that it
# takes images in a prompt; else a line says that the picture is left out.
function _make_prompt_blocks(connection::AcpConnection, prompt::AbstractVector)
    has_images = _has_prompt_capability(connection, "image")
    ACP.ContentBlock[_make_prompt_content(content, has_images) for content in prompt]
end

_make_prompt_content(content::LlmText, ::Bool) = ACP.TextContent(text = content.text)
_make_prompt_content(content::LlmImage, has_images::Bool) =
    has_images ? ACP.ImageContent(data = base64encode(content.data), mime_type = content.media_type) :
                 ACP.TextContent(text = "(A picture is left out: the agent takes no pictures.)")
_make_prompt_content(content, ::Bool) =
    throw(ArgumentError("An ACP prompt takes text and pictures, not a $(nameof(typeof(content)))."))

function _has_prompt_capability(connection::AcpConnection, name::AbstractString)
    capabilities = get(ACP.get_json(connection.agent_capabilities), "promptCapabilities", nothing)
    capabilities isa AbstractDict && get(capabilities, name, false) === true
end

# A cancel answers each request of the session that waits, in its prompt or in
# its queue, as cancelled.
function cancel_agent_prompt!(connection::AcpConnection, session_id::AbstractString)
    transport = _get_started_transport(connection)
    ACP.send_notification!(transport, ACP.CancelNotification(session_id = String(session_id)))
    turns = lock(connection.turns_lock) do
        AcpTurn[turn for turn in (get(connection.turns, session_id, nothing),
                                  get(connection.session_frames, session_id, nothing)) if turn !== nothing]
    end
    foreach(_cancel_waiting_replies!, turns)
    nothing
end

# The work of a subagent stops with the notification `session/cancel` of its
# child session, which stays open.
function cancel_agent_subagent!(connection::AcpConnection, session_id::AbstractString,
                                subagent_id::AbstractString)
    ACP.send_notification!(_get_started_transport(connection),
                           ACP.CancelNotification(session_id = String(subagent_id)))
    nothing
end

# The extension method `_session/stop_background_task {sessionId, taskId}`
# answers an empty object when the agent stopped the task, and an error when it
# did not.
function stop_agent_background_task!(connection::AcpConnection, session_id::AbstractString,
                                     task_id::AbstractString)
    result = try
        ACP.send_request!(_get_started_transport(connection), "_session/stop_background_task",
                          Dict{String,Any}("sessionId" => String(session_id), "taskId" => String(task_id));
                          timeout = 30)
    catch exception
        exception isa ACP.ProtocolException || rethrow()
        return false
    end
    result isa AbstractDict
end

function close_agent_session!(connection::AcpConnection, session_id::AbstractString)
    lock(() -> _forget_session!(connection, String(session_id)), connection.turns_lock)
    transport = connection.transport
    transport === nothing && return nothing
    _has_session_capability(connection, "close") || return nothing
    try
        ACP.send_request!(transport, ACP.CloseSessionRequest(session_id = String(session_id)); timeout = 30)
    catch exception
        @warn "The agent did not close its session." exception
    end
    nothing
end

# The sessions of the agent end with it: each frame ends its open block where
# its events go, and the connection forgets every session. An open that waits
# throws, and counts itself out of `opening_count`.
function stop_agent_connection!(connection::AcpConnection)
    turns = lock(connection.turns_lock) do
        _close_session_frames!(connection, collect(keys(connection.session_frames)))
        foreach(empty!, (connection.session_options, connection.session_queues, connection.session_parents,
                         connection.session_frames, connection.finished_parents, connection.finished_children,
                         connection.compaction_summaries, connection.message_recipients,
                         connection.opening_frames, connection.opening_events))
        collect(values(connection.turns))
    end
    foreach(_cancel_waiting_replies!, turns)
    transport = connection.transport
    connection.transport = nothing
    transport === nothing || ACP.close_connection!(transport)
    nothing
end

has_agent_steering(connection::AcpConnection) = connection.transport !== nothing && connection.has_steering

# The extension method `_session/steering` sends the prompt into the turn that
# runs; its params have the shape of a `session/prompt`, so a `PromptRequest`
# writes them, with the type of each block. The outcome `injected` says that the
# turn took it, and `startedNewTurn` that the turn had ended and the agent began a
# new one; any other outcome, and an error, is a prompt that the agent did not take.
function steer_agent_prompt!(connection::AcpConnection, session_id::AbstractString, prompt::AbstractVector)
    has_agent_steering(connection) || return false
    params = ACP.get_json(ACP.PromptRequest(session_id = String(session_id),
        prompt = _make_prompt_blocks(connection, prompt)))
    result = try
        ACP.send_request!(_get_started_transport(connection), "_session/steering", params; timeout = 60)
    catch exception
        exception isa ACP.ProtocolException || rethrow()
        return false
    end
    result isa AbstractDict && get(result, "outcome", nothing) in ("injected", "startedNewTurn")
end

# A sign-in of the type `agent` runs in the agent, such as in the browser of the
# person, so its answer waits as long as the person takes, up to five minutes. A
# request that gets no answer in that time is withdrawn, so the agent stops its
# sign-in too.
function sign_in_agent!(connection::AcpConnection, method_id::AbstractString)
    _has_agent_sign_in_method(connection, method_id) || return false
    request = ACP.start_request!(_get_started_transport(connection),
                                 ACP.AuthenticateRequest(method_id = String(method_id)))
    try
        ACP.wait_for_answer(request; timeout = 300)
    catch
        ACP.cancel_request!(request)
        rethrow()
    end
    true
end

# Whether the agent names `method_id` among its sign-in methods of the type `agent`.
_has_agent_sign_in_method(connection::AcpConnection, method_id::AbstractString) =
    any(method -> (json = ACP.get_json(method);
                   get(json, "id", nothing) == method_id && get(json, "type", "agent") == "agent"),
        connection.auth_methods)

function has_agent_sign_out(connection::AcpConnection)
    connection.transport === nothing && return false
    auth = get(ACP.get_json(connection.agent_capabilities), "auth", nothing)
    auth isa AbstractDict && get(auth, "logout", nothing) isa AbstractDict
end

function sign_out_agent!(connection::AcpConnection)
    has_agent_sign_out(connection) || return false
    ACP.send_request!(_get_started_transport(connection), ACP.LogoutRequest(); timeout = 60)
    true
end

function _get_started_transport(connection::AcpConnection)
    transport = connection.transport
    transport === nothing && error("The agent connection is not started.")
    transport
end

# A `session/update` goes, as its events, to the prompt that runs in its session,
# or between two prompts to the queue of the session. An update of a child
# session goes the same way for its parent, as the `event` of an
# `AgentSubagentUpdate`, one level for each parent, up to the session that the
# client opened. A session that opened with no queue drops the updates between
# two prompts. The options of a session stay current in any case.
# `AgentClientProtocol` drops every other notification of the protocol unread.
function ACP.receive_notification(handler::AcpClientHandler, notification::ACP.SessionNotification, transport)
    connection = handler.connection
    session_id = notification.session_id
    update = ACP.get_json(notification.update)
    lock(connection.turns_lock) do
        turn = _find_session_turn!(connection, session_id)
        events = _translate_connection_update!(connection, turn, session_id, update)
        if _is_working_session(connection, session_id)
            for event in events
                event isa AgentOptionsUpdate && (connection.session_options[session_id] = event.options)
            end
        end
        turn === nothing || _send_turn_events!(turn, events)
        # A child that went idle has ended its work once its last events are on
        # their way.
        for event in events
            event isa AgentSubagentUpdate && event.event === nothing && event.state === :idle &&
                _finish_subagent!(connection, event.id)
        end
    end
    nothing
end

# The extension notification `_session/background_task` goes where an update of
# its session goes. A notification of another method is dropped unread.
function ACP.receive_notification(handler::AcpClientHandler, method::String, params, transport)
    method == "_session/background_task" && params isa Dict{String,Any} || return nothing
    session_id = _find_string(params, "sessionId")
    session_id === nothing && return nothing
    connection = handler.connection
    event = _read_background_task(params)
    lock(() -> _deliver_session_event!(connection, session_id, event), connection.turns_lock)
    nothing
end

# The events of one update of a session. The updates of the session itself need
# no frame, and the connection keeps its options also when the update goes
# nowhere; a `subagent_update` makes its child session known, also then, and a
# message between sessions goes to its recipient.
function _translate_connection_update!(connection::AcpConnection, turn::Union{Nothing,AcpTurn},
                                       session_id::String, update::Dict{String,Any})
    kind = get(update, "sessionUpdate", "")
    kind == "current_mode_update" && return _translate_mode_update(connection, session_id, update)
    kind == "config_option_update" &&
        return Any[AgentOptionsUpdate(_read_agent_options(get(update, "configOptions", Any[])))]
    kind == "usage_update" && return Any[_read_usage_update(update)]
    kind == "session_info_update" && return Any[_read_session_info_update(update)]
    kind == "available_commands_update" &&
        return Any[AgentCommandsUpdate(_read_agent_commands(get(update, "availableCommands", Any[])))]
    kind == "subagent_update" && return _translate_subagent_update!(connection, session_id, update)
    if kind in ("session_message", "session_message_chunk")
        _deliver_session_message!(connection, session_id, update)
        return Any[]
    end
    turn === nothing && return Any[]
    kind == "user_message_chunk" && return _translate_subagent_prompt!(connection, turn, session_id, update)
    kind == "compaction_update" && return _translate_compaction_update!(connection, session_id, update)
    kind == "compaction_summary_chunk" && return _translate_compaction_chunk!(connection, session_id, update)
    _translate_session_update!(turn, update)
end

# A `subagent_update` names a child session of `parent_id`. It adds nothing for
# a session that the connection does not know, as one that closed, and nothing
# for a child that is `parent_id` or one of its parents, which would make the
# updates go round. A child whose work ended comes back for a state of work;
# another update of it reaches its parent and adds nothing. The child goes idle
# when its work ends, which closes the block that its frame left open, as the
# end of a prompt does.
function _translate_subagent_update!(connection::AcpConnection, parent_id::String, update::Dict{String,Any})
    event = _read_subagent_update(update)
    child_id = event.id
    (isempty(child_id) || !_is_known_session(connection, parent_id)) && return Any[]
    if child_id in _collect_session_chain(connection, parent_id)
        @warn "An ACP agent named a session as a subagent of itself or of its own subagent, and the client " *
              "ignores it." child_id parent_id maxlog = 1
        return Any[]
    end
    if !haskey(connection.finished_parents, child_id)
        connection.session_parents[child_id] = parent_id
    elseif event.state in (:running, :requires_action)
        _forget_finished_subagent!(connection, child_id)
        connection.session_parents[child_id] = parent_id
    end
    events = Any[]
    frame = get(connection.session_frames, child_id, nothing)
    if event.state === :idle && frame !== nothing
        for stop in _close_open_block!(Any[], frame)
            push!(events, AgentSubagentUpdate(child_id; event = stop))
        end
    end
    push!(events, event)
end

# A child whose work ended keeps only its parent, in `finished_parents`, under
# the session that the client opened, which keeps the last
# `FINISHED_SUBAGENT_LIMIT` of them.
function _finish_subagent!(connection::AcpConnection, child_id::String)
    parent_id = pop!(connection.session_parents, child_id, nothing)
    parent_id === nothing && return nothing
    delete!(connection.session_frames, child_id)
    delete!(connection.session_options, child_id)
    connection.finished_parents[child_id] = parent_id
    finished = get!(Vector{String}, connection.finished_children, last(_collect_session_chain(connection, parent_id)))
    push!(finished, child_id)
    length(finished) > FINISHED_SUBAGENT_LIMIT && delete!(connection.finished_parents, popfirst!(finished))
    nothing
end

function _forget_finished_subagent!(connection::AcpConnection, child_id::String)
    root_id = last(_collect_session_chain(connection, child_id))
    delete!(connection.finished_parents, child_id)
    finished = get(connection.finished_children, root_id, nothing)
    finished === nothing || filter!(!=(child_id), finished)
    nothing
end

# The `user_message_chunk` of a child session is the prompt of its subagent, an
# `LlmMessage` of the role `:user`, one for each chunk. A chunk of a session that
# the client opened is the prompt that the client sent, and gives no event.
function _translate_subagent_prompt!(connection::AcpConnection, turn::AcpTurn, session_id::String,
                                     update::Dict{String,Any})
    _find_parent_session(connection, session_id) === nothing && return Any[]
    _make_subagent_prompt!(turn, _read_content_text(get(update, "content", nothing)))
end

# The prompt of a subagent, after the block that its frame left open; none for
# an empty text.
function _make_subagent_prompt!(turn::AcpTurn, text::String)
    isempty(text) && return Any[]
    push!(_close_open_block!(Any[], turn), LlmMessage(:user, LlmContent[LlmText(text)]))
end

# A `session_message` or a `session_message_chunk` whose recipient is a child
# session is a prompt of its subagent, as its `user_message_chunk` is, one for
# each update. A message whose recipient is a session that the client opened, a
# child that the connection does not know, or none at all, is dropped: the
# client sends its own prompts, and the kernel has no event for a message
# between two sessions. A chunk that leaves out its recipient continues the last
# message of its session, when the message id is the same.
function _deliver_session_message!(connection::AcpConnection, session_id::String, update::Dict{String,Any})
    message_id = _read_id(get(update, "messageId", nothing))
    recipient_id = _find_string(update, "recipientSessionId")
    if recipient_id === nothing
        last_message = get(connection.message_recipients, session_id, nothing)
        last_message !== nothing && first(last_message) == message_id && (recipient_id = last(last_message))
    end
    recipient_id === nothing && return nothing
    _is_known_session(connection, session_id) && (connection.message_recipients[session_id] = (message_id, recipient_id))
    _find_parent_session(connection, recipient_id) === nothing && return nothing
    content = get(update, "content", nothing)
    blocks = content isa Vector{Any} ? content : content isa Dict{String,Any} ? Any[content] : Any[]
    turn = _find_session_turn!(connection, recipient_id)
    turn === nothing && return nothing
    text = join(filter(!isempty, String[_read_content_text(block) for block in blocks]), '\n')
    _send_turn_events!(turn, _make_subagent_prompt!(turn, text))
    nothing
end

# A `compaction_update`, with the summary that its compaction has: the summary of
# the update, else the summary that its chunks gave. The connection keeps the
# summary of a compaction while it is in progress.
function _translate_compaction_update!(connection::AcpConnection, session_id::String, update::Dict{String,Any})
    event = _read_compaction_update(update)
    key = (session_id, event.id)
    summary = something(event.summary, get(connection.compaction_summaries, key, nothing), Some(nothing))
    if event.status === :in_progress && summary !== nothing
        connection.compaction_summaries[key] = summary
    else
        delete!(connection.compaction_summaries, key)
    end
    Any[AgentCompactionUpdate(event.id, event.status, summary)]
end

# A `compaction_summary_chunk` adds the text of its block to the summary of its
# compaction, on a line of its own, and gives the compaction with that summary.
function _translate_compaction_chunk!(connection::AcpConnection, session_id::String, update::Dict{String,Any})
    compaction_id = _read_id(get(update, "compactionId", nothing))
    text = _read_content_text(get(update, "content", nothing))
    (isempty(compaction_id) || isempty(text)) && return Any[]
    key = (session_id, compaction_id)
    before = get(connection.compaction_summaries, key, "")
    summary = connection.compaction_summaries[key] = isempty(before) ? text : before * "\n" * text
    Any[AgentCompactionUpdate(compaction_id, :in_progress, summary)]
end

# The turn whose frame and whose `on_event` take the updates of a session, under
# the lock: the prompt that runs in it; else, for a child session, its frame,
# whose events go to its parent; else, for a session with a queue, its frame
# between two prompts, whose events go to the queue; else, while an open runs,
# the frame that the open hands to its session. Else `nothing`, and the updates
# go nowhere. A child whose work ended keeps no frame: each update gets one for
# itself.
function _find_session_turn!(connection::AcpConnection, session_id::String)
    turn = get(connection.turns, session_id, nothing)
    turn === nothing || return turn
    turn = get(connection.session_frames, session_id, nothing)
    turn === nothing || return turn
    haskey(connection.session_parents, session_id) &&
        return connection.session_frames[session_id] = AcpTurn(event ->
            _deliver_child_event!(connection, session_id, event))
    haskey(connection.finished_parents, session_id) &&
        return AcpTurn(event -> _deliver_child_event!(connection, session_id, event))
    if haskey(connection.session_queues, session_id)
        queue = connection.session_queues[session_id]
        queue === nothing && return nothing
        return connection.session_frames[session_id] = AcpTurn(event -> put_agent_event!(queue, event))
    end
    connection.opening_count > 0 || return nothing
    get!(connection.opening_frames, session_id) do
        AcpTurn(event -> push!(get!(Vector{Any}, connection.opening_events, session_id), event))
    end
end

# One event of a session, to where its updates go, under the lock.
function _deliver_session_event!(connection::AcpConnection, session_id::String, event)
    turn = _find_session_turn!(connection, session_id)
    turn === nothing || _send_turn_events!(turn, (event,))
    nothing
end

# One event of a child session, to its parent, as the event of an
# `AgentSubagentUpdate` of the child.
function _deliver_child_event!(connection::AcpConnection, child_id::String, event)
    parent_id = _find_parent_session(connection, child_id)
    parent_id === nothing || _deliver_session_event!(connection, parent_id, AgentSubagentUpdate(child_id; event))
    nothing
end

# The parent of a child session, also of one whose work ended; `nothing` for a
# session that the client opened.
_find_parent_session(connection::AcpConnection, session_id::String) =
    get(connection.session_parents, session_id, get(connection.finished_parents, session_id, nothing))

# A session and its parents, the session first and the session that the client
# opened last. A parent that is already on the chain ends it.
function _collect_session_chain(connection::AcpConnection, session_id::String)
    chain = String[session_id]
    while true
        parent_id = _find_parent_session(connection, last(chain))
        (parent_id === nothing || parent_id in chain) && return chain
        push!(chain, parent_id)
    end
end

# Whether the connection knows a session: a session that opened, a child, or,
# while an open waits, any session.
_is_known_session(connection::AcpConnection, session_id::String) =
    haskey(connection.session_queues, session_id) || haskey(connection.session_parents, session_id) ||
    haskey(connection.finished_parents, session_id) || connection.opening_count > 0

# Whether a session works: it opened and did not close, or it is a child whose
# work did not end.
_is_working_session(connection::AcpConnection, session_id::String) =
    haskey(connection.session_queues, session_id) || haskey(connection.session_parents, session_id) ||
    (connection.opening_count > 0 && !haskey(connection.finished_parents, session_id))

# The turn that takes a request of a session for a person, with the ids of the
# children that the request comes through, the innermost first: the prompt that
# runs in the session that the client opened, else its frame between two
# prompts, when it has a queue. `nothing` when the request has nowhere to go.
function _find_request_turn!(connection::AcpConnection, session_id::String)
    chain = _collect_session_chain(connection, session_id)
    root_id = last(chain)
    turn = get(connection.turns, root_id, nothing)
    if turn === nothing
        get(connection.session_queues, root_id, nothing) === nothing && return nothing
        turn = _find_session_turn!(connection, root_id)
    end
    turn, chain[1:end - 1]
end

# An event of a child session as the session that the client opened takes it:
# inside an `AgentSubagentUpdate` of each child on the way, the innermost first.
_wrap_subagent_event(child_ids::Vector{String}, event) =
    foldl((inner, child_id) -> AgentSubagentUpdate(child_id; event = inner), child_ids; init = event)

# Ends the frames of `session_ids`: the block that a frame left open ends where
# its events go, each request that waits in it is answered as cancelled, and the
# frames go.
function _close_session_frames!(connection::AcpConnection, session_ids::Vector{String})
    frames = AcpTurn[connection.session_frames[id] for id in session_ids if haskey(connection.session_frames, id)]
    for frame in frames
        _send_turn_events!(frame, _close_open_block!(Any[], frame))
        _cancel_waiting_replies!(frame)
    end
    foreach(id -> delete!(connection.session_frames, id), session_ids)
    nothing
end

# What the connection keeps of a session that closed, and of its children: their
# frames end, as at the stop of the agent.
function _forget_session!(connection::AcpConnection, session_id::String)
    session_ids = String[session_id]
    for child_id in union(keys(connection.session_parents), keys(connection.session_frames))
        child_id != session_id && last(_collect_session_chain(connection, child_id)) == session_id &&
            push!(session_ids, child_id)
    end
    _close_session_frames!(connection, session_ids)
    for finished_id in pop!(connection.finished_children, session_id, String[])
        delete!(connection.finished_parents, finished_id)
        push!(session_ids, finished_id)
    end
    for id in session_ids
        delete!(connection.session_options, id)
        delete!(connection.session_queues, id)
        delete!(connection.session_parents, id)
        delete!(connection.message_recipients, id)
    end
    filter!(entry -> !(first(first(entry)) in session_ids), connection.compaction_summaries)
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
# the request waits for the reply. It goes where an update of its session goes:
# to the prompt that runs, or between two prompts to the queue of the session,
# and a request of a child session as the event of an `AgentSubagentUpdate` of
# each child on the way. A request that waits in the queue waits until the end
# of the next prompt. A request of a session with no prompt and no queue is
# cancelled, and so is a request that the agent withdraws with
# `$/cancel_request`. A request for a file or a terminal gets "method not found"
# from `AgentClientProtocol`, because the client offers neither in `initialize`.
function ACP.answer_request(handler::AcpClientHandler, request::ACP.RequestPermissionRequest, context)
    connection = handler.connection
    json = ACP.get_json(request)
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
    ACP.add_cancel_callback!(() -> reply(nothing), context)
    event = AgentPermissionRequest(
        tool_call isa Dict{String,Any} ? _read_tool_call(tool_call) : AgentToolCallUpdate(""), options, reply)
    turn = lock(() -> _deliver_session_request!(connection, request.session_id, event, reply, choice),
                connection.turns_lock)
    turn === nothing && return _make_cancelled_answer()
    option_id = take!(choice)
    lock(() -> filter!(waiting -> waiting !== reply, turn.waiting_replies), connection.turns_lock)
    option_id === nothing && return _make_cancelled_answer()
    ACP.RequestPermissionResponse(outcome = ACP.SelectedPermissionOutcome(option_id = option_id))
end

_make_cancelled_answer() = ACP.RequestPermissionResponse(outcome = ACP.RequestPermissionOutcomeCancelled())

# A request of a session for a person, to the turn that takes it, with `reply`
# among the replies that wait there, under the lock; answers that turn, or
# `nothing` when the request has nowhere to go. A request that the agent
# withdrew already, whose `answer` is ready, does not reach the person.
function _deliver_session_request!(connection::AcpConnection, session_id::String, event, reply::Function,
                                   answer::Channel)
    target = _find_request_turn!(connection, session_id)
    target === nothing && return nothing
    turn, child_ids = target
    push!(turn.waiting_replies, reply)
    isready(answer) || _send_turn_events!(turn, (_wrap_subagent_event(child_ids, event),))
    turn
end

# A question of the agent goes to the person as an `AgentQuestionRequest`, and
# the task of the request waits for the reply: values accept the form, `nothing`
# declines it, and a cancel of the turn or of the request cancels it. It goes
# where a permission request goes. A form of a session with no prompt and no
# queue, and a request that is no form, such as a URL, are cancelled, because
# the client offers forms only.
function ACP.answer_request(handler::AcpClientHandler, request::ACP.CreateElicitationRequest, context)
    connection = handler.connection
    json = ACP.get_json(request)
    session_id = get(json, "sessionId", nothing)
    (session_id isa AbstractString && get(json, "mode", nothing) == "form") ||
        return ACP.CreateElicitationResponseCancel()
    fields = _read_question_fields(get(json, "requestedSchema", nothing))
    answer = Channel{Any}(1)
    is_answered = Threads.Atomic{Bool}(false)
    deliver(value) = (Threads.atomic_xchg!(is_answered, true) && return false; put!(answer, value); true)
    cancel = _ -> deliver(:cancel)
    ACP.add_cancel_callback!(() -> deliver(:cancel), context)
    event = AgentQuestionRequest(string(get(json, "message", "")), fields,
                                 values -> deliver(values === nothing ? :decline : values))
    turn = lock(() -> _deliver_session_request!(connection, String(session_id), event, cancel, answer),
                connection.turns_lock)
    turn === nothing && return ACP.CreateElicitationResponseCancel()
    value = take!(answer)
    lock(() -> filter!(waiting -> waiting !== cancel, turn.waiting_replies), connection.turns_lock)
    value === :cancel && return ACP.CreateElicitationResponseCancel()
    value === :decline && return ACP.CreateElicitationResponseDecline()
    ACP.CreateElicitationResponseAccept(content = Dict{String,Any}(
        name => answered for (name, answered) in value if any(field -> field.name == name, fields)))
end

# The fields of a form, one for each property of its schema. The protocol library
# reads a JSON object into a `Dict`, which keeps no order, so the fields come in
# the order of their names; an agent that names them `question_1`, `question_2`
# gets its order.
function _read_question_fields(schema)
    schema isa AbstractDict || return AgentQuestionField[]
    properties = get(schema, "properties", nothing)
    properties isa AbstractDict || return AgentQuestionField[]
    required = get(schema, "required", Any[])
    AgentQuestionField[_read_question_field(String(name), properties[name],
                                            required isa AbstractVector && name in required)
                       for name in sort!(collect(keys(properties)))]
end

# One property as a field. A string with options is a choice and an array of
# them is a choice of several; a number, an integer and a boolean are what they
# say; any other property is a text.
function _read_question_field(name::String, property, is_required::Bool)
    property isa Dict{String,Any} || return AgentQuestionField(name, name, "", :text, AgentOptionValue[], is_required)
    title = something(_find_string(property, "title"), name)
    description = something(_find_string(property, "description"), "")
    type = get(property, "type", "string")
    kind, options = if type == "string"
        options = _read_question_options(property)
        (isempty(options) ? :text : :choice), options
    elseif type == "array"
        items = get(property, "items", nothing)
        :choices, items isa Dict{String,Any} ? _read_question_options(items) : AgentOptionValue[]
    elseif type in ("number", "integer", "boolean")
        Symbol(type), AgentOptionValue[]
    else
        :text, AgentOptionValue[]
    end
    AgentQuestionField(name, title, description, kind, options, is_required)
end

# The options of an enum: `oneOf` or `anyOf`, each with a `const`, a `title` and
# a `description`, or else `enum`, whose values are their own titles.
function _read_question_options(schema::Dict{String,Any})
    for key in ("oneOf", "anyOf")
        list = get(schema, key, nothing)
        list isa AbstractVector || continue
        return AgentOptionValue[AgentOptionValue(string(get(option, "const", "")),
                                                 string(get(option, "title", get(option, "const", ""))),
                                                 something(_find_string(option, "description"), ""))
                                for option in list if option isa Dict{String,Any}]
    end
    values = get(schema, "enum", nothing)
    values isa AbstractVector || return AgentOptionValue[]
    AgentOptionValue[AgentOptionValue(string(value), string(value), "") for value in values]
end

function _cancel_waiting_replies!(turn::AcpTurn)
    for reply in copy(turn.waiting_replies)
        reply(nothing)
    end
    nothing
end
