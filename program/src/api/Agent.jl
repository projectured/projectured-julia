"""
    AgentModule

Abstract agent control-surface interface. An *agent server* is a channel that
lets an external AI agent inspect and manipulate a running editor — conceptually
another device/backend that reads operations from an agent and writes document
state back.

Concrete servers (e.g. the MCP server) live in their own modules / package
extensions and register methods for `make_agent_server` / `agent_server_start!`
/ `agent_server_stop!`. The editor loop drives an agent server only through
these generics, so it never names a concrete server type — letting the
implementation move into an optional extension whose type cannot be referenced
at load time.
"""
module AgentModule

export make_agent_server, agent_server_start!, agent_server_stop!

"""
    make_agent_server(kind::Symbol, editor; kwargs...)

Construct an agent server of the given `kind` (e.g. `:mcp`) bound to `editor`.
A missing method (its optional dependency not loaded) raises a helpful error.
"""
make_agent_server(kind::Symbol, editor; kwargs...) =
    make_agent_server(Val(kind), editor; kwargs...)
make_agent_server(::Val{K}, editor; kwargs...) where {K} = error(
    "No agent server registered for :$(K). Is the package/extension that " *
    "provides it loaded?")

"""
    agent_server_start!(server)

Start the agent server (begin processing in the background).
"""
function agent_server_start! end

"""
    agent_server_stop!(server)

Stop the agent server and release its resources.
"""
function agent_server_stop! end

end # module
