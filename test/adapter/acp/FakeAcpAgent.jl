# A fake ACP agent in this process, on the other end of two streams, for the
# tests of the client. It answers each request of the client with the handler
# of its method, records every message it gets, and can send notifications and
# requests of its own. It needs no network, no Node.js and no sign-in.

"""
    FakeAcpAgent(handlers)

An agent that answers the request `method` with `handlers[method](agent, params)`.
A handler answers a result, or throws an `AcpRequestException` for an error
answer. It runs on a task of its own, so it can send updates with
`send_fake_update` and ask the client with `ask_fake_client` before it answers.
A request with no handler gets "method not found".

`client_streams(agent)` gives the `(input, output)` that a connection talks on.
"""
mutable struct FakeAcpAgent
    from_client::Base.BufferStream
    to_client::Base.BufferStream
    handlers::Dict{String,Function}
    received::Vector{Dict{String,Any}}
    pending::Dict{Int,Channel{Dict{String,Any}}}
    next_id::Int
    lock::ReentrantLock
    reader::Union{Nothing,Task}
end

function FakeAcpAgent(handlers::AbstractDict = Dict{String,Function}())
    agent = FakeAcpAgent(Base.BufferStream(), Base.BufferStream(),
                         Dict{String,Function}(handlers), Dict{String,Any}[],
                         Dict{Int,Channel{Dict{String,Any}}}(), 0, ReentrantLock(), nothing)
    agent.reader = errormonitor(@async _read_fake_messages(agent))
    agent
end

client_streams(agent::FakeAcpAgent) = (agent.from_client, agent.to_client)

# The messages of the client with this method, in the order they came.
get_received(agent::FakeAcpAgent, method::AbstractString) =
    lock(() -> filter(message -> get(message, "method", nothing) == method, agent.received), agent.lock)

# A message after the agent closed its output goes nowhere, as for an agent that
# ended.
function send_fake_message(agent::FakeAcpAgent, message::AbstractDict)
    lock(agent.lock) do
        isopen(agent.to_client) && write(agent.to_client, JSON3.write(message), '\n')
    end
    nothing
end

send_fake_update(agent::FakeAcpAgent, session_id::AbstractString, update::AbstractDict) =
    send_fake_message(agent, Dict("jsonrpc" => "2.0", "method" => "session/update",
                                  "params" => Dict("sessionId" => session_id, "update" => update)))

# Ask the client, and wait at most ten seconds for its answer.
function ask_fake_client(agent::FakeAcpAgent, method::AbstractString, params::AbstractDict)
    channel = Channel{Dict{String,Any}}(1)
    id = lock(agent.lock) do
        agent.next_id += 1
        agent.pending[agent.next_id] = channel
        agent.next_id
    end
    send_fake_message(agent, Dict("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params))
    timedwait(() -> isready(channel), 10.0; pollint = 0.01) === :ok ||
        error("the client did not answer `$(method)`")
    take!(channel)
end

# The agent ends its output when the client closes its input, as a real agent
# ends at the end of its input.
function _read_fake_messages(agent::FakeAcpAgent)
    try
        for line in eachline(agent.from_client)
            isempty(line) && continue
            message = _make_fake_plain(JSON3.read(line))
            lock(() -> push!(agent.received, message), agent.lock)
            if haskey(message, "method") && haskey(message, "id")
                errormonitor(@async _answer_fake_request(agent, message))
            elseif haskey(message, "id")
                channel = lock(() -> get(agent.pending, message["id"], nothing), agent.lock)
                channel === nothing || put!(channel, message)
            end
        end
    finally
        close(agent.to_client)
    end
end

function _answer_fake_request(agent::FakeAcpAgent, message::Dict{String,Any})
    method = message["method"]
    params = get(message, "params", Dict{String,Any}())
    handler = get(agent.handlers, method, nothing)
    answer = try
        handler === nothing &&
            throw(AcpRequestException(-32601, "the fake agent has no method `$(method)`"))
        Dict("jsonrpc" => "2.0", "id" => message["id"], "result" => handler(agent, params))
    catch exception
        exception isa AcpRequestException || rethrow()
        Dict("jsonrpc" => "2.0", "id" => message["id"],
             "error" => Dict("code" => exception.code, "message" => exception.message))
    end
    send_fake_message(agent, answer)
end

_make_fake_plain(value::JSON3.Object) =
    Dict{String,Any}(String(key) => _make_fake_plain(item) for (key, item) in pairs(value))
_make_fake_plain(value::JSON3.Array) = Any[_make_fake_plain(item) for item in value]
_make_fake_plain(value::AbstractString) = String(value)
_make_fake_plain(value) = value

# An answer of `initialize` in the shape that `claude-agent-acp` 0.87.0 gives,
# with fewer capabilities and no `_meta`.
const FAKE_INITIALIZE_RESULT = Dict(
    "protocolVersion" => 1,
    "agentCapabilities" => Dict(
        "promptCapabilities" => Dict("image" => true, "embeddedContext" => true),
        "mcpCapabilities" => Dict("http" => true, "sse" => true),
        "loadSession" => true,
        "sessionCapabilities" => Dict("close" => Dict(), "list" => Dict(), "resume" => Dict())),
    "agentInfo" => Dict("name" => "fake-agent", "title" => "Fake Agent", "version" => "0.0.1"),
    "authMethods" => [Dict("id" => "fake-login", "name" => "Log in", "type" => "terminal",
                           "description" => "Run `fake /login` in the terminal", "args" => ["--cli"])])

# Options of a session in the shape that `claude-agent-acp` 0.87.0 gives, cut
# down, with the values of the model in a group.
const FAKE_CONFIG_OPTIONS = [
    Dict("id" => "mode", "name" => "Mode", "category" => "mode", "type" => "select",
         "currentValue" => "default",
         "options" => [Dict("value" => "default", "name" => "Manual"),
                       Dict("value" => "plan", "name" => "Plan")]),
    Dict("id" => "model", "name" => "Model", "category" => "model", "type" => "select",
         "currentValue" => "opus",
         "options" => [Dict("group" => "latest", "name" => "Latest",
                            "options" => [Dict("value" => "opus", "name" => "Opus 5.5"),
                                          Dict("value" => "sonnet", "name" => "Sonnet 5.5")])]),
    Dict("id" => "effort", "name" => "Effort", "category" => "thought_level", "type" => "select",
         "currentValue" => "high",
         "options" => [Dict("value" => "high", "name" => "High"), Dict("value" => "max", "name" => "Max")])]

# The handlers that a test starts from: an agent that starts, opens the session
# `session-1` with `FAKE_CONFIG_OPTIONS`, and ends each prompt with `end_turn`.
make_fake_handlers() = Dict{String,Function}(
    "initialize" => (agent, params) -> FAKE_INITIALIZE_RESULT,
    "session/new" => (agent, params) -> Dict("sessionId" => "session-1", "configOptions" => FAKE_CONFIG_OPTIONS),
    "session/prompt" => (agent, params) -> Dict("stopReason" => "end_turn"),
    "session/close" => (agent, params) -> Dict())

# A connection to a fake agent, started.
function make_fake_connection(agent::FakeAcpAgent; kwargs...)
    connection = make_agent_connection(:acp; streams = client_streams(agent), kwargs...)
    start_agent_connection!(connection)
end
