# Fragment of `AgentModule` — the external-agent **contract**: the seams of the
# direction in which this editor drives an agent that runs its own loop in
# another process. That agent owns its model, its tools and its history. The
# editor sends it a prompt, shows what it reports, and answers what it asks.
#
# Concrete connections live in their own packages and add methods to these
# generics, so a caller never names a concrete connection type. Nothing here
# carries a body — the fallback behaviours sit in `AgentConnectionDefaults.jl`.

"""
    make_agent_connection(kind::Symbol; kwargs...)

Make a connection of the given `kind` (e.g. `:acp`) to an external agent. The
connection starts nothing: [`start_agent_connection!`](@ref) starts the agent.

A connection package answers `make_agent_connection(::Val{kind}; kwargs...)`.
The `Symbol` entry dispatches to it, and a missing method (its package not
loaded) raises an error that lists the kinds that are loaded — both in
`AgentConnectionDefaults.jl`.
"""
function make_agent_connection end

"""
    start_agent_connection!(connection) -> connection

Start the agent of `connection` and agree with it on the protocol. A connection
that runs already stays as it is.
"""
function start_agent_connection! end

"""
    open_agent_session!(connection; directory, mcp_servers = [], instructions = "", on_event = nothing) -> String

Open a new session of the agent, and answer its id. The agent works in
`directory`. It connects to each of `mcp_servers`, a named tuple
`(name, url, headers)` that names an MCP server over HTTP: `headers` is a
`Vector{Pair{String,String}}` that the agent sends with each request.
`instructions`, when not empty, is text that the agent adds to its system
prompt: what its host is, and how to use the tools of the host. An agent that
has no way to take it ignores it.

`on_event`, when given, gets the events of the open: an `AgentOptionsUpdate`
with the options of the session. The connection keeps no reference to it after
the call, so a caller can capture what it must not store. An update that the
agent sends later reaches the `on_event` of the prompt that runs. An update of
the session that comes between two prompts — its options, its usage, its
title, its commands — waits, and the next prompt gets the latest of each kind
first.

Throws when the agent needs a sign-in, with a message that says how to sign in.
"""
function open_agent_session! end

"""
    set_agent_option!(connection, session_id, option_id, value; on_event = nothing)

Set the option `option_id` of the session to `value`, the `value` of one of the
`AgentOptionValue`s that the option lists. The agent answers with all its
options, which reach `on_event`, when given, as an `AgentOptionsUpdate`. The
connection keeps no reference to `on_event` after the call.
"""
function set_agent_option! end

"""
    send_agent_prompt!(connection, session_id, prompt; on_event) -> Symbol

Send `prompt`, a vector of `LlmContent`, to the session, and wait until the turn
of the agent ends. `on_event` gets each event of the turn as it arrives: an
`LlmTextStart`, `LlmTextDelta` or `LlmTextStop` for the text of the answer, the
same three of `LlmThinking…` for its reasoning, and an `AgentEvent` for what the
agent does and asks, and for its session: its options, its usage, its title,
its commands.
It is called on a task that is not the editor's.

Answers why the turn ended: `:end_turn`, `:max_tokens`, `:max_turn_requests`,
`:refusal` or `:cancelled`.
"""
function send_agent_prompt! end

"""
    cancel_agent_prompt!(connection, session_id)

Ask the agent to stop the turn of the session. Each request of the session that
waits for a person is answered as cancelled, and `send_agent_prompt!` then
answers `:cancelled`.
"""
function cancel_agent_prompt! end

"""
    close_agent_session!(connection, session_id)

Close the session: the agent stops its work in it and frees what it holds.
"""
function close_agent_session! end

"""
    stop_agent_connection!(connection)

Stop the agent of `connection`, with every session in it.
"""
function stop_agent_connection! end
