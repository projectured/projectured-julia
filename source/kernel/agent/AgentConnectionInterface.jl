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
    open_agent_session!(connection; directory, mcp_servers = [], instructions = "", session_id = "",
                        on_event = nothing, events = nothing) -> String

Open a session of the agent, and answer its id. The agent works in
`directory`. It connects to each of `mcp_servers`, a named tuple
`(name, url, headers)` that names an MCP server over HTTP: `headers` is a
`Vector{Pair{String,String}}` that the agent sends with each request.
`instructions`, when not empty, is text that the agent adds to its system
prompt: what its host is, and how to use the tools of the host. An agent that
has no way to take it ignores it.

With `session_id`, the connection resumes that session, with the history that
the agent keeps for it, when the agent can; `directory` must then be the folder
of that session. When the agent can not resume it, the connection opens a new
session. So an id that is not `session_id` says that the agent does not have
the history of the old session.

`on_event`, when given, gets the events of the open: an `AgentOptionsUpdate`
with the options of the session. The connection keeps no reference to it after
the call, so a caller can capture what it must not store.

An event that the agent sends later goes to one of two places. An event during
a prompt goes to the `on_event` of that prompt. An event between two prompts
goes to `events`, an [`AgentEventQueue`](@ref), in the order that the agent
sent it: the options, the usage, the title and the commands of the session,
and the work of a subagent or of a background task that goes on after a
prompt. The caller takes them with [`take_agent_events!`](@ref). Without
`events`, an event between two prompts is dropped.

Throws an [`AgentSignInException`](@ref) when the agent needs a sign-in.
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
`:refusal` or `:cancelled`. Throws an [`AgentSignInException`](@ref) when the
agent needs a sign-in, as after [`sign_out_agent!`](@ref).
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
    cancel_agent_subagent!(connection, session_id, subagent_id)

Ask the agent to stop the work of its subagent `subagent_id` in the session,
the `id` of an `AgentSubagentUpdate`. The subagent stays, and a later
`AgentSubagentUpdate` reports its new state. A connection that can not cancel
the work of a subagent does nothing.
"""
function cancel_agent_subagent! end

"""
    stop_agent_background_task!(connection, session_id, task_id) -> Bool

Ask the agent to stop its background task `task_id` in the session, the `id` of
an `AgentBackgroundTaskUpdate`, and answer whether the agent stopped it. A task
that does not run, a stop that the agent refuses, and a connection that can not
stop a background task answer `false`. A later `AgentBackgroundTaskUpdate`
reports the end of the task.
"""
function stop_agent_background_task! end

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

"""
    has_agent_steering(connection) -> Bool

Whether the agent of `connection` takes a prompt into a turn that runs, as a
person who writes while the agent works. A connection that has not started
answers `false`.
"""
function has_agent_steering end

"""
    steer_agent_prompt!(connection, session_id, prompt) -> Bool

Send `prompt`, a vector of `LlmContent`, into the turn of the session that runs.
The agent reads it at its next step, or in a turn of its own just after the one
that runs, and the events of its answer reach the `on_event` of the prompt that
runs. Answers whether the agent took it: `false` when it can not, when no turn
runs, or when it refused, and the caller then sends the prompt after the turn.
"""
function steer_agent_prompt! end

"""
    has_agent_sign_out(connection) -> Bool

Whether the agent of `connection` signs out when asked. A connection that has
not started answers `false`.
"""
function has_agent_sign_out end

"""
    sign_out_agent!(connection) -> Bool

Sign the agent of `connection` out. It forgets the sign-in of the person, and
its next session or prompt throws an [`AgentSignInException`](@ref). Answers
`false`, and does nothing, when the agent can not sign out.
"""
function sign_out_agent! end
